import Foundation
import Security

enum KeychainError: Error {
    case unexpectedStatus(OSStatus)
    case invalidData
}

struct KeychainSessionStore: Sendable {
    /// App Groups are also valid keychain access groups. Using the group name keeps
    /// the main app and Share Extension on one protected session without copying
    /// credentials through UserDefaults.
    private static let accessGroup = "group.com.tryniecki.KajutaBot"
    private static let service = "com.tryniecki.KajutaBot.session"
    private static let legacyService = "com.tryniecki.KajutaBot.KajutaBot"
    private static let account = "user-session"

    func save(_ session: UserSession) throws {
        let data = try JSONEncoder().encode(session)
        try save(data, service: Self.service, accessGroup: Self.accessGroup)
    }

    func load() throws -> UserSession? {
        if let data = try loadData(service: Self.service, accessGroup: Self.accessGroup) {
            return try JSONDecoder().decode(UserSession.self, from: data)
        }

        // One-time migration from builds that stored the session in the app-only
        // keychain item whose service was Bundle.main.bundleIdentifier.
        if let legacyData = try loadData(service: Self.legacyService, accessGroup: nil) {
            let session = try JSONDecoder().decode(UserSession.self, from: legacyData)
            try save(session)
            delete(service: Self.legacyService, accessGroup: nil)
            return session
        }

        return nil
    }

    func clear() throws {
        try deleteThrowing(service: Self.service, accessGroup: Self.accessGroup)
        delete(service: Self.legacyService, accessGroup: nil)
    }

    private func save(_ data: Data, service: String, accessGroup: String?) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account,
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            attributes.forEach { insert[$0.key] = $0.value }
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func loadData(service: String, accessGroup: String?) throws -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        guard let data = item as? Data else { throw KeychainError.invalidData }
        return data
    }

    private func deleteThrowing(service: String, accessGroup: String?) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account,
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func delete(service: String, accessGroup: String?) {
        try? deleteThrowing(service: service, accessGroup: accessGroup)
    }
}
