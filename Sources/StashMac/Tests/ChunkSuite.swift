//  Stash for Mac — MIT licensed. See LICENSE.

import Foundation

enum ChunkSuite {
    static let suite = TestSuite(name: "Chunk", cases: [
        TestCase(name: "seal and open round-trip") { t in
            let k = MasterKey.random()
            let plain = Data((0..<10_000).map { UInt8($0 % 251) })
            let blob = try Chunk.seal(plain, key: k)
            t.check(blob.prefix(5) == Data("STSH1".utf8), "magic")
            t.equal(blob.count, plain.count + 5 + 12 + 16, "overhead is nonce plus tag")
            t.equal(try Chunk.open(blob, key: k), plain, "round trip")
            let second = try Chunk.seal(plain, key: k)
            t.check(second != blob, "fresh nonce every time")
        },
        TestCase(name: "wrong key, tampering and junk are refused") { t in
            let k = MasterKey.random(), other = MasterKey.random()
            let blob = try Chunk.seal(Data("secret".utf8), key: k)
            t.check((try? Chunk.open(blob, key: other)) == nil, "other key fails")
            var tampered = blob; tampered[tampered.count - 3] ^= 0x01
            t.check((try? Chunk.open(tampered, key: k)) == nil, "flipped bit fails")
            var body = blob; body[10] ^= 0x01
            t.check((try? Chunk.open(body, key: k)) == nil, "ciphertext change fails")
            t.check((try? Chunk.open(Data("hello".utf8), key: k)) == nil, "junk fails")
        },
        TestCase(name: "names dedupe within a key and reveal nothing across keys") { t in
            let k = MasterKey.random(), other = MasterKey.random()
            let a = Data("the same content".utf8)
            t.equal(Chunk.name(for: a, key: k), Chunk.name(for: a, key: k), "same content, same name")
            t.check(Chunk.name(for: a, key: k) != Chunk.name(for: a, key: other), "different key, different name")
            t.check(Chunk.name(for: a, key: k) != Chunk.name(for: Data("the same content!".utf8), key: k), "different content, different name")
            t.equal(Chunk.name(for: a, key: k).count, 64, "64 hex chars")
        },
        TestCase(name: "splitting and rejoining") { t in
            let big = Data(repeating: 7, count: Chunk.size * 2 + 123)
            let parts = Chunk.split(big)
            t.equal(parts.count, 3, "two full chunks and a tail")
            t.equal(parts.last?.count, 123, "tail size")
            t.equal(Data(parts.joined()), big, "rejoin")
            t.equal(Chunk.split(Data()).count, 1, "empty file is one empty chunk")
        },
    ])
}
