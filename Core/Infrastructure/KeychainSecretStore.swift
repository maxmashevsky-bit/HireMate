import Foundation
import Security

@MainActor
public protocol SecureSecretStore: Sendable {
    func save(_ secret: String) throws
    func read() throws -> String?
    func delete() throws
}

@MainActor
public final class KeychainSecretStore: SecureSecretStore {
    private let service: String
    private let account: String
    public init(service: String = "dev.maxmashevsky.MaxInterviewCopilot", account: String = "ai.primary") {
        self.service = service
        self.account = account
    }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false]
    }
    public func save(_ secret: String) throws {
        guard !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SecretStoreError.empty }
        let attributes: [String: Any] = [kSecValueData as String: Data(secret.utf8)]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = Data(secret.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw SecretStoreError.system(status) }
    }
    public func read() throws -> String? {
        var item = query
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(item as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw SecretStoreError.system(status) }
        guard let data = result as? Data, let secret = String(data: data, encoding: .utf8) else {
            throw SecretStoreError.invalidData
        }
        return secret
    }
    public func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SecretStoreError.system(status) }
    }
}

public enum SecretStoreError: Error, LocalizedError {
    case empty, invalidData, system(OSStatus)
    public var errorDescription: String? {
        switch self {
        case .empty: "Ключ не может быть пустым."
        case .invalidData: "Формат записи Keychain не поддерживается."
        case .system(let status): "Keychain вернул ошибку \(status). Значение ключа не записано в журнал."
        }
    }
}
