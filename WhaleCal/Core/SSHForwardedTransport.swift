@preconcurrency import Citadel
import Crypto
import Foundation
@preconcurrency import NIO
@preconcurrency import NIOSSH

enum SSHTransportEvent: Sendable {
    case bytes(Data)
    case closed
    case error(String)
}

/// Owns one SSH connection and one OpenSSH direct-tcpip channel. The target is
/// loopback on the SSH server, never a listener reachable from another host.
actor SSHForwardedTransport {
    private let configuration: SSHConnectionConfiguration
    private var client: SSHClient?
    private var channel: Channel?
    private var continuation: AsyncStream<SSHTransportEvent>.Continuation?

    init(configuration: SSHConnectionConfiguration = .current) {
        self.configuration = configuration
    }

    func open(identity: DeviceIdentity) async throws -> AsyncStream<SSHTransportEvent> {
        await close()
        try configuration.validate()

        let hostKey = try NIOSSHPublicKey(openSSHPublicKey: configuration.pinnedHostKey)
        let sshClient = try await SSHClient.connect(
            host: configuration.host,
            port: configuration.port,
            authenticationMethod: .ed25519(
                username: configuration.username,
                privateKey: identity.privateKey
            ),
            hostKeyValidator: .trustedKeys([hostKey]),
            reconnect: .never,
            connectTimeout: .seconds(15)
        )

        var capturedContinuation: AsyncStream<SSHTransportEvent>.Continuation?
        let stream = AsyncStream<SSHTransportEvent> { continuation in
            capturedContinuation = continuation
        }
        guard let capturedContinuation else {
            try? await sshClient.close()
            throw SSHTransportError.streamSetupFailed
        }
        self.continuation = capturedContinuation

        let originator = try SocketAddress(ipAddress: "127.0.0.1", port: 0)
        do {
            let forwardedChannel = try await sshClient.createDirectTCPIPChannel(
                using: SSHChannelType.DirectTCPIP(
                    targetHost: configuration.bridgeHost,
                    targetPort: configuration.bridgePort,
                    originatorAddress: originator
                )
            ) { channel in
                channel.pipeline.addHandler(
                    ForwardedByteHandler { event in
                        capturedContinuation.yield(event)
                    }
                )
            }
            self.client = sshClient
            self.channel = forwardedChannel
            return stream
        } catch {
            capturedContinuation.finish()
            self.continuation = nil
            try? await sshClient.close()
            throw error
        }
    }

    func send(_ data: Data) async throws {
        guard let channel, channel.isActive else { throw SSHTransportError.notConnected }
        var buffer = channel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        try await channel.writeAndFlush(buffer).get()
    }

    func close() async {
        continuation?.finish()
        continuation = nil
        if let channel { try? await channel.close() }
        channel = nil
        if let client { try? await client.close() }
        client = nil
    }
}

enum SSHTransportError: LocalizedError {
    case notConnected
    case streamSetupFailed

    var errorDescription: String? {
        switch self {
        case .notConnected: "The forwarded SSH channel is not connected."
        case .streamSetupFailed: "Could not create the forwarded byte stream."
        }
    }
}

private final class ForwardedByteHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    private let emit: @Sendable (SSHTransportEvent) -> Void

    init(emit: @escaping @Sendable (SSHTransportEvent) -> Void) {
        self.emit = emit
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        if let bytes = buffer.readBytes(length: buffer.readableBytes), !bytes.isEmpty {
            emit(.bytes(Data(bytes)))
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        emit(.closed)
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        emit(.error(error.localizedDescription))
        context.close(promise: nil)
    }
}
