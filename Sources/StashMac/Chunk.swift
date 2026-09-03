//  Stash for Mac — MIT licensed. See LICENSE.
//
//  Chunks are what the provider stores: same-shaped encrypted blobs named by an HMAC of their
//  plaintext, so identical content dedupes within one stash but nobody without the key can tell
//  what a blob is or whether two people stored the same file. Every blob is authenticated;
//  tampering is detected on restore, never written to disk.

import Foundation
import CryptoKit

enum Chunk {
    static let magic = Data("STSH1".utf8)

    /// Provider-visible name for a chunk: HMAC-SHA256 of the plaintext under the naming key, hex.
    static func name(for plaintext: Data, key: MasterKey) -> String {
        HMAC<SHA256>.authenticationCode(for: plaintext, using: key.nameKey).map { String(format: "%02x", $0) }.joined()
    }

    /// magic || 12-byte nonce || ciphertext || 16-byte tag. Random nonce per seal.
    static func seal(_ plaintext: Data, key: MasterKey) throws -> Data {
        let box = try ChaChaPoly.seal(plaintext, using: key.chunkKey)
        return magic + box.combined
    }

    static func open(_ blob: Data, key: MasterKey) throws -> Data {
        guard blob.count > magic.count + 28, blob.prefix(magic.count) == magic else { throw ChunkError.notAChunk }
        do {
            return try ChaChaPoly.open(try ChaChaPoly.SealedBox(combined: blob.dropFirst(magic.count)), using: key.chunkKey)
        } catch { throw ChunkError.corruptOrWrongKey }
    }

    /// Content-defined boundaries would be better for edited documents; fixed 4 MB is the honest
    /// version 1 and still dedupes identical files exactly.
    static let size = 4 * 1024 * 1024

    static func split(_ data: Data) -> [Data] {
        stride(from: 0, to: max(data.count, 1), by: size).map { data.subdata(in: $0..<min($0 + size, data.count)) }
    }
}

enum ChunkError: LocalizedError {
    case notAChunk, corruptOrWrongKey
    var errorDescription: String? {
        switch self {
        case .notAChunk: return String(localized: "This file is not a Stash for Mac chunk.")
        case .corruptOrWrongKey: return String(localized: "The chunk is damaged or was made with a different key. Nothing was written.")
        }
    }
}
