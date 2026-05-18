import Foundation
import Security

struct KeychainService {
    let serviceName: String

    func save(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
        ]
        let addQuery: [String: Any] = baseQuery.merging([
            kSecValueData as String: data,
        ]) { _, new in new }

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecSuccess { return }

        if addStatus == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(
                baseQuery as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
            guard updateStatus == errSecSuccess else { throw KeychainError.unhandled(updateStatus) }
            return
        }

        throw KeychainError.unhandled(addStatus)
    }

    func read(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
    }

    enum KeychainError: LocalizedError, Equatable {
        case unhandled(OSStatus)

        var errorDescription: String? {
            switch self {
            case .unhandled(let status):
                let message = SecCopyErrorMessageString(status, nil) as String?
                    ?? "Unknown Keychain error"
                let suggestion = recoverySuggestion(for: status)
                return "Keychain 操作失败 / Keychain operation failed: \(message) (OSStatus \(status)).\(suggestion)"
            }
        }

        private func recoverySuggestion(for status: OSStatus) -> String {
            if status == errSecAuthFailed ||
                status == errSecInteractionNotAllowed ||
                status == errSecMissingEntitlement {
                return " 如果测试机曾用旧测试包保存过同名条目，请先删除 Keychain 中的 CJLocalProxy 条目后重试。"
            }
            return ""
        }
    }
}
