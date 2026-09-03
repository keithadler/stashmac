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
    static func snapshots(destination: URL, key: MasterKey) -> [SnapshotInfo] {
        let layout = Layout(destination: destination, key: key)
        return layout.manifestFiles().compactMap { url in
            guard let data = try? Data(contentsOf: url), let m = try? Manifest.open(data, key: key) else { return nil }
            return SnapshotInfo(fileName: url.lastPathComponent, createdAt: m.createdAt, host: m.host, files: m.files.count, bytes: m.totalBytes, placeholders: m.skippedPlaceholders.count)
        }
    }

    static func manifest(named name: String, destination: URL, key: MasterKey) throws -> Manifest {
        let layout = Layout(destination: destination, key: key)
        return try Manifest.open(try Data(contentsOf: layout.manifests.appendingPathComponent(name)), key: key)
    }

    /// Restores files from a snapshot into `target`/<source folder name>/<relative path>.
    /// `only` limits to relative paths starting with that prefix (a file or a folder).
    static func run(snapshot: String, destination: URL, key: MasterKey, to target: URL, only: String? = nil,
                    progress: ((Int, Int) -> Void)? = nil) throws -> RestoreReport {
        let layout = Layout(destination: destination, key: key)
        let m = try manifest(named: snapshot, destination: destination, key: key)
        let wanted = m.files.filter { only == nil || $0.path == only! || $0.path.hasPrefix(only!.hasSuffix("/") ? only! : only! + "/") }
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
                    let blob = try Data(contentsOf: layout.chunk(name))
                    try h.write(contentsOf: try Chunk.open(blob, key: key))
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
        let layout = Layout(destination: destination, key: key)
        guard let latest = layout.manifestFiles().first else { return VerifyReport() }
        let m = try Manifest.open(try Data(contentsOf: latest), key: key)
        var report = VerifyReport()
        let names = Array(Set(m.files.flatMap(\.chunks))).sorted()
        for (n, name) in names.enumerated() {
            let url = layout.chunk(name)
            guard let blob = try? Data(contentsOf: url) else { report.chunksMissing.append(name); continue }
            if (try? Chunk.open(blob, key: key)) == nil { report.chunksBad.append(name) }
            report.chunksChecked += 1
            progress?(n + 1, names.count)
        }
        if let pick = m.files.randomElement() {
            report.sampleFile = pick.path
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("stashmac-verify-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: tmp) }
            let r = try run(snapshot: latest.lastPathComponent, destination: destination, key: key, to: tmp, only: pick.path)
            let sourceName = URL(fileURLWithPath: m.sources[pick.source]).lastPathComponent
            let restored = tmp.appendingPathComponent(sourceName).appendingPathComponent(pick.path)
            let size = (try? FileManager.default.attributesOfItem(atPath: restored.path)[.size] as? Int64) ?? -1
            report.sampleOK = r.failed.isEmpty && size == pick.size
        }
        return report
    }
}
