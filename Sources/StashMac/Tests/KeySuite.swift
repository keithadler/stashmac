//  Stash for Mac — MIT licensed. See LICENSE.

import Foundation

enum KeySuite {
    static let suite = TestSuite(name: "Key", cases: [
        TestCase(name: "BIP-39 test vectors") { t in
            // From the reference vectors: all-zero and all-0x7f 256-bit entropy.
            let zero = Data(repeating: 0, count: 32)
            t.equal(Mnemonic.words(from: zero).joined(separator: " "),
                    "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art", "all zeros")
            let sevens = Data(repeating: 0x7f, count: 32)
            t.equal(Mnemonic.words(from: sevens).joined(separator: " "),
                    "legal winner thank year wave sausage worth useful legal winner thank year wave sausage worth useful legal winner thank year wave sausage worth title", "all 0x7f")
            let ff = Data(repeating: 0xff, count: 32)
            t.equal(Mnemonic.words(from: ff).joined(separator: " "),
                    "zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo vote", "all 0xff")
        },
        TestCase(name: "words round-trip and forgive formatting") { t in
            for _ in 0..<50 {
                let k = MasterKey.random()
                let back = try MasterKey(words: k.words.joined(separator: " "))
                if back != k { t.fail("round trip failed for \(k.fingerprint)"); break }
            }
            t.check(true, "50 random keys round-trip")
            let k = MasterKey.random()
            let messy = k.words.enumerated().map { $0.offset % 2 == 0 ? $0.element.uppercased() : $0.element }.joined(separator: ",  \n")
            t.equal(try MasterKey(words: messy), k, "case and separators forgiven")
        },
        TestCase(name: "wrong words are caught before anything happens") { t in
            let k = MasterKey.random()
            var words = k.words
            words[5] = words[5] == "zoo" ? "abandon" : "zoo"
            do { _ = try MasterKey(words: words.joined(separator: " ")); t.fail("checksum should fail") }
            catch let e as Mnemonic.Error { t.equal(e, .checksum, "checksum error") } catch { t.fail("wrong error \(error)") }
            do { _ = try MasterKey(words: (words.dropLast()).joined(separator: " ")); t.fail("count should fail") }
            catch let e as Mnemonic.Error { t.equal(e, .wordCount(23), "count error") } catch { t.fail("wrong error \(error)") }
            do { _ = try MasterKey(words: k.words.joined(separator: " ").replacingOccurrences(of: k.words[0], with: "clipboard")); t.fail("unknown word should fail") }
            catch let e as Mnemonic.Error { t.equal(e, .unknownWord("clipboard"), "unknown word error") } catch { t.fail("wrong error \(error)") }
        },
        TestCase(name: "derived keys differ by purpose and are stable") { t in
            let k = MasterKey.random()
            t.check(k.chunkKey != k.nameKey && k.nameKey != k.manifestKey, "purposes separate")
            let again = MasterKey(entropy: k.entropy)
            t.check(k.chunkKey == again.chunkKey && k.fingerprint == again.fingerprint, "deterministic")
            t.equal(k.fingerprint.count, 8, "fingerprint is 8 hex")
            t.check(MasterKey.random().fingerprint != k.fingerprint, "fingerprints differ")
        },
        TestCase(name: "QR payload survives rendering and scanning") { t in
            let k = MasterKey.random()
            t.equal(MasterKey.fromQRPayload(k.qrPayload), k, "payload parses")
            t.check(MasterKey.fromQRPayload("stashmac:key/v1/nope") == nil && MasterKey.fromQRPayload("https://x") == nil, "junk rejected")
            guard let png = QR.png(k.qrPayload, size: 512) else { t.fail("no qr image"); return }
            t.check(png.count > 500, "png rendered")
            guard let scanned = QR.read(png) else { t.fail("vision found no qr"); return }
            t.equal(MasterKey.fromQRPayload(scanned), k, "scanned key matches")
        },
        TestCase(name: "recovery card renders a PDF with the words") { t in
            let k = MasterKey.random()
            guard let pdf = QR.recoveryCard(k, stashName: "default") else { t.fail("no pdf"); return }
            t.check(pdf.count > 5_000 && pdf.prefix(5) == Data("%PDF-".utf8), "is a pdf")
            let card = Mnemonic.card(k.words)
            t.check(card.contains(" 1. ") && card.contains("24. ") && card.split(separator: "\n").count == 6, "card lists 24 numbered words in 6 rows")
        },
        TestCase(name: "keychain stand-in stores and forgets") { t in
            t.check(KeyStore.load() == nil, "empty at start")
            let k = MasterKey.random()
            KeyStore.save(k)
            t.equal(KeyStore.load(), k, "saved and loaded")
            KeyStore.delete()
            t.check(KeyStore.load() == nil, "forgotten")
        },
    ])
}
