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
    static func run(destination: URL, key: MasterKey, keep: Int = Config.keepSnapshots, policy: Retention.Policy = Config.retention, now: Date = Date()) throws -> PruneReport {
        let layout = Layout(destination: destination, key: key)
        let fm = FileManager.default
        var report = PruneReport()
        let manifests = layout.manifestFiles()
        // Open every manifest first: a wrong key or a damaged manifest must never turn into deleted chunks.
        let opened = try manifests.map { try Manifest.open(try Data(contentsOf: $0), key: key) }
        let dates = opened.map(\.createdAt)
        let keepSet = policy == .thin ? Retention.thin(dates, now: now) : Retention.last(dates, keep: keep)
        var referenced = Set<String>()
        for i in keepSet { for f in opened[i].files { referenced.formUnion(f.chunks) } }
        for (i, url) in manifests.enumerated() where !keepSet.contains(i) {
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

    /// Deletes one snapshot by name, then the chunks only it used.
    static func delete(snapshot: String, destination: URL, key: MasterKey) throws -> PruneReport {
        let layout = Layout(destination: destination, key: key)
        let url = layout.manifests.appendingPathComponent(snapshot)
        _ = try Manifest.open(try Data(contentsOf: url), key: key)   // proves the key before deleting anything
        try FileManager.default.removeItem(at: url)
        var r = try run(destination: destination, key: key, keep: Int.max, policy: .last)
        r.snapshotsRemoved = 1
        return r
    }

    /// Per snapshot: bytes held by chunks that no other snapshot references, i.e. what deleting it frees.
    static func uniqueSizes(destination: URL, key: MasterKey) -> [String: Int64] {
        let layout = Layout(destination: destination, key: key)
        let manifests = layout.manifestFiles()
        var refs: [String: Int] = [:]
        var perSnapshot: [String: Set<String>] = [:]
        for url in manifests {
            guard let m = try? Manifest.open(try Data(contentsOf: url), key: key) else { continue }
            let set = Set(m.files.flatMap(\.chunks))
            perSnapshot[url.lastPathComponent] = set
            for c in set { refs[c, default: 0] += 1 }
        }
        var sizes: [String: Int64] = [:]
        for (name, set) in perSnapshot {
            var total: Int64 = 0
            for c in set where refs[c] == 1 {
                total += Int64((try? layout.chunk(c).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
            sizes[name] = total
        }
        return sizes
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
