//  Stash for Mac — MIT licensed. See LICENSE.

import Foundation

/// A chunk store in a dictionary: proves the engine only needs the protocol, and stands in for a
/// cloud store in tests.
final class MemoryStore: ChunkStore {
    var chunks: [String: Data] = [:]
    var manifests: [String: Data] = [:]
    var puts = 0
    var name: String { "memory" }
    func prepare() throws {}
    func hasChunk(_ name: String) -> Bool { chunks[name] != nil }
    func putChunk(_ name: String, _ data: Data) throws { chunks[name] = data; puts += 1 }
    func getChunk(_ name: String) throws -> Data { guard let d = chunks[name] else { throw ChunkError.notAChunk }; return d }
    func deleteChunk(_ name: String) throws { chunks[name] = nil }
    func chunkNames() -> [String] { Array(chunks.keys) }
    func chunkSize(_ name: String) -> Int64 { Int64(chunks[name]?.count ?? 0) }
    func manifestNames() -> [String] { manifests.keys.sorted(by: >) }
    func putManifest(_ name: String, _ data: Data) throws { manifests[name] = data }
    func getManifest(_ name: String) throws -> Data { guard let d = manifests[name] else { throw ChunkError.notAChunk }; return d }
    func deleteManifest(_ name: String) throws { manifests[name] = nil }
    func totalSize() -> Int64 { Int64(chunks.values.reduce(0) { $0 + $1.count } + manifests.values.reduce(0) { $0 + $1.count }) }
}

enum StoreSuite {
    static let suite = TestSuite(name: "Store", cases: [
        TestCase(name: "the whole engine runs against a non-folder store") { t in
            let src = try BackupSuite.tempDir("src"), out = try BackupSuite.tempDir("out")
            defer { [src, out].forEach { try? FileManager.default.removeItem(at: $0) } }
            try BackupSuite.write(src, "a.txt", Data("alpha".utf8)); try BackupSuite.write(src, "sub/b.txt", Data("beta".utf8))
            let key = MasterKey.random(), store = MemoryStore()
            let r = try Backup.run(sources: [src], store: store, key: key)
            t.equal(r.newChunks, 2, "two chunks put")
            t.equal(store.manifests.count, 1, "one manifest")
            t.check(store.chunks.values.allSatisfy { $0.prefix(5) == Data("STSH1".utf8) }, "sealed in the store")
            let again = try Backup.run(sources: [src], store: store, key: key)
            t.equal(again.newChunks, 0, "dedupe through the protocol")
            let snaps = Restore.snapshots(store: store, key: key)
            t.equal(snaps.count, 2, "two snapshots listed")
            let rr = try Restore.run(snapshot: snaps[0].fileName, store: store, key: key, to: out)
            t.equal(rr.restored, 2, "restored through the protocol")
            t.equal(try String(contentsOf: out.appendingPathComponent(src.lastPathComponent).appendingPathComponent("sub/b.txt"), encoding: .utf8), "beta", "content")
            let v = try Restore.verify(store: store, key: key)
            t.check(v.chunksBad.isEmpty && v.sampleOK == true, "verify through the protocol")
            let p = try Prune.run(store: store, key: key, keep: 1, policy: .last)
            t.equal(p.snapshotsRemoved, 1, "prune through the protocol")
            t.equal(Prune.uniqueSizes(store: store, key: key).count, 1, "unique sizes through the protocol")
        },
        TestCase(name: "exclusions by pattern and size") { t in
            let src = try BackupSuite.tempDir("src")
            defer { try? FileManager.default.removeItem(at: src) }
            try BackupSuite.write(src, "keep.txt", Data("k".utf8))
            try BackupSuite.write(src, "scratch.tmp", Data("t".utf8))
            try BackupSuite.write(src, "Caches/x.db", Data("c".utf8))
            try BackupSuite.write(src, "Photos.photoslibrary/inner.db", Data("p".utf8))
            try BackupSuite.write(src, "huge.bin", Data(repeating: 0, count: 3_000_000))
            let (files, _, skipped) = Backup.walk(src, exclude: Config.defaultExcludes, maxBytes: 2_000_000)
            t.equal(files.map(\.rel), ["keep.txt"], "only the plain file survives")
            t.equal(skipped, 4, "four skipped by rule")
            let (all, _, none) = Backup.walk(src, exclude: [], maxBytes: 0)
            t.equal(all.count, 5, "no rules, everything")
            t.equal(none, 0, "nothing skipped")
            t.check(Backup.matches("Report.TMP", "*.tmp") && Backup.matches("Caches", "Cache*") && !Backup.matches("cachet", "Cache"), "patterns are shell-style and case-insensitive")
        },
        TestCase(name: "restore selection prefixes") { t in
            t.check(Restore.selected("a/b/c.txt", by: []), "empty means everything")
            t.check(Restore.selected("a/b/c.txt", by: ["a/b"]), "folder prefix")
            t.check(Restore.selected("a/b/c.txt", by: ["a/b/c.txt"]), "exact file")
            t.check(!Restore.selected("a/bc/d.txt", by: ["a/b"]), "sibling folder with the same prefix is not selected")
            t.check(Restore.selected("x.txt", by: ["nope", "x.txt"]), "any of several")
        },
    ])
}
