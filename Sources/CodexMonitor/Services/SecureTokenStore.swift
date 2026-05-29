import Foundation
import CryptoKit

/// Secure token storage using AES-GCM encryption in the app's Application Support directory.
/// Replaces Keychain to avoid macOS system password prompts on every app launch/update.
enum SecureTokenStore {
    private static let fileName = "tokens.json"
    private static let keyFileName = "encryption.key"
    private static let directoryName = "CodexMonitor"

    // MARK: - Directory & File Paths

    private static var appSupportDir: URL {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/\(directoryName)")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private static var tokensFileURL: URL {
        appSupportDir.appendingPathComponent(fileName)
    }

    private static var keyFileURL: URL {
        appSupportDir.appendingPathComponent(keyFileName)
    }

    // MARK: - Encryption Key Management

    private static func getOrCreateKey() -> SymmetricKey? {
        let keyURL = keyFileURL

        // Try to load existing key
        if let keyData = try? Data(contentsOf: keyURL), keyData.count == 32 {
            return SymmetricKey(data: keyData)
        }

        // Generate new 256-bit key
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }

        do {
            try keyData.write(to: keyURL, options: .atomic)
            // Set file permissions to be readable only by the owner
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: keyURL.path
            )
            return key
        } catch {
            print("[SecureTokenStore] Failed to save encryption key: \(error)")
            return nil
        }
    }

    // MARK: - Token Storage

    /// Save a token for the given account ID
    static func save(accountID: String, token: String) {
        guard let key = getOrCreateKey() else { return }

        // Load existing tokens
        var tokens = loadAllTokens(key: key)

        // Encrypt and store the new token
        tokens[accountID] = token

        // Save all tokens
        saveAllTokens(tokens, key: key)
    }

    /// Load a token for the given account ID
    static func load(accountID: String) -> String? {
        guard let key = getOrCreateKey() else { return nil }
        return loadAllTokens(key: key)[accountID]
    }

    /// Delete a token for the given account ID
    static func delete(accountID: String) {
        guard let key = getOrCreateKey() else { return }

        var tokens = loadAllTokens(key: key)
        tokens.removeValue(forKey: accountID)
        saveAllTokens(tokens, key: key)
    }

    // MARK: - Internal: Encrypted File I/O

    private static func loadAllTokens(key: SymmetricKey) -> [String: String] {
        guard let fileData = try? Data(contentsOf: tokensFileURL) else {
            return [:]
        }

        // The file format: 12-byte nonce + ciphertext + 16-byte tag
        guard fileData.count > 28 else { return [:] }

        let nonce = fileData.prefix(12)
        let sealedBox = fileData.dropFirst(12)

        do {
            let sealed = try AES.GCM.SealedBox(combined: Data(nonce) + sealedBox)
            let decrypted = try AES.GCM.open(sealed, using: key)
            let tokens = try JSONDecoder().decode([String: String].self, from: decrypted)
            return tokens
        } catch {
            print("[SecureTokenStore] Failed to decrypt tokens: \(error)")
            return [:]
        }
    }

    private static func saveAllTokens(_ tokens: [String: String], key: SymmetricKey) {
        do {
            let plaintext = try JSONEncoder().encode(tokens)
            let nonce = AES.GCM.Nonce()
            let sealedBox = try AES.GCM.seal(plaintext, using: key, nonce: nonce)

            guard let combined = sealedBox.combined else {
                print("[SecureTokenStore] Failed to create sealed box")
                return
            }

            try combined.write(to: tokensFileURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: tokensFileURL.path
            )
        } catch {
            print("[SecureTokenStore] Failed to save tokens: \(error)")
        }
    }

    // MARK: - Migration from Keychain

    /// Migrate all tokens from Keychain to encrypted storage.
    /// Returns the number of tokens migrated.
    @discardableResult
    static func migrateFromKeychain(accountIDs: [String]) -> Int {
        var migrated = 0

        for id in accountIDs {
            let keychainKey = "token_\(id)"
            guard let token = KeychainHelper.load(key: keychainKey) else { continue }

            save(accountID: id, token: token)
            KeychainHelper.delete(key: keychainKey)
            migrated += 1
        }

        if migrated > 0 {
            print("[SecureTokenStore] Migrated \(migrated) token(s) from Keychain")
        }

        return migrated
    }
}
