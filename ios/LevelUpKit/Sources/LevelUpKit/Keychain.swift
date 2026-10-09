import Foundation
import Security

/// Одна запись в Keychain (generic password).
///
/// С `accessGroup` (идентификатор App Group) запись видна и приложению, и виджетам.
/// Если подпись не даёт доступа к общей группе, запись остаётся в личной группе
/// приложения — оно работает как раньше, просто виджеты не смогут ходить на сервер.
struct KeychainItem: Sendable {
    let service: String
    let account: String
    var accessGroup: String?

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func query(group: String?) -> [String: Any] {
        var query = query
        if let group {
            query[kSecAttrAccessGroup as String] = group
        }
        return query
    }

    func read() -> Data? {
        guard let accessGroup, !accessGroup.isEmpty else { return read(group: nil).data }
        let shared = read(group: accessGroup)
        if let data = shared.data {
            return data
        }
        guard let legacy = read(group: nil).data else { return nil }
        if shared.status == errSecItemNotFound {
            // Запись из версии без общей группы — переносим, чтобы её видели виджеты.
            SecItemDelete(query as CFDictionary)
            write(legacy)
        }
        return legacy
    }

    func write(_ data: Data) {
        let group = accessGroup.flatMap { $0.isEmpty ? nil : $0 }
        if upsert(data, group: group) == errSecMissingEntitlement, group != nil {
            _ = upsert(data, group: nil)
        }
    }

    func delete() {
        // Без группы удаляются копии во всех доступных группах.
        SecItemDelete(query as CFDictionary)
    }

    private func read(group: String?) -> (data: Data?, status: OSStatus) {
        var query = query(group: group)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status == errSecSuccess ? result as? Data : nil, status)
    }

    private func upsert(_ data: Data, group: String?) -> OSStatus {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            // Доступно после первой разблокировки — нужно для фоновых задач и виджетов.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let query = query(group: group)
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        guard status == errSecItemNotFound else { return status }
        return SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
    }
}
