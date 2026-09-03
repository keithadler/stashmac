//  Stash for Mac — MIT licensed. See LICENSE.
//
//  The backup itself: walk the chosen folders, split each file into chunks, upload the ones the
//  destination doesn't have, write the manifest. Streams files in 4 MB pieces so a 20 GB movie
//  never sits in memory. Cloud placeholders are listed and skipped; reading one would make the
//  provider download it behind the user's back.

import Foundation
import CryptoKit

struct BackupReport: Equatable {
    var files = 0
    var bytes: Int64 = 0
    var newChunks = 0
    var newBytes: Int64 = 0
    var reusedChunks = 0
    var skippedPlaceholders = 0
    var skippedByRule = 0
    var unreadable: [String] = []
    var manifest: String = ""
}

enum Backup {
    /// True for files whose bytes are not on this disk (iCloud, Dropbox, OneDrive, Google Drive placeholders).
    static func isDataless(_ url: URL) -> Bool {
        var st = stat()
        if lstat(url.path, &st) == 0, st.st_flags & UInt32(SF_DATALESS) != 0 { return true }
        if let v = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
           v.isUbiquitousItem == true, let status = v.ubiquitousItemDownloadingStatus, status != .current { return true }
        return false
    }

    static let ignoredNames: Set<String> = [".DS_Store", ".localized", "Icon\r", ".Trash", "node_modules", ".git"]

    /// Shell-style pattern match on a file or folder name (`*.tmp`, `Cache*`, `*.photoslibrary`).
    static func matches(_ name: String, _ pattern: String) -> Bool {
        fnmatch(pattern, name, FNM_CASEFOLD) == 0
    }

    /// Regular files under a root, relative paths sorted, placeholders separated out. Never follows symlinks.
    /// `exclude` are name patterns; `maxBytes` skips larger files (0 = no cap). Both counted in `skipped`.
    static func walk(_ root: URL, exclude: [String] = Config.excludePatterns, maxBytes: Int64 = Config.maxFileBytes) -> (files: [(rel: String, url: URL, size: Int64, modified: Date)], placeholders: [String], skipped: Int) {
        var files: [(String, URL, Int64, Date)] = []
        var placeholders: [String] = []
        var skipped = 0
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey, .nameKey]
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else { return ([], [], 0) }
        let rootPath = root.standardizedFileURL.path + "/"
        for case let url as URL in e {
            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if let n = v.name, ignoredNames.contains(n) { if v.isDirectory == true { e.skipDescendants() }; continue }
            if let n = v.name, exclude.contains(where: { matches(n, $0) }) { skipped += 1; if v.isDirectory == true { e.skipDescendants() }; continue }
            if v.isSymbolicLink == true { if v.isDirectory == true { e.skipDescendants() }; continue }
            guard v.isRegularFile == true else { continue }
            let rel = String(url.standardizedFileURL.path.dropFirst(rootPath.count))
            if isDataless(url) { placeholders.append(rel); continue }
            let size = Int64(v.fileSize ?? 0)
            if maxBytes > 0 && size > maxBytes { skipped += 1; continue }
            files.append((rel, url, size, v.contentModificationDate ?? .distantPast))
        }
        files.sort { $0.0 < $1.0 }
        return (files.map { (rel: $0.0, url: $0.1, size: $0.2, modified: $0.3) }, placeholders, skipped)
    }

    /// Runs one backup of `sources` into a folder destination. `progress` gets (files done, files total, bytes done).
    static func run(sources: [URL], destination: URL, key: MasterKey, progress: ((Int, Int, Int64) -> Void)? = nil) throws -> BackupReport {
        try run(sources: sources, store: FolderStore(destination: destination, key: key), key: key, progress: progress)
    }

    /// Runs one backup of `sources` into any chunk store.
    static func run(sources: [URL], store: ChunkStore, key: MasterKey, progress: ((Int, Int, Int64) -> Void)? = nil) throws -> BackupReport {
        try store.prepare()
        var report = BackupReport()
        var manifest = Manifest(sources: sources.map(\.path), files: [])
        var walked: [(source: Int, rel: String, url: URL, size: Int64, modified: Date)] = []
        for (i, s) in sources.enumerated() {
            let (files, placeholders, skipped) = walk(s)
            walked += files.map { (i, $0.rel, $0.url, $0.size, $0.modified) }
            manifest.skippedPlaceholders += placeholders.map { s.lastPathComponent + "/" + $0 }
            report.skippedByRule += skipped
        }
        report.skippedPlaceholders = manifest.skippedPlaceholders.count
        var done: Int64 = 0
        for (n, f) in walked.enumerated() {
            guard let h = try? FileHandle(forReadingFrom: f.url) else { report.unreadable.append(f.rel); continue }
            defer { try? h.close() }
            var names: [String] = []
            var readAny = false
            while true {
                let piece = (try? h.read(upToCount: Chunk.size)) ?? Data()
                if piece.isEmpty && readAny { break }
                readAny = true
                let name = Chunk.name(for: piece, key: key)
                if store.hasChunk(name) {
                    report.reusedChunks += 1
                } else {
                    let blob = try Chunk.seal(piece, key: key)
                    try store.putChunk(name, blob)
                    report.newChunks += 1; report.newBytes += Int64(blob.count)
                }
                names.append(name)
                done += Int64(piece.count)
                if piece.isEmpty || piece.count < Chunk.size { break }
            }
            manifest.files.append(Manifest.File(source: f.source, path: f.rel, size: f.size, modified: f.modified, chunks: names))
            report.files += 1; report.bytes += f.size
            progress?(n + 1, walked.count, done)
        }
        // Two backups in the same millisecond still get distinct names.
        var name = manifest.fileName
        let existing = Set(store.manifestNames())
        var n = 1
        while existing.contains(name) { name = manifest.fileName.replacingOccurrences(of: ".stsm", with: "-\(n).stsm"); n += 1 }
        try store.putManifest(name, try manifest.sealed(key: key))
        report.manifest = name
        return report
    }
}
