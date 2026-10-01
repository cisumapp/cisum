//
//  DiscordTokenStore.swift
//  cisum
//
//  Created by Aarav Gupta on 01/10/26.
//


import Foundation
import Security

/// Minimal Keychain-backed store for the Discord token pair + expiry.
struct DiscordTokenStore {
    private let service = "aaravgupta.cisum.discord"
    private let accessKey = "access", refreshKey = "refresh", expiryKey = "expiry"

    var accessToken: String?  { read(accessKey) }
    var refreshToken: String? { read(refreshKey) }

    var isExpired: Bool {
        guard let raw = read(expiryKey), let epoch = TimeInterval(raw) else { return true }
        // 24h safety buffer, matching Discord's own refresh guidance.
        return Date().addingTimeInterval(24 * 3600) >= Date(timeIntervalSince1970: epoch)
    }

    func save(access: String, refresh: String, expiresIn: Int) {
        write(accessKey, access)
        write(refreshKey, refresh)
        write(expiryKey, String(Date().addingTimeInterval(TimeInterval(expiresIn)).timeIntervalSince1970))
    }

    func clear() { [accessKey, refreshKey, expiryKey].forEach(delete) }

    // MARK: - Keychain primitives
    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private func write(_ account: String, _ value: String) {
        delete(account)
        var q = query(account)
        q[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(q as CFDictionary, nil)
    }

    private func read(_ account: String) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func delete(_ account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }
}