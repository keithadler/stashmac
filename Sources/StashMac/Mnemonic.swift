//  Stash for Mac — MIT licensed. See LICENSE.
//
//  The key as 24 words (BIP-39 encoding of 256 bits of entropy plus an 8-bit checksum). The words
//  ARE the key: no passphrase, nothing to guess, nothing to forget except the card. A wrong word
//  is caught by the checksum before any restore starts.

import Foundation
import CryptoKit

enum Mnemonic {
    enum Error: LocalizedError, Equatable {
        case wordCount(Int), unknownWord(String), checksum
        var errorDescription: String? {
            switch self {
            case .wordCount(let n): return String(format: String(localized: "A recovery key has 24 words; this has %lld."), n)
            case .unknownWord(let w): return String(format: String(localized: "\"%@\" is not a recovery-key word. Check the spelling."), w)
            case .checksum: return String(localized: "The words don't add up. One of them is probably wrong.")
            }
        }
    }

    /// 32 bytes of entropy → 24 words.
    static func words(from entropy: Data) -> [String] {
        precondition(entropy.count == 32, "24-word keys encode exactly 256 bits")
        let hash = SHA256.hash(data: entropy)
        var bits: [Bool] = []
        for byte in entropy { for i in (0..<8).reversed() { bits.append((byte >> i) & 1 == 1) } }
        let checkByte = Array(hash)[0]
        for i in (0..<8).reversed() { bits.append((checkByte >> i) & 1 == 1) }   // 256/32 = 8 checksum bits
        return stride(from: 0, to: bits.count, by: 11).map { start in
            let idx = bits[start..<start + 11].reduce(0) { ($0 << 1) | ($1 ? 1 : 0) }
            return Wordlist.english[idx]
        }
    }

    /// 24 words → 32 bytes of entropy, verifying the checksum. Case and extra spaces are forgiven.
    static func entropy(from text: String) throws -> Data {
        let words = text.lowercased().split { !$0.isLetter }.map(String.init)
        guard words.count == 24 else { throw Error.wordCount(words.count) }
        var bits: [Bool] = []
        for w in words {
            guard let idx = Wordlist.index[w] else { throw Error.unknownWord(w) }
            for i in (0..<11).reversed() { bits.append((idx >> i) & 1 == 1) }
        }
        var entropy = Data(count: 32)
        for i in 0..<256 where bits[i] { entropy[i / 8] |= UInt8(1 << (7 - i % 8)) }
        let expected = Array(SHA256.hash(data: entropy))[0]
        let got = bits[256..<264].reduce(UInt8(0)) { ($0 << 1) | ($1 ? 1 : 0) }
        guard expected == got else { throw Error.checksum }
        return entropy
    }

    /// Words numbered in four columns, for the recovery card and the terminal.
    static func card(_ words: [String]) -> String {
        stride(from: 0, to: words.count, by: 4).map { row in
            (row..<min(row + 4, words.count)).map { String(format: "%2d. %-10@", $0 + 1, words[$0] as NSString) }.joined(separator: "  ")
        }.joined(separator: "\n")
    }
}
