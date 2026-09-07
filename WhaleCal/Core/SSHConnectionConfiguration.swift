import Foundation

/// Non-secret deployment settings. Keep your real hostname, account and public host
/// key in the ignored local JSON file, never in the published source or Git history.
struct SSHConnectionConfiguration: Codable, Sendable {
    var host: String
    var port: Int
    var username: String
    var bridgeHost: String
    var bridgePort: Int
    var pinnedHostKey: String

    static let current: Self = {
        guard let url = Bundle.main.url(forResource: "Connection.local", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let configuration = try? JSONDecoder().decode(Self.self, from: data) else {
            return Self(host: "", port: 22, username: "", bridgeHost: "127.0.0.1", bridgePort: 46282, pinnedHostKey: "")
        }
        return configuration
    }()

    func validate() throws {
        guard !host.isEmpty, !username.isEmpty, !host.hasSuffix(".example.com"),
              (1...65535).contains(port), (1...65535).contains(bridgePort),
              bridgeHost == "127.0.0.1", pinnedHostKey.hasPrefix("ssh-ed25519 ") else {
            throw ConfigurationError.missingSettings
        }
    }

    enum ConfigurationError: LocalizedError {
        case missingSettings
        var errorDescription: String? {
            "Configure your SSH host, username and verified Ed25519 host key in Connection.local.json, then rebuild. The calendar bridge must remain on 127.0.0.1."
        }
    }
}
