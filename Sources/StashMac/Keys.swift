//  Stash for Mac — MIT licensed. See LICENSE.
//
//  One random 256-bit master key per stash. Everything else is derived from it with HKDF, so the
//  24 words recover all of it: the chunk-encryption key, the chunk-naming key, and the manifest key.
//  The master key lives in the login Keychain for daily use; the words and QR live on the card.

import Foundation
import CryptoKit
import Security

struct MasterKey: Equatable {
    let entropy: Data   // 32 bytes

    static func random() -> MasterKey {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, 32, &bytes)
        return MasterKey(entropy: Data(bytes))
    }

    init(entropy: Data) { precondition(entropy.count == 32); self.entropy = entropy }
    init(words: String) throws { self.entropy = try Mnemonic.entropy(from: words) }

    var words: [String] { Mnemonic.words(from: entropy) }

    private func derive(_ purpose: String) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: entropy), salt: Data("stashmac-v1".utf8), info: Data(purpose.utf8), outputByteCount: 32)
    }
    var chunkKey: SymmetricKey { derive("chunk-encryption") }
    var nameKey: SymmetricKey { derive("chunk-naming") }
    var manifestKey: SymmetricKey { derive("manifest-encryption") }

    /// Short, safe-to-show identifier of the key (first 8 hex of a hash), so two cards can be told apart.
    var fingerprint: String {
        SHA256.hash(data: Data("fingerprint".utf8) + entropy).prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    /// What the QR code carries: a versioned URI so a phone camera shows something meaningful.
    var qrPayload: String { "stashmac:key/v1/" + entropy.base64EncodedString() }

    static func fromQRPayload(_ s: String) -> MasterKey? {
        guard s.hasPrefix("stashmac:key/v1/"), let d = Data(base64Encoded: String(s.dropFirst("stashmac:key/v1/".count))), d.count == 32 else { return nil }
        return MasterKey(entropy: d)
    }
}

/// Keychain storage of the master key for this Mac.
enum KeyStore {
    private static let service = "com.keithadler.stashmac"
    nonisolated(unsafe) static var memoryOnly = false
    nonisolated(unsafe) private static var memory: [String: Data] = [:]

    static func load(stash: String = "default") -> MasterKey? {
        if memoryOnly { return memory[stash].map { MasterKey(entropy: $0) } }
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: stash,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data, d.count == 32 else { return nil }
        return MasterKey(entropy: d)
    }

    static func save(_ key: MasterKey, stash: String = "default") {
        if memoryOnly { memory[stash] = key.entropy; return }
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: stash]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = key.entropy
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        add[kSecAttrLabel as String] = "Stash for Mac key (\(key.fingerprint))"
        SecItemAdd(add as CFDictionary, nil)
    }

    static func delete(stash: String = "default") {
        if memoryOnly { memory[stash] = nil; return }
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: stash] as CFDictionary)
    }
}
