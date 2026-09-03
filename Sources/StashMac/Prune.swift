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
        try run(store: FolderStore(destination: destination, key: key), key: key, keep: keep, policy: policy, now: now)
    }

    static func run(store: ChunkStore, key: MasterKey, keep: Int = Config.keepSnapshots, policy: Retention.Policy = Config.retention, now: Date = Date()) throws -> PruneReport {
        var report = PruneReport()
        let manifests = store.manifestNames()
        // Open every manifest first: a wrong key or a damaged manifest must never turn into deleted chunks.
        let opened = try manifests.map { try Manifest.open(try store.getManifest($0), key: key) }
        let dates = opened.map(\.createdAt)
        let keepSet = policy == .thin ? Retention.thin(dates, now: now) : Retention.last(dates, keep: keep)
        var referenced = Set<String>()
        var released = Set<String>()   // chunks the removed manifests used: complete uploads, free to go now
        for (i, m) in opened.enumerated() {
            for f in m.files { if keepSet.contains(i) { referenced.formUnion(f.chunks) } else { released.formUnion(f.chunks) } }
        }
        for (i, name) in manifests.enumerated() where !keepSet.contains(i) {
            try store.deleteManifest(name); report.snapshotsRemoved += 1
        }
        for name in store.chunkNames() {
            let size = store.chunkSize(name)
            if referenced.contains(name) { report.chunksKept += 1; report.bytesKept += size; continue }
            // A chunk no manifest has ever referenced is either an orphan from an interrupted run or an
            // upload in flight from another Mac on the same card; leave it alone while it is fresh.
            if !released.contains(name), let written = store.chunkDate(name), now.timeIntervalSince(written) < grace { report.chunksKept += 1; report.bytesKept += size; continue }
            try store.deleteChunk(name); report.chunksRemoved += 1; report.bytesFreed += size
        }
        return report
    }

    /// Unreferenced chunks younger than this are never deleted.
    static let grace: TimeInterval = 2 * 3600

    /// Deletes one snapshot by name, then the chunks only it used.
    static func delete(snapshot: String, destination: URL, key: MasterKey) throws -> PruneReport {
        try delete(snapshot: snapshot, store: FolderStore(destination: destination, key: key), key: key)
    }

    static func delete(snapshot: String, store: ChunkStore, key: MasterKey) throws -> PruneReport {
        let manifests = store.manifestNames()
        guard manifests.contains(snapshot) else { throw ChunkError.notAChunk }
        let opened = try manifests.map { try Manifest.open(try store.getManifest($0), key: key) }   // proves the key before deleting anything
        var referenced = Set<String>(), released = Set<String>()
        for (i, m) in opened.enumerated() { for f in m.files { if manifests[i] == snapshot { released.formUnion(f.chunks) } else { referenced.formUnion(f.chunks) } } }
        try store.deleteManifest(snapshot)
        var report = PruneReport(snapshotsRemoved: 1)
        for name in store.chunkNames() {
            let size = store.chunkSize(name)
            if referenced.contains(name) { report.chunksKept += 1; report.bytesKept += size; continue }
            if !released.contains(name), let written = store.chunkDate(name), Date().timeIntervalSince(written) < grace { report.chunksKept += 1; report.bytesKept += size; continue }
            try store.deleteChunk(name); report.chunksRemoved += 1; report.bytesFreed += size
        }
        return report
    }

    /// Per snapshot: bytes held by chunks that no other snapshot references, i.e. what deleting it frees.
    static func uniqueSizes(destination: URL, key: MasterKey) -> [String: Int64] { uniqueSizes(store: FolderStore(destination: destination, key: key), key: key) }

    static func uniqueSizes(store: ChunkStore, key: MasterKey) -> [String: Int64] {
        var refs: [String: Int] = [:]
        var perSnapshot: [String: Set<String>] = [:]
        for name in store.manifestNames() {
            guard let data = try? store.getManifest(name), let m = try? Manifest.open(data, key: key) else { continue }
            let set = Set(m.files.flatMap(\.chunks))
            perSnapshot[name] = set
            for c in set { refs[c, default: 0] += 1 }
        }
        var sizes: [String: Int64] = [:]
        for (name, set) in perSnapshot {
            sizes[name] = set.filter { refs[$0] == 1 }.reduce(0) { $0 + store.chunkSize($1) }
        }
        return sizes
    }

    /// Bytes the stash occupies at a destination (chunks plus manifests).
    static func size(destination: URL, key: MasterKey) -> Int64 { FolderStore(destination: destination, key: key).totalSize() }
}
