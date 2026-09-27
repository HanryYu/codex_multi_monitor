import Foundation
import Security

enum NonInteractiveKeychainError: LocalizedError, Sendable {
    case interactionStateReadFailed(OSStatus)
    case interactionStateWriteFailed(OSStatus)
    case interactionStateRestoreFailed(OSStatus)
    case readFailed(OSStatus)
    case updateFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .interactionStateReadFailed(let status):
            return "Could not read the Keychain interaction state (OSStatus \(status))."
        case .interactionStateWriteFailed(let status):
            return "Could not disable Keychain interaction (OSStatus \(status))."
        case .interactionStateRestoreFailed(let status):
            return "Could not restore the Keychain interaction state (OSStatus \(status))."
        case .readFailed(let status):
            return "The non-interactive Keychain read failed (OSStatus \(status))."
        case .updateFailed(let status):
            return "The non-interactive Keychain update failed (OSStatus \(status))."
        }
    }
}

/// Serializes the deprecated process-wide Keychain interaction switch so legacy
/// file-based keychains cannot display UI while a synchronous operation runs.
/// A per-query authentication UI policy is still supplied as defense in depth.
final class NonInteractiveKeychainGate: @unchecked Sendable {
    struct Client: @unchecked Sendable {
        let readInteractionAllowed: () -> (status: OSStatus, allowed: Bool)
        let setInteractionAllowed: (Bool) -> OSStatus

        static let live = Client(
            readInteractionAllowed: {
                var allowed = DarwinBoolean(false)
                let status = SecKeychainGetUserInteractionAllowed(&allowed)
                return (status, allowed.boolValue)
            },
            setInteractionAllowed: { allowed in
                SecKeychainSetUserInteractionAllowed(allowed)
            }
        )
    }

    static let shared = NonInteractiveKeychainGate(client: .live)

    private let lock = NSLock()
    private let client: Client

    init(client: Client) {
        self.client = client
    }

    func perform<T>(_ operation: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }

        let previous = client.readInteractionAllowed()
        guard previous.status == errSecSuccess else {
            throw NonInteractiveKeychainError.interactionStateReadFailed(previous.status)
        }

        let disabled = client.setInteractionAllowed(false)
        guard disabled == errSecSuccess else {
            throw NonInteractiveKeychainError.interactionStateWriteFailed(disabled)
        }

        let result = Result { try operation() }
        let restored = client.setInteractionAllowed(previous.allowed)
        guard restored == errSecSuccess else {
            throw NonInteractiveKeychainError.interactionStateRestoreFailed(restored)
        }
        return try result.get()
    }
}

enum NonInteractiveKeychain {
    static func genericPasswordQuery(
        service: String,
        account: String? = nil,
        returningData: Bool
    ) -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecUseAuthenticationUI: kSecUseAuthenticationUIFail,
        ]
        if let account {
            query[kSecAttrAccount] = account
        }
        if returningData {
            query[kSecReturnData] = true
            query[kSecMatchLimit] = kSecMatchLimitOne
        }
        return query
    }

    static func copyGenericPassword(service: String, account: String? = nil) throws -> Data? {
        let query = genericPasswordQuery(service: service, account: account, returningData: true)
        return try NonInteractiveKeychainGate.shared.perform {
            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            switch status {
            case errSecSuccess:
                guard let data = result as? Data else {
                    throw NonInteractiveKeychainError.readFailed(errSecDecode)
                }
                return data
            case errSecItemNotFound:
                return nil
            default:
                throw NonInteractiveKeychainError.readFailed(status)
            }
        }
    }

    static func updateGenericPassword(
        _ data: Data,
        service: String,
        account: String? = nil
    ) throws {
        let query = genericPasswordQuery(service: service, account: account, returningData: false)
        try NonInteractiveKeychainGate.shared.perform {
            let status = SecItemUpdate(
                query as CFDictionary,
                [kSecValueData: data] as CFDictionary
            )
            guard status == errSecSuccess else {
                throw NonInteractiveKeychainError.updateFailed(status)
            }
        }
    }
}
