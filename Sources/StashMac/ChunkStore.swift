//  Stash for Mac — MIT licensed. See LICENSE.
//
//  Where chunks and manifests live. The backup, restore, verify and prune code speaks only to this
//  protocol, so a Google Drive or OneDrive store can be added without touching any of it. The one
//  implementation today is a folder, which already covers every provider that has a desktop app.

import Foundation

protocol ChunkStore {
    var name: String { get }
    func prepare() throws
    func hasChunk(_ name: String) -> Bool
    func putChunk(_ name: String, _ data: Data) throws
    func getChunk(_ name: String) throws -> Data
    func deleteChunk(_ name: String) throws
    func chunkNames() -> [String]
    func chunkSize(_ name: String) -> Int64
    /// Newest first.
    func manifestNames() -> [String]
    func putManifest(_ name: String, _ data: Data) throws
    func getManifest(_ name: String) throws -> Data
    func deleteManifest(_ name: String) throws
    func totalSize() -> Int64
}

/// A folder: local disk, NAS, or the folder a cloud provider's desktop app syncs.
struct FolderStore: ChunkStore {
    let layout: Layout
    let destination: URL
    var name: String { destination.lastPathComponent }

    init(destination: URL, key: MasterKey) {
        self.destination = destination
        layout = Layout(destination: destination, key: key)
    }

    func prepare() throws { try layout.prepare() }
    func hasChunk(_ name: String) -> Bool { FileManager.default.fileExists(atPath: layout.chunk(name).path) }
    func putChunk(_ name: String, _ data: Data) throws {
        let url = layout.chunk(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
    func getChunk(_ name: String) throws -> Data { try Data(contentsOf: layout.chunk(name)) }
    func deleteChunk(_ name: String) throws {
        let url = layout.chunk(name)
        try FileManager.default.removeItem(at: url)
        let dir = url.deletingLastPathComponent()
        if (try? FileManager.default.contentsOfDirectory(atPath: dir.path))?.isEmpty == true { try? FileManager.default.removeItem(at: dir) }
    }
    func chunkNames() -> [String] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: layout.chunks, includingPropertiesForKeys: nil) else { return [] }
        return dirs.flatMap { (try? fm.contentsOfDirectory(atPath: $0.path)) ?? [] }.filter { $0.count == 64 }
    }
    func chunkSize(_ name: String) -> Int64 { Int64((try? layout.chunk(name).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    func manifestNames() -> [String] { layout.manifestFiles().map(\.lastPathComponent) }
    func putManifest(_ name: String, _ data: Data) throws { try data.write(to: layout.manifests.appendingPathComponent(name), options: .atomic) }
    func getManifest(_ name: String) throws -> Data { try Data(contentsOf: layout.manifests.appendingPathComponent(name)) }
    func deleteManifest(_ name: String) throws { try FileManager.default.removeItem(at: layout.manifests.appendingPathComponent(name)) }
    func totalSize() -> Int64 {
        guard let e = FileManager.default.enumerator(at: layout.root, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else { return 0 }
        var total: Int64 = 0
        for case let u as URL in e {
            if let v = try? u.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]), v.isRegularFile == true { total += Int64(v.fileSize ?? 0) }
        }
        return total
    }
}
