//  Stash for Mac — MIT licensed. See LICENSE.

import Foundation

enum PruneSuite {
    static let suite = TestSuite(name: "Prune", cases: [
        TestCase(name: "keeps the newest snapshots and drops orphaned chunks") { t in
            let src = try BackupSuite.tempDir("src"), dest = try BackupSuite.tempDir("dest")
            defer { [src, dest].forEach { try? FileManager.default.removeItem(at: $0) } }
            let key = MasterKey.random()
            try BackupSuite.write(src, "a.txt", Data("version one".utf8))
            _ = try Backup.run(sources: [src], destination: dest, key: key)
            try BackupSuite.write(src, "a.txt", Data("version two".utf8))
            _ = try Backup.run(sources: [src], destination: dest, key: key)
            try BackupSuite.write(src, "a.txt", Data("version three".utf8))
            _ = try Backup.run(sources: [src], destination: dest, key: key)
            t.equal(Restore.snapshots(destination: dest, key: key).count, 3, "three snapshots")
            let before = Prune.size(destination: dest, key: key)
            let r = try Prune.run(destination: dest, key: key, keep: 2)
            t.equal(r.snapshotsRemoved, 1, "oldest snapshot removed")
            t.equal(r.chunksRemoved, 1, "its chunk removed")
            t.equal(r.chunksKept, 2, "two chunks stay")
            t.check(r.bytesFreed > 0 && Prune.size(destination: dest, key: key) < before, "space reclaimed")
            let snaps = Restore.snapshots(destination: dest, key: key)
            t.equal(snaps.count, 2, "two remain")
            let out = try BackupSuite.tempDir("out"); defer { try? FileManager.default.removeItem(at: out) }
            let rr = try Restore.run(snapshot: snaps[0].fileName, destination: dest, key: key, to: out)
            t.check(rr.failed.isEmpty, "newest still restores")
            t.equal(try String(contentsOf: out.appendingPathComponent(src.lastPathComponent).appendingPathComponent("a.txt"), encoding: .utf8), "version three", "newest content")
            let rr2 = try Restore.run(snapshot: snaps[1].fileName, destination: dest, key: key, to: out)
            t.check(rr2.failed.isEmpty, "second newest still restores")
        },
        TestCase(name: "shared chunks survive, nothing is deleted under a wrong key") { t in
            let src = try BackupSuite.tempDir("src"), dest = try BackupSuite.tempDir("dest")
            defer { [src, dest].forEach { try? FileManager.default.removeItem(at: $0) } }
            let key = MasterKey.random()
            try BackupSuite.write(src, "same.txt", Data("unchanged".utf8)); try BackupSuite.write(src, "b.txt", Data("b1".utf8))
            _ = try Backup.run(sources: [src], destination: dest, key: key)
            try BackupSuite.write(src, "b.txt", Data("b2".utf8))
            _ = try Backup.run(sources: [src], destination: dest, key: key)
            let r = try Prune.run(destination: dest, key: key, keep: 1)
            t.equal(r.chunksRemoved, 1, "only the old b chunk goes")
            t.equal(r.chunksKept, 2, "shared chunk and new b stay")
            let sizeBefore = Prune.size(destination: dest, key: key)
            t.check((try? Prune.run(destination: dest, key: MasterKey.random(), keep: 1)) != nil, "a wrong key sees an empty layout and does nothing")
            t.equal(Prune.size(destination: dest, key: key), sizeBefore, "nothing of ours was touched")
            // A damaged remaining manifest must stop pruning before any deletion.
            let layout = Layout(destination: dest, key: key)
            let m = layout.manifestFiles()[0]
            var bytes = try Data(contentsOf: m); bytes[bytes.count - 1] ^= 1; try bytes.write(to: m)
            t.check((try? Prune.run(destination: dest, key: key, keep: 1)) == nil, "refuses with a damaged manifest")
            t.equal(Prune.size(destination: dest, key: key), sizeBefore, "still nothing deleted")
        },
        TestCase(name: "keep is never less than one") { t in
            let src = try BackupSuite.tempDir("src"), dest = try BackupSuite.tempDir("dest")
            defer { [src, dest].forEach { try? FileManager.default.removeItem(at: $0) } }
            let key = MasterKey.random()
            try BackupSuite.write(src, "a.txt", Data("x".utf8))
            _ = try Backup.run(sources: [src], destination: dest, key: key)
            let r = try Prune.run(destination: dest, key: key, keep: 0)
            t.equal(r.snapshotsRemoved, 0, "the only snapshot is kept")
            t.equal(Config.keepSnapshots, 30, "default keeps thirty")
        },
    ])
}
