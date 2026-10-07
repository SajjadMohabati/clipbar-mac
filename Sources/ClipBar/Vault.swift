import Foundation
import LocalAuthentication
import Security

/// Values of locked saved items. They live in the macOS Keychain (not in saved.json),
/// and reading them requires Touch ID or the Mac's password.
@MainActor
enum Vault {
    private static let service = "ClipBar Saved Items"
    /// Unlocking once covers the next few actions, e.g. edit and then paste.
    private static let grace: TimeInterval = 30
    private static var unlockedUntil = Date.distantPast

    static func authenticate(reason: String) async -> Bool {
        if Date.now < unlockedUntil { return true }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        let granted = await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }
        if granted { unlockedUntil = .now.addingTimeInterval(grace) }
        return granted
    }

    static func read(_ id: UUID) -> String? {
        var query = baseQuery(id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func write(_ text: String, for id: UUID) -> Bool {
        SecItemDelete(baseQuery(id) as CFDictionary)
        var item = baseQuery(id)
        item[kSecValueData as String] = Data(text.utf8)
        item[kSecAttrLabel as String] = "ClipBar saved item"
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func delete(_ id: UUID) {
        SecItemDelete(baseQuery(id) as CFDictionary)
    }

    private static func baseQuery(_ id: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
        ]
    }
}
