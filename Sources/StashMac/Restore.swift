//  Stash for Mac — MIT licensed. See LICENSE.
//
//  Reading a backup back: list snapshots, restore files to a place of your choosing, and verify
//  that every chunk still opens. A chunk that fails authentication stops that file and is reported;
//  nothing partial is written where a good file should go.

import Foundation
import CryptoKit

struct SnapshotInfo: Identifiable, Equatable {
    var id: String { fileName }
    let fileName: String
    let createdAt: Date
    let host: String
    let files: Int
    let bytes: Int64
    let placeholders: Int
}

struct RestoreReport: Equatable {
    var restored = 0
    var bytes: Int64 = 0
    var failed: [String] = []
}

struct VerifyReport: Equatable {
    var chunksChecked = 0
    var chunksBad: [String] = []
    var chunksMissing: [String] = []
    var sampleFile: String?
    var sampleOK: Bool?
}

enum Restore {
    static func snapshots(destination: URL, key: MasterKey) -> [SnapshotInfo] { snapshots(store: FolderStore(destination: destination, key: key), key: key) }

    static func snapshots(store: ChunkStore, key: MasterKey) -> [SnapshotInfo] {
        store.manifestNames().compactMap { name in
            guard let data = try? store.getManifest(name), let m = try? Manifest.open(data, key: key) else { return nil }
            return SnapshotInfo(fileName: name, createdAt: m.createdAt, host: m.host, files: m.files.count, bytes: m.totalBytes, placeholders: m.skippedPlaceholders.count)
        }
    }

    static func manifest(named name: String, destination: URL, key: MasterKey) throws -> Manifest {
        try manifest(named: name, store: FolderStore(destination: destination, key: key), key: key)
    }
    static func manifest(named name: String, store: ChunkStore, key: MasterKey) throws -> Manifest {
        try Manifest.open(try store.getManifest(name), key: key)
    }

    /// True when `path` is `prefix` itself or lives under it.
    static func selected(_ path: String, by prefixes: [String]) -> Bool {
        prefixes.isEmpty || prefixes.contains { path == $0 || path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
    }

    /// Restores files from a snapshot into `target`/<source folder name>/<relative path>.
    /// `only` limits to relative paths equal to or under any of the given prefixes (files or folders).
    static func run(snapshot: String, destination: URL, key: MasterKey, to target: URL, only: String? = nil,
                    progress: ((Int, Int) -> Void)? = nil) throws -> RestoreReport {
        try run(snapshot: snapshot, store: FolderStore(destination: destination, key: key), key: key, to: target, only: only.map { [$0] } ?? [], progress: progress)
    }

    static func run(snapshot: String, store: ChunkStore, key: MasterKey, to target: URL, only: [String] = [],
                    progress: ((Int, Int) -> Void)? = nil) throws -> RestoreReport {
        let m = try manifest(named: snapshot, store: store, key: key)
        let wanted = m.files.filter { selected($0.path, by: only) }
        var report = RestoreReport()
        for (n, f) in wanted.enumerated() {
            let sourceName = URL(fileURLWithPath: m.sources[f.source]).lastPathComponent
            let out = target.appendingPathComponent(sourceName, isDirectory: true).appendingPathComponent(f.path)
            let tmp = out.appendingPathExtension("stash-partial")
            do {
                try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
                FileManager.default.createFile(atPath: tmp.path, contents: nil)
                let h = try FileHandle(forWritingTo: tmp)
                defer { try? h.close() }
                for name in f.chunks {
                    try h.write(contentsOf: try Chunk.open(try store.getChunk(name), key: key))
                }
                try h.close()
                if FileManager.default.fileExists(atPath: out.path) { try FileManager.default.removeItem(at: out) }
                try FileManager.default.moveItem(at: tmp, to: out)
                try? FileManager.default.setAttributes([.modificationDate: f.modified], ofItemAtPath: out.path)
                report.restored += 1; report.bytes += f.size
            } catch {
                try? FileManager.default.removeItem(at: tmp)
                report.failed.append(f.path + ": " + error.localizedDescription)
            }
            progress?(n + 1, wanted.count)
        }
        return report
    }

    /// Opens every chunk the latest snapshot references, and restores one random file to a
    /// temporary folder to prove the whole path works.
    static func verify(destination: URL, key: MasterKey, progress: ((Int, Int) -> Void)? = nil) throws -> VerifyReport {
        try verify(store: FolderStore(destination: destination, key: key), key: key, progress: progress)
    }

    static func verify(store: ChunkStore, key: MasterKey, progress: ((Int, Int) -> Void)? = nil) throws -> VerifyReport {
        guard let latest = store.manifestNames().first else { return VerifyReport() }
        let m = try Manifest.open(try store.getManifest(latest), key: key)
        var report = VerifyReport()
        let names = Array(Set(m.files.flatMap(\.chunks))).sorted()
        for (n, name) in names.enumerated() {
            guard store.hasChunk(name), let blob = try? store.getChunk(name) else { report.chunksMissing.append(name); continue }
            if (try? Chunk.open(blob, key: key)) == nil { report.chunksBad.append(name) }
            report.chunksChecked += 1
            progress?(n + 1, names.count)
        }
        if let pick = m.files.randomElement() {
            report.sampleFile = pick.path
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("stashmac-verify-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: tmp) }
            let r = try run(snapshot: latest, store: store, key: key, to: tmp, only: [pick.path])
            let sourceName = URL(fileURLWithPath: m.sources[pick.source]).lastPathComponent
            let restored = tmp.appendingPathComponent(sourceName).appendingPathComponent(pick.path)
            let size = (try? FileManager.default.attributesOfItem(atPath: restored.path)[.size] as? Int64) ?? -1
            report.sampleOK = r.failed.isEmpty && size == pick.size
        }
        return report
    }
}
