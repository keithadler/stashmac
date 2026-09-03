//  Stash for Mac — MIT licensed. See LICENSE.

import Foundation

enum GuardSuite {
    static let suite = TestSuite(name: "Guards", cases: [
        TestCase(name: "a backup must not contain itself") { t in
            let docs = URL(fileURLWithPath: "/Users/sam/Documents"), drive = URL(fileURLWithPath: "/Users/sam/Library/CloudStorage/GoogleDrive/My Drive")
            t.check(Config.objection(toSource: docs, sources: [], destinations: [drive]) == nil, "normal pair is fine")
            t.check(Config.objection(toDestination: drive, sources: [docs]) == nil, "normal pair is fine the other way")
            t.check(Config.objection(toDestination: docs.appendingPathComponent("Backups"), sources: [docs]) != nil, "destination inside a source")
            t.check(Config.objection(toSource: URL(fileURLWithPath: "/Users/sam"), sources: [], destinations: [drive]) != nil, "source that contains the destination")
            t.check(Config.objection(toSource: docs.appendingPathComponent("Taxes"), sources: [docs], destinations: []) != nil, "already inside a source")
            t.check(Config.objection(toSource: URL(fileURLWithPath: "/"), sources: [], destinations: []) != nil, "the whole disk is refused")
            t.check(Config.objection(toSource: URL(fileURLWithPath: "/Users/sam/Documents2"), sources: [docs], destinations: []) == nil, "sibling with a shared prefix is not inside")
        },
        TestCase(name: "home folder skips Library") { t in
            let home = try BackupSuite.tempDir("home")
            defer { try? FileManager.default.removeItem(at: home) }
            try BackupSuite.write(home, "Documents/a.txt", Data("a".utf8))
            try BackupSuite.write(home, "Library/Caches/x", Data("x".utf8))
            let saved = Config.isHome
            defer { Config.isHome = saved }
            Config.isHome = { $0.standardizedFileURL.path == home.standardizedFileURL.path }
            let (files, _, skipped) = Backup.walk(home, exclude: [], maxBytes: 0)
            t.equal(files.map(\.rel), ["Documents/a.txt"], "Library left out")
            t.equal(skipped, 1, "counted as skipped")
            Config.isHome = { _ in false }
            t.equal(Backup.walk(home, exclude: [], maxBytes: 0).files.count, 2, "any other folder keeps its Library")
        },
        TestCase(name: "prune leaves fresh unreferenced chunks alone") { t in
            let store = MemoryStore()
            let key = MasterKey.random()
            let src = try BackupSuite.tempDir("src"); defer { try? FileManager.default.removeItem(at: src) }
            try BackupSuite.write(src, "a.txt", Data("a".utf8))
            _ = try Backup.run(sources: [src], store: store, key: key)
            // Another Mac is mid-backup: a chunk no manifest references yet, written just now.
            let orphan = Chunk.name(for: Data("in flight".utf8), key: key)
            try store.putChunk(orphan, try Chunk.seal(Data("in flight".utf8), key: key))
            store.dates[orphan] = Date()
            let r = try Prune.run(store: store, key: key, keep: 5)
            t.equal(r.chunksRemoved, 0, "fresh orphan survives")
            store.dates[orphan] = Date().addingTimeInterval(-3 * 3600)
            let r2 = try Prune.run(store: store, key: key, keep: 5)
            t.equal(r2.chunksRemoved, 1, "old orphan goes")
        },
        TestCase(name: "verify never downloads evicted chunks") { t in
            let store = MemoryStore()
            let key = MasterKey.random()
            let src = try BackupSuite.tempDir("src"); defer { try? FileManager.default.removeItem(at: src) }
            try BackupSuite.write(src, "a.txt", Data("a".utf8)); try BackupSuite.write(src, "b.txt", Data("b".utf8))
            _ = try Backup.run(sources: [src], store: store, key: key)
            let evicted = Chunk.name(for: Data("b".utf8), key: key)
            store.evicted.insert(evicted)
            store.reads = 0
            let v = try Restore.verify(store: store, key: key)
            t.equal(v.chunksChecked, 1, "one checked")
            t.equal(v.chunksInCloudOnly, 1, "one reported as cloud-only")
            t.check(v.chunksMissing.isEmpty && v.chunksBad.isEmpty, "not counted as missing or bad")
            t.check(!store.readNames.contains(evicted), "the evicted chunk was never read")
            t.equal(v.sampleFile, "a.txt", "sample picked from files that are local")
        },
    ])
}
