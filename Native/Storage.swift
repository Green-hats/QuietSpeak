import Foundation
import Security

struct ServerBookmark: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var address: String
    var nickname: String
}

// Private TS3 keys and passwords stay in the user's login Keychain.
enum SecureStore {
    private static let service = "app.quietspeak.personal"
    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }
    @discardableResult static func save(_ value: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account,
        ]
        if value.isEmpty {
            let result = SecItemDelete(query as CFDictionary)
            return result == errSecSuccess || result == errSecItemNotFound
        }
        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8)]
        let update = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if update == errSecSuccess { return true }
        guard update == errSecItemNotFound else { return false }
        var add = query
        add.merge(attributes) { _, new in new }
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}

struct Channel: Identifiable, Decodable {
    let id: UInt64
    let parent: UInt64
    let order: UInt64
    let name: String
    let topic: String?
    let locked: Bool
    let codec: String
}
struct Member: Identifiable, Decodable {
    let id: UInt16
    let channel: UInt64
    let name: String
    let muted: Bool
    let deafened: Bool
}
struct ChatMessage: Identifiable {
    let id = UUID()
    let time = Date()
    let sender: String
    let text: String
    let channel: UInt64
    let scope: String
    let outgoing: Bool
}
struct Snapshot: Decodable {
    let server: String
    let welcome: String
    let own: UInt16
    let currentChannel: UInt64
    let channels: [Channel]
    let clients: [Member]
}

// TeamSpeak channel order stores a predecessor, rather than a numeric rank.
func orderedChannels(_ channels: [Channel], parent: UInt64) -> [Channel] {
    var pending = channels.filter { $0.parent == parent }.sorted { $0.id < $1.id }
    var result: [Channel] = []
    var previous: UInt64 = 0
    while !pending.isEmpty {
        let index = pending.firstIndex { $0.order == previous } ?? 0
        let channel = pending.remove(at: index)
        result.append(channel)
        previous = channel.id
    }
    return result
}

struct ConnectionAddress {
    static func normalize(_ raw: String) throws -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw InputError("请输入服务器地址") }
        guard !text.contains(where: { $0.isWhitespace }) else { throw InputError("服务器地址不能包含空格") }
        if text.lowercased().hasPrefix("ts3server://") {
            guard let url = URLComponents(string: text), let host = url.host else {
                throw InputError("无效的 TS3 连接地址")
            }
            let port = url.port ?? 9987
            guard (1...65535).contains(port) else { throw InputError("端口需要在 1–65535 之间") }
            if let explicitPort = url.port {
                return host.contains(":") ? "[\(host)]:\(explicitPort)" : "\(host):\(explicitPort)"
            }
            return host.contains(":") ? "[\(host)]:9987" : host
        }
        guard !text.contains("/"), !text.contains("?"), !text.contains("#") else {
            throw InputError("请输入域名或 IP，可附带 :端口")
        }
        if text.hasPrefix("[") {
            guard let close = text.firstIndex(of: "]"), close > text.startIndex else {
                throw InputError("IPv6 地址格式不正确")
            }
            let suffix = String(text[text.index(after: close)...])
            if suffix.isEmpty { return text + ":9987" }
            guard suffix.hasPrefix(":"), let port = Int(suffix.dropFirst()),
                (1...65535).contains(port)
            else { throw InputError("端口需要在 1–65535 之间") }
            return text
        }
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count == 2 {
            guard !parts[0].isEmpty, let port = Int(parts[1]), (1...65535).contains(port) else {
                throw InputError("端口需要在 1–65535 之间")
            }
            return text
        }
        if parts.count > 2 { return "[\(text)]:9987" }
        return text
    }
}
struct InputError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
