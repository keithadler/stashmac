//  Stash for Mac — MIT licensed. See LICENSE.
//
//  The command-line face. Exit codes: 0 fine, 1 warning, 2 problem, 64 usage error.

import Foundation
import AppKit

enum CLI {
    static let usage = """
    stashmac — encrypted backup into storage you already have (command-line face)

    USAGE
      stashmac key new [--json]         make a key on this Mac and print the 24 words
      stashmac key show [--json]        print this Mac's words and fingerprint
      stashmac key card <file.pdf>      write the printable recovery card
      stashmac key restore "<24 words>" | --qr <image.png>
                                        install a key from a card
      stashmac key forget               remove the key from this Mac's Keychain
      stashmac add <folder>             back this folder up (repeatable); stashmac remove <folder>
      stashmac dest <folder>            a destination: any folder a provider syncs, a disk, a NAS
      stashmac backup [--json]          back up every folder to every destination now
      stashmac snapshots [--json]       list snapshots at each destination
      stashmac restore <snapshot|latest> <target folder> [--only <path>] [--dest <folder>]
      stashmac verify [--json]          open every chunk of the latest snapshot; restore one random file
      stashmac prune [--keep N] [--json] drop old snapshots and the chunks only they used (runs after each backup)
      stashmac seal <in> <out>          encrypt one file as a chunk (proof of the format)
      stashmac open <in> <out>          decrypt one chunk
      stashmac status [--json]
      stashmac screenshots <dir> [--announce]   render windows and promo cards from demo data; --announce copies the kit to the Desktop
      stashmac selftest [--filter S] [--list] [--json]
      stashmac help | version

    Destinations are folders on purpose: iCloud Drive, Google Drive, OneDrive and Dropbox all appear
    as folders through their own apps, so no API keys or accounts are needed. Everything written
    there is encrypted; the 24-word card is the only way to read it back.
    """

    static var version: String {
        if Bundle.main.bundleIdentifier == "com.keithadler.stashmac", let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String { return v }
        var url = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath()
        while url.path != "/" {
            if url.pathExtension == "app", let b = Bundle(url: url), b.bundleIdentifier == "com.keithadler.stashmac",
               let v = b.infoDictionary?["CFBundleShortVersionString"] as? String { return v }
            url = url.deletingLastPathComponent()
        }
        return "dev"
    }

    static func runIfRequested() {
        if let dir = ProcessInfo.processInfo.environment["STASHMAC_TEST"], !dir.isEmpty {   // integration runs: no Keychain, no real defaults
            KeyStore.fileDirectory = URL(fileURLWithPath: dir, isDirectory: true)
            Config.defaults = UserDefaults(suiteName: "com.keithadler.stashmac.test")!
        }
        let args = Array(CommandLine.arguments.dropFirst())
        guard let cmd = args.first, !cmd.hasPrefix("-psn") else { return }
        exit(run(cmd, Array(args.dropFirst())))
    }

    static func flag(_ n: String, _ a: [String]) -> Bool { a.contains(n) }
    static func value(_ n: String, _ a: [String]) -> String? { guard let i = a.firstIndex(of: n), i + 1 < a.count else { return nil }; return a[i + 1] }
    static func positional(_ a: [String]) -> [String] {
        var out: [String] = []; var skip = false
        for x in a { if skip { skip = false; continue }; if ["--filter", "--qr", "--only", "--dest", "--keep"].contains(x) { skip = true; continue }; if x.hasPrefix("--") { continue }; out.append(x) }
        return out
    }

    static func json(_ o: Any) -> String {
        guard JSONSerialization.isValidJSONObject(o), let d = try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys]) else { return "{}" }
        return String(decoding: d, as: UTF8.self)
    }

    static func run(_ cmd: String, _ args: [String]) -> Int32 {
        let js = flag("--json", args)
        let pos = positional(args)
        switch cmd {
        case "help", "--help", "-h": print(usage); return 0
        case "version", "--version": print("stashmac \(version)"); return 0

        case "key":
            switch pos.first {
            case "new":
                if KeyStore.load() != nil { fputs("This Mac already has a key. `stashmac key forget` first if you really want a new one.\n", stderr); return 2 }
                let k = MasterKey.random(); KeyStore.save(k)
                print(js ? json(["fingerprint": k.fingerprint, "words": k.words]) : "New key \(k.fingerprint). Write these down or print the card:\n\n" + Mnemonic.card(k.words))
                return 0
            case "show":
                guard let k = KeyStore.load() else { fputs("no key on this Mac\n", stderr); return 2 }
                print(js ? json(["fingerprint": k.fingerprint, "words": k.words]) : "Key \(k.fingerprint)\n\n" + Mnemonic.card(k.words))
                return 0
            case "card":
                guard let k = KeyStore.load() else { fputs("no key on this Mac\n", stderr); return 2 }
                guard pos.count > 1 else { fputs("key card needs a file\n", stderr); return 64 }
                guard let pdf = MainActor.assumeIsolated({ QR.recoveryCard(k, stashName: "default") }) else { fputs("could not render the card\n", stderr); return 2 }
                do { try pdf.write(to: URL(fileURLWithPath: pos[1])); print("wrote \(pos[1])"); return 0 } catch { fputs("\(error.localizedDescription)\n", stderr); return 2 }
            case "restore":
                let k: MasterKey
                if let qr = value("--qr", args) {
                    guard let data = try? Data(contentsOf: URL(fileURLWithPath: qr)), let payload = QR.read(data), let key = MasterKey.fromQRPayload(payload) else { fputs("no Stash for Mac key in that image\n", stderr); return 2 }
                    k = key
                } else {
                    guard pos.count > 1 else { fputs("key restore needs the 24 words or --qr <image>\n", stderr); return 64 }
                    do { k = try MasterKey(words: pos.dropFirst().joined(separator: " ")) } catch { fputs("\(error.localizedDescription)\n", stderr); return 2 }
                }
                KeyStore.save(k)
                print(js ? json(["fingerprint": k.fingerprint]) : "key \(k.fingerprint) installed on this Mac")
                return 0
            case "forget":
                KeyStore.delete(); print("key removed from this Mac. The recovery card still works."); return 0
            default:
                fputs("key new | show | card <file> | restore <words> | forget\n", stderr); return 64
            }

        case "seal", "open":
            guard pos.count >= 2 else { fputs("\(cmd) <in> <out>\n", stderr); return 64 }
            guard let k = KeyStore.load() else { fputs("no key on this Mac\n", stderr); return 2 }
            do {
                let input = try Data(contentsOf: URL(fileURLWithPath: pos[0]))
                let output = cmd == "seal" ? try Chunk.seal(input, key: k) : try Chunk.open(input, key: k)
                try output.write(to: URL(fileURLWithPath: pos[1]))
                if cmd == "seal" { print("sealed \(input.count) bytes → \(output.count) bytes, chunk name \(Chunk.name(for: input, key: k).prefix(16))…") }
                else { print("opened \(output.count) bytes") }
                return 0
            } catch { fputs("\(error.localizedDescription)\n", stderr); return 2 }

        case "add", "remove":
            guard let f = pos.first else { fputs("\(cmd) <folder>\n", stderr); return 64 }
            let url = URL(fileURLWithPath: f).standardizedFileURL
            if cmd == "add" {
                guard Config.isFolder(url) else { fputs("not a folder: \(url.path)\n", stderr); return 2 }
                if !Config.sources.contains(url) { Config.sources += [url] }
                print("backing up \(url.path)")
            } else {
                Config.sources.removeAll { $0 == url }; print("no longer backing up \(url.path)")
            }
            return 0

        case "dest":
            guard let f = pos.first else { fputs("dest <folder>\n", stderr); return 64 }
            let url = URL(fileURLWithPath: f).standardizedFileURL
            guard Config.isFolder(url) else { fputs("not a folder: \(url.path)\n", stderr); return 2 }
            if !Config.destinations.contains(url) { Config.destinations += [url] }
            print("backups go to \(url.path)")
            return 0

        case "backup":
            guard let k = KeyStore.load() else { fputs("no key on this Mac (stashmac key new)\n", stderr); return 2 }
            guard !Config.sources.isEmpty else { fputs("nothing to back up (stashmac add <folder>)\n", stderr); return 2 }
            guard !Config.destinations.isEmpty else { fputs("nowhere to put it (stashmac dest <folder>)\n", stderr); return 2 }
            var results: [[String: Any]] = []
            var worst: Int32 = 0
            for d in Config.destinations {
                do {
                    let r = try Backup.run(sources: Config.sources, destination: d, key: k) { done, total, _ in
                        if !js && done % 50 == 0 { fputs("\r\(done)/\(total) files", stderr) }
                    }
                    if !js { fputs("\r", stderr) }
                    results.append(["destination": d.path, "files": r.files, "bytes": r.bytes, "new_chunks": r.newChunks, "new_bytes": r.newBytes,
                                    "reused_chunks": r.reusedChunks, "skipped_placeholders": r.skippedPlaceholders, "unreadable": r.unreadable, "manifest": r.manifest])
                    if !js {
                        print("\(d.path): \(r.files) files, \(ByteCountFormatter.string(fromByteCount: r.bytes, countStyle: .file)); uploaded \(r.newChunks) chunks (\(ByteCountFormatter.string(fromByteCount: r.newBytes, countStyle: .file))), reused \(r.reusedChunks)"
                              + (r.skippedPlaceholders > 0 ? "; \(r.skippedPlaceholders) cloud placeholders listed, not downloaded" : "")
                              + (r.unreadable.isEmpty ? "" : "; \(r.unreadable.count) unreadable"))
                    }
                    if r.skippedPlaceholders > 0 || !r.unreadable.isEmpty { worst = max(worst, 1) }
                } catch {
                    results.append(["destination": d.path, "error": error.localizedDescription])
                    if !js { fputs("\(d.path): \(error.localizedDescription)\n", stderr) }
                    worst = 2
                }
            }
            Config.lastBackup = Date()
            for d in Config.destinations { if let p = try? Prune.run(destination: d, key: k), p.bytesFreed > 0, !js { print("\(d.path): reclaimed \(ByteCountFormatter.string(fromByteCount: p.bytesFreed, countStyle: .file)) from \(p.snapshotsRemoved) old snapshots") } }
            if js { print(json(["results": results])) }
            return worst

        case "snapshots":
            guard let k = KeyStore.load() else { fputs("no key on this Mac\n", stderr); return 2 }
            var all: [[String: Any]] = []
            for d in Config.destinations {
                let snaps = Restore.snapshots(destination: d, key: k)
                if !js { print(d.path + (snaps.isEmpty ? ": no snapshots" : "")) }
                for s in snaps {
                    all.append(["destination": d.path, "snapshot": s.fileName, "created_at": ISO8601DateFormatter().string(from: s.createdAt), "host": s.host, "files": s.files, "bytes": s.bytes, "placeholders": s.placeholders])
                    if !js { print("  \(s.fileName)  \(s.createdAt.formatted(date: .abbreviated, time: .shortened))  \(s.files) files, \(ByteCountFormatter.string(fromByteCount: s.bytes, countStyle: .file)), from \(s.host)") }
                }
            }
            if js { print(json(["snapshots": all])) }
            return all.isEmpty ? 1 : 0

        case "restore":
            guard let k = KeyStore.load() else { fputs("no key on this Mac\n", stderr); return 2 }
            guard pos.count >= 2 else { fputs("restore <snapshot|latest> <target folder> [--only <path>] [--dest <folder>]\n", stderr); return 64 }
            let dest = value("--dest", args).map { URL(fileURLWithPath: $0) } ?? Config.destinations.first
            guard let dest else { fputs("no destination (stashmac dest <folder> or --dest)\n", stderr); return 2 }
            let snaps = Restore.snapshots(destination: dest, key: k)
            guard let snap = pos[0] == "latest" ? snaps.first?.fileName : snaps.first(where: { $0.fileName == pos[0] })?.fileName else { fputs("no such snapshot at \(dest.path)\n", stderr); return 2 }
            let target = URL(fileURLWithPath: pos[1])
            do {
                let r = try Restore.run(snapshot: snap, destination: dest, key: k, to: target, only: value("--only", args))
                print(js ? json(["restored": r.restored, "bytes": r.bytes, "failed": r.failed]) : "restored \(r.restored) files (\(ByteCountFormatter.string(fromByteCount: r.bytes, countStyle: .file))) into \(target.path)" + (r.failed.isEmpty ? "" : "\nFAILED:\n  " + r.failed.joined(separator: "\n  ")))
                return r.failed.isEmpty ? 0 : 2
            } catch { fputs("\(error.localizedDescription)\n", stderr); return 2 }

        case "verify":
            guard let k = KeyStore.load() else { fputs("no key on this Mac\n", stderr); return 2 }
            var worst: Int32 = 0
            var out: [[String: Any]] = []
            for d in Config.destinations {
                do {
                    let v = try Restore.verify(destination: d, key: k)
                    out.append(["destination": d.path, "chunks_checked": v.chunksChecked, "bad": v.chunksBad, "missing": v.chunksMissing, "sample_file": v.sampleFile as Any, "sample_ok": v.sampleOK as Any])
                    let ok = v.chunksBad.isEmpty && v.chunksMissing.isEmpty && v.sampleOK != false
                    if !js { print("\(d.path): \(v.chunksChecked) chunks checked, \(v.chunksBad.count) bad, \(v.chunksMissing.count) missing" + (v.sampleFile.map { "; restored \($0) \(v.sampleOK == true ? "OK" : "FAILED")" } ?? "; no snapshot yet")) }
                    if !ok { worst = 2 } else if v.chunksChecked == 0 { worst = max(worst, 1) }
                } catch { if !js { fputs("\(d.path): \(error.localizedDescription)\n", stderr) }; worst = 2 }
            }
            Config.lastVerify = Date()
            if js { print(json(["results": out])) }
            return worst

        case "prune":
            guard let k = KeyStore.load() else { fputs("no key on this Mac\n", stderr); return 2 }
            let keep = Int(value("--keep", args) ?? "") ?? Config.keepSnapshots
            var out: [[String: Any]] = []
            for d in Config.destinations {
                do {
                    let p = try Prune.run(destination: d, key: k, keep: keep)
                    out.append(["destination": d.path, "snapshots_removed": p.snapshotsRemoved, "chunks_removed": p.chunksRemoved, "bytes_freed": p.bytesFreed, "chunks_kept": p.chunksKept, "bytes_kept": p.bytesKept])
                    if !js { print("\(d.path): removed \(p.snapshotsRemoved) snapshots and \(p.chunksRemoved) chunks (\(ByteCountFormatter.string(fromByteCount: p.bytesFreed, countStyle: .file))); keeping \(ByteCountFormatter.string(fromByteCount: p.bytesKept, countStyle: .file))") }
                } catch { fputs("\(d.path): \(error.localizedDescription)\n", stderr); return 2 }
            }
            if js { print(json(["results": out])) }
            return 0

        case "status":
            let k = KeyStore.load()
            let iso = ISO8601DateFormatter()
            if js { print(json(["version": version, "key": k?.fingerprint as Any, "folders": Config.sources.map(\.path), "destinations": Config.destinations.map(\.path),
                                "last_backup": Config.lastBackup.map { iso.string(from: $0) } as Any, "last_verify": Config.lastVerify.map { iso.string(from: $0) } as Any])) }
            else {
                print("""
                Stash for Mac \(version)
                key:           \(k.map { $0.fingerprint } ?? "none (stashmac key new)")
                folders:       \(Config.sources.isEmpty ? "none (stashmac add <folder>)" : Config.sources.map(\.path).joined(separator: ", "))
                destinations:  \(Config.destinations.isEmpty ? "none (stashmac dest <folder>)" : Config.destinations.map(\.path).joined(separator: ", "))
                last backup:   \(Config.lastBackup.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "never")
                last verify:   \(Config.lastVerify.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "never")
                keep:          \(Config.keepSnapshots) snapshots
                at destination:\(k == nil ? " ?" : Config.destinations.map { " " + ByteCountFormatter.string(fromByteCount: Prune.size(destination: $0, key: k!), countStyle: .file) }.joined(separator: ","))
                """)
            }
            return k == nil || Config.sources.isEmpty || Config.destinations.isEmpty ? 1 : 0

        case "screenshots":
            guard let dir = pos.first else { fputs("screenshots needs a directory\n", stderr); return 64 }
            do {
                let out = URL(fileURLWithPath: dir)
                let files = try MainActor.assumeIsolated { try Screenshots.render(to: out) }
                var lines = files.map { "wrote \($0.path)" }
                if flag("--announce", args) { lines.append("announcement kit: \(try Screenshots.announce(from: out).path)") }
                print(lines.joined(separator: "\n")); return 0
            } catch { fputs("\(error.localizedDescription)\n", stderr); return 2 }

        case "selftest":
            if flag("--list", args) { TestKit.list(); return 0 }
            let results = MainActor.assumeIsolated { TestKit.run(filter: value("--filter", args)) }
            return TestKit.report(results, json: js)

        default:
            fputs("unknown command: \(cmd)\n\n\(usage)\n", stderr); return 64
        }
    }
}
