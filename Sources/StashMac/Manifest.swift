//  Stash for Mac — MIT licensed. See LICENSE.
//
//  A snapshot manifest: every file in the chosen folders at one moment, with the chunk names that
//  rebuild it. Stored encrypted under the manifest key, so the provider never sees a file name.

import Foundation
import CryptoKit

struct Manifest: Codable {
    struct File: Codable, Equatable {
        var source: Int          // index into sources
        var path: String         // relative to the source root
        var size: Int64
        var modified: Date
        var chunks: [String]     // chunk names in order
    }
    var format = 1
    var createdAt = Date()
    var host = Host.current().localizedName ?? "Mac"
    var sources: [String]        // absolute source roots at backup time
    var files: [File]
    var skippedPlaceholders: [String] = []   // dataless files listed, never downloaded

    var totalBytes: Int64 { files.reduce(0) { $0 + $1.size } }

    static let magic = Data("STSM1".utf8)

    func sealed(key: MasterKey) throws -> Data {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        return Manifest.magic + (try ChaChaPoly.seal(try enc.encode(self), using: key.manifestKey).combined)
    }

    static func open(_ blob: Data, key: MasterKey) throws -> Manifest {
        guard blob.prefix(magic.count) == magic else { throw ChunkError.notAChunk }
        let plain: Data
        do { plain = try ChaChaPoly.open(try ChaChaPoly.SealedBox(combined: blob.dropFirst(magic.count)), using: key.manifestKey) }
        catch { throw ChunkError.corruptOrWrongKey }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try dec.decode(Manifest.self, from: plain)
    }

    /// File name at the destination: sortable, no information about contents.
    var fileName: String {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss-SSS"; f.timeZone = TimeZone(identifier: "UTC"); f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: createdAt) + ".stsm"
    }
}

/// Where things live inside a destination folder: one subtree per key fingerprint, so one drive
/// can hold several stashes and a wrong card never overwrites the right one.
struct Layout {
    let root: URL
    init(destination: URL, key: MasterKey) {
        root = destination.appendingPathComponent("Stash for Mac", isDirectory: true).appendingPathComponent(key.fingerprint, isDirectory: true)
    }
    var chunks: URL { root.appendingPathComponent("chunks", isDirectory: true) }
    var manifests: URL { root.appendingPathComponent("manifests", isDirectory: true) }
    func chunk(_ name: String) -> URL { chunks.appendingPathComponent(String(name.prefix(2)), isDirectory: true).appendingPathComponent(name) }

    func prepare() throws {
        try FileManager.default.createDirectory(at: chunks, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: manifests, withIntermediateDirectories: true)
        let note = root.appendingPathComponent("README.txt")
        if !FileManager.default.fileExists(atPath: note.path) {
            try """
            This folder is a Stash for Mac backup. Every file in it is encrypted; nothing here can be read
            without the 24-word recovery card that was shown when the backup was set up.
            To restore: install Stash for Mac (github.com/keithadler/stashmac), enter the card, choose this folder.
            """.write(to: note, atomically: true, encoding: .utf8)
        }
    }

    /// Manifests newest first.
    func manifestFiles() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: manifests, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "stsm" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
}
