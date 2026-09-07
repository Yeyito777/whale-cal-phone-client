import Crypto
import Foundation
import Security

/// A device-local Ed25519 identity. The private key is generated on first use and
/// stored with a this-device-only Keychain accessibility class; it is never sent
/// to the server or included in the application bundle.
struct DeviceIdentity: @unchecked Sendable {
    let privateKey: Curve25519.Signing.PrivateKey
    let publicKeyOpenSSH: String
}

enum DeviceIdentityError: LocalizedError {
    case keychain(OSStatus)
    case malformedKey

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            return "Keychain error \(status): \(SecCopyErrorMessageString(status, nil) as String? ?? "unknown")"
        case .malformedKey:
            return "The device SSH key stored in Keychain is malformed."
        }
    }
}

enum DeviceIdentityStore {
    private static let service = (Bundle.main.bundleIdentifier ?? "org.whalecal.phone") + ".ssh"
    private static let account = "device-ed25519-v1"

    static func loadOrCreate() throws -> DeviceIdentity {
        let privateKey: Curve25519.Signing.PrivateKey
        if let bytes = try readKeyData() {
            do {
                privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: bytes)
            } catch {
                throw DeviceIdentityError.malformedKey
            }
        } else {
            privateKey = Curve25519.Signing.PrivateKey()
            try saveKeyData(Data(privateKey.rawRepresentation))
        }

        return DeviceIdentity(
            privateKey: privateKey,
            publicKeyOpenSSH: openSSHPublicKey(for: Data(privateKey.publicKey.rawRepresentation))
        )
    }

    private static func readKeyData() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw DeviceIdentityError.keychain(status)
        }
        return data
    }

    private static func saveKeyData(_ data: Data) throws {
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw DeviceIdentityError.keychain(status)
        }
    }

    /// OpenSSH public-key blob: string("ssh-ed25519") + string(raw public key).
    private static func openSSHPublicKey(for rawKey: Data) -> String {
        let algorithm = Data("ssh-ed25519".utf8)
        var blob = Data()
        blob.appendSSHString(algorithm)
        blob.appendSSHString(rawKey)
        return "ssh-ed25519 \(blob.base64EncodedString()) whale-cal-ios"
    }
}

private extension Data {
    mutating func appendSSHString(_ value: Data) {
        var length = UInt32(value.count).bigEndian
        Swift.withUnsafeBytes(of: &length) { append(contentsOf: $0) }
        append(value)
    }
}
