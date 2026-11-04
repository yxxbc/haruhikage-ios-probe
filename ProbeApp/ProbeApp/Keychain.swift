import Foundation
import Security

// The session, kept where iOS keeps secrets: the keychain, which survives
// reinstalls only with an entitlement and does survive relaunches, as the
// app's own macOS build keeps it. The Go side cannot reach it, so the Swift
// side owns it: Go hands over a cookie string, and reads it back at launch.
enum Keychain {
    static let service = "dev.yxxbc.probe.session"
    static let account = "netease-session"
    /// The status of the last failed call, for the probe to report.
    static var lastStatus: OSStatus = errSecSuccess

    static func save(_ value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        // Replacing: delete then add, which is simpler than SecItemUpdate
        // and does not fail on the first save.
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        if status != errSecSuccess { lastStatus = status }
        return status == errSecSuccess
    }

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        let st = SecItemCopyMatching(query as CFDictionary, &out)
        guard st == errSecSuccess, let data = out as? Data else {
            if st != errSecItemNotFound { lastStatus = st }
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
