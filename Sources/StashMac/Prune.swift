//  Stash for Mac — MIT licensed. See LICENSE.
//
//  Keeping the destination from growing forever: keep the newest N snapshots, then delete every
//  chunk no remaining snapshot references. Runs after each backup. Free tiers are small, so this
//  is not optional; the number kept is.

import Foundation

struct PruneReport: Equatable {
    var snapshotsRemoved = 0
    var chunksRemoved = 0
    var bytesFreed: Int64 = 0
    var chunksKept = 0
    var bytesKept: Int64 = 0
}

enum Prune {
    /// Deletes manifests beyond `keep` (newest first) and any chunk they alone referenced.
    /// Refuses to touch anything if a remaining manifest cannot be opened: a wrong key or a damaged
    /// manifest must never turn into deleted chunks.
    static func run(destination: URL, key: MasterKey, keep: Int = Config.keepSnapshots) throws -> PruneReport {
        let layout = Layout(destination: destination, key: key)
        let fm = FileManager.default
        var report = PruneReport()
        let manifests = layout.manifestFiles()
        let keepList = Array(manifests.prefix(max(keep, 1)))
        var referenced = Set<String>()
        for url in keepList {
            let m = try Manifest.open(try Data(contentsOf: url), key: key)   // throws → nothing is deleted
            for f in m.files { referenced.formUnion(f.chunks) }
        }
        for url in manifests.dropFirst(max(keep, 1)) {
            try fm.removeItem(at: url); report.snapshotsRemoved += 1
        }
        guard let dirs = try? fm.contentsOfDirectory(at: layout.chunks, includingPropertiesForKeys: nil) else { return report }
        for dir in dirs {
            guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { continue }
            for f in files {
                let size = Int64((try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                if referenced.contains(f.lastPathComponent) { report.chunksKept += 1; report.bytesKept += size }
                else { try fm.removeItem(at: f); report.chunksRemoved += 1; report.bytesFreed += size }
            }
            if (try? fm.contentsOfDirectory(atPath: dir.path))?.isEmpty == true { try? fm.removeItem(at: dir) }
        }
        return report
    }

    /// Bytes the stash occupies at a destination (chunks plus manifests).
    static func size(destination: URL, key: MasterKey) -> Int64 {
        let layout = Layout(destination: destination, key: key)
        guard let e = FileManager.default.enumerator(at: layout.root, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else { return 0 }
        var total: Int64 = 0
        for case let u as URL in e {
            if let v = try? u.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]), v.isRegularFile == true { total += Int64(v.fileSize ?? 0) }
        }
        return total
    }
}
