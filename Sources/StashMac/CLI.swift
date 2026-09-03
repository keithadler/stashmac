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
      stashmac seal <in> <out>          encrypt one file as a chunk (proof of the format)
      stashmac open <in> <out>          decrypt one chunk
      stashmac status [--json]
      stashmac selftest [--filter S] [--list] [--json]
      stashmac help | version

    Folders, destinations, schedules and restore are the next milestones. Everything above is
    the part that has to be right first: the key, its recovery, and the chunk format.
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
        let args = Array(CommandLine.arguments.dropFirst())
        guard let cmd = args.first, !cmd.hasPrefix("-psn") else { return }
        exit(run(cmd, Array(args.dropFirst())))
    }

    static func flag(_ n: String, _ a: [String]) -> Bool { a.contains(n) }
    static func value(_ n: String, _ a: [String]) -> String? { guard let i = a.firstIndex(of: n), i + 1 < a.count else { return nil }; return a[i + 1] }
    static func positional(_ a: [String]) -> [String] {
        var out: [String] = []; var skip = false
        for x in a { if skip { skip = false; continue }; if ["--filter", "--qr"].contains(x) { skip = true; continue }; if x.hasPrefix("--") { continue }; out.append(x) }
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

        case "status":
            let k = KeyStore.load()
            if js { print(json(["version": version, "key": k?.fingerprint as Any, "folders": [], "destinations": []])) }
            else { print("Stash for Mac \(version)\nkey:           \(k.map { $0.fingerprint } ?? "none (stashmac key new)")\nfolders:       none yet\ndestinations:  none yet") }
            return k == nil ? 1 : 0

        case "selftest":
            if flag("--list", args) { TestKit.list(); return 0 }
            let results = MainActor.assumeIsolated { TestKit.run(filter: value("--filter", args)) }
            return TestKit.report(results, json: js)

        default:
            fputs("unknown command: \(cmd)\n\n\(usage)\n", stderr); return 64
        }
    }
}
