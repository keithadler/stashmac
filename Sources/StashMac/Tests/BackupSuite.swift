//  Stash for Mac — MIT licensed. See LICENSE.

import Foundation
import CryptoKit

enum BackupSuite {
    static func tempDir(_ tag: String) throws -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("stashmac-\(tag)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    static func write(_ dir: URL, _ rel: String, _ data: Data) throws {
        let u = dir.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: u)
    }
    static func sha(_ url: URL) -> String { (try? Data(contentsOf: url)).map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() } ?? "missing" }

    static let suite = TestSuite(name: "Backup", cases: [
        TestCase(name: "backup then restore reproduces every file") { t in
            let src = try tempDir("src"), dest = try tempDir("dest"), out = try tempDir("out")
            defer { [src, dest, out].forEach { try? FileManager.default.removeItem(at: $0) } }
            try write(src, "notes.txt", Data("hello stash".utf8))
            try write(src, "deep/photos/one.bin", Data((0..<300_000).map { UInt8($0 % 253) }))
            try write(src, "big.bin", Data(repeating: 0xAB, count: Chunk.size + 4321))
            try write(src, "empty.txt", Data())
            try write(src, ".DS_Store", Data([1, 2, 3]))
            let key = MasterKey.random()
            let r = try Backup.run(sources: [src], destination: dest, key: key)
            t.equal(r.files, 4, "four files (the .DS_Store is ignored)")
            t.equal(r.newChunks, 5, "1 + 1 + 2 + 1 chunks")
            t.check(r.unreadable.isEmpty && r.skippedPlaceholders == 0, "nothing skipped")
            let layout = Layout(destination: dest, key: key)
            t.check(FileManager.default.fileExists(atPath: layout.root.appendingPathComponent("README.txt").path), "readme for whoever finds the folder")
            let names = try FileManager.default.subpathsOfDirectory(atPath: layout.chunks.path).filter { !$0.contains("/") == false }
            t.check(names.allSatisfy { $0.range(of: "^[0-9a-f]{2}/[0-9a-f]{64}$", options: .regularExpression) != nil }, "chunk paths reveal nothing")
            for n in names { t.check((try? Data(contentsOf: layout.chunks.appendingPathComponent(n)))?.prefix(5) == Data("STSH1".utf8), "sealed") }

            let snaps = Restore.snapshots(destination: dest, key: key)
            t.equal(snaps.count, 1, "one snapshot")
            t.equal(snaps.first?.files, 4, "listed files")
            let rr = try Restore.run(snapshot: snaps[0].fileName, destination: dest, key: key, to: out)
            t.equal(rr.restored, 4, "restored all")
            t.check(rr.failed.isEmpty, "no failures")
            let base = out.appendingPathComponent(src.lastPathComponent)
            for rel in ["notes.txt", "deep/photos/one.bin", "big.bin", "empty.txt"] {
                t.equal(sha(base.appendingPathComponent(rel)), sha(src.appendingPathComponent(rel)), "identical: \(rel)")
            }
        },
        TestCase(name: "second backup reuses chunks; changed and new files upload") { t in
            let src = try tempDir("src"), dest = try tempDir("dest")
            defer { [src, dest].forEach { try? FileManager.default.removeItem(at: $0) } }
            try write(src, "a.txt", Data("alpha".utf8)); try write(src, "b.txt", Data("beta".utf8))
            let key = MasterKey.random()
            _ = try Backup.run(sources: [src], destination: dest, key: key)
            let again = try Backup.run(sources: [src], destination: dest, key: key)
            t.equal(again.newChunks, 0, "nothing new to upload")
            t.equal(again.reusedChunks, 2, "both reused")
            try write(src, "b.txt", Data("beta changed".utf8)); try write(src, "c.txt", Data("gamma".utf8))
            let third = try Backup.run(sources: [src], destination: dest, key: key)
            t.equal(third.newChunks, 2, "changed plus new")
            t.equal(third.reusedChunks, 1, "unchanged reused")
            t.equal(Restore.snapshots(destination: dest, key: key).count, 3, "three snapshots kept")
            try write(src, "copy of a.txt", Data("alpha".utf8))
            let fourth = try Backup.run(sources: [src], destination: dest, key: key)
            t.equal(fourth.newChunks, 0, "identical content dedupes")
        },
        TestCase(name: "tampered chunk fails that file only, writes nothing partial") { t in
            let src = try tempDir("src"), dest = try tempDir("dest"), out = try tempDir("out")
            defer { [src, dest, out].forEach { try? FileManager.default.removeItem(at: $0) } }
            try write(src, "good.txt", Data("fine".utf8)); try write(src, "bad.txt", Data("will be damaged".utf8))
            let key = MasterKey.random()
            _ = try Backup.run(sources: [src], destination: dest, key: key)
            let badName = Chunk.name(for: Data("will be damaged".utf8), key: key)
            let url = Layout(destination: dest, key: key).chunk(badName)
            var blob = try Data(contentsOf: url); blob[blob.count - 1] ^= 0xFF; try blob.write(to: url)
            let snap = Restore.snapshots(destination: dest, key: key)[0].fileName
            let r = try Restore.run(snapshot: snap, destination: dest, key: key, to: out)
            t.equal(r.restored, 1, "good file restored")
            t.equal(r.failed.count, 1, "bad file reported")
            t.check(r.failed[0].hasPrefix("bad.txt"), "named")
            let base = out.appendingPathComponent(src.lastPathComponent)
            t.check(!FileManager.default.fileExists(atPath: base.appendingPathComponent("bad.txt").path), "no partial file")
            t.check(!FileManager.default.fileExists(atPath: base.appendingPathComponent("bad.txt.stash-partial").path), "temp cleaned")
            let v = try Restore.verify(destination: dest, key: key)
            t.equal(v.chunksChecked, 2, "verify checked both")
            t.equal(v.chunksBad, [badName], "verify names the bad chunk")
        },
        TestCase(name: "verify restores a random file and a wrong key sees nothing") { t in
            let src = try tempDir("src"), dest = try tempDir("dest")
            defer { [src, dest].forEach { try? FileManager.default.removeItem(at: $0) } }
            for i in 0..<5 { try write(src, "f\(i).txt", Data(repeating: UInt8(i), count: 1000 + i)) }
            let key = MasterKey.random()
            _ = try Backup.run(sources: [src], destination: dest, key: key)
            let v = try Restore.verify(destination: dest, key: key)
            t.equal(v.chunksChecked, 5, "all chunks")
            t.check(v.chunksBad.isEmpty && v.chunksMissing.isEmpty, "all good")
            t.equal(v.sampleOK, true, "sample restore matches size")
            t.check(Restore.snapshots(destination: dest, key: MasterKey.random()).isEmpty, "another key sees no snapshots")
        },
        TestCase(name: "restore a subfolder only, and manifests hide names") { t in
            let src = try tempDir("src"), dest = try tempDir("dest"), out = try tempDir("out")
            defer { [src, dest, out].forEach { try? FileManager.default.removeItem(at: $0) } }
            try write(src, "keep/a.txt", Data("a".utf8)); try write(src, "keep/b.txt", Data("b".utf8)); try write(src, "other/c.txt", Data("c".utf8))
            let key = MasterKey.random()
            _ = try Backup.run(sources: [src], destination: dest, key: key)
            let snap = Restore.snapshots(destination: dest, key: key)[0].fileName
            let r = try Restore.run(snapshot: snap, destination: dest, key: key, to: out, only: "keep")
            t.equal(r.restored, 2, "only the subfolder")
            let raw = try Data(contentsOf: Layout(destination: dest, key: key).manifests.appendingPathComponent(snap))
            t.check(!String(decoding: raw, as: UTF8.self).contains("keep/a.txt") && raw.prefix(5) == Data("STSM1".utf8), "manifest is ciphertext")
            let m = try Restore.manifest(named: snap, destination: dest, key: key)
            t.equal(m.files.map(\.path), ["keep/a.txt", "keep/b.txt", "other/c.txt"], "sorted paths")
        },
        TestCase(name: "walker skips symlinks, git and node_modules") { t in
            let src = try tempDir("src")
            defer { try? FileManager.default.removeItem(at: src) }
            try write(src, "real.txt", Data("x".utf8))
            try write(src, "node_modules/pkg/index.js", Data("y".utf8))
            try write(src, ".git/HEAD", Data("z".utf8))
            try FileManager.default.createSymbolicLink(at: src.appendingPathComponent("link"), withDestinationURL: URL(fileURLWithPath: "/etc"))
            let (files, placeholders, _) = Backup.walk(src)
            t.equal(files.map(\.rel), ["real.txt"], "only the real file")
            t.check(placeholders.isEmpty, "no placeholders in a temp dir")
        },
    ])
}
