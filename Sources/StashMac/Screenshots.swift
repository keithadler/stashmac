//  Stash for Mac — MIT licensed. See LICENSE.
//
//  `stashmac screenshots <dir>`: the main window with a demo stash, the settings, and a recovery
//  card, in dark and light, for the README. Demo key and folders live in a temporary directory;
//  nothing touches the Keychain or real settings.

import AppKit
import SwiftUI

enum Screenshots {
    @MainActor
    static func render(to dir: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.activate(ignoringOtherApps: true)
        if app.applicationIconImage.size.width == 0 || Bundle.main.bundleIdentifier == nil, let icon = NSImage(contentsOfFile: FileManager.default.currentDirectoryPath + "/AppIcon.icns") {
            app.applicationIconImage = icon
        }

        // Demo world in a temp directory: a key, two folders with a few files, one destination with a backup.
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("stashmac-shots-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        KeyStore.fileDirectory = tmp
        Manifest.hostOverride = "Sam's MacBook"
        defer { Manifest.hostOverride = nil }
        Config.defaults = UserDefaults(suiteName: "com.keithadler.stashmac.screenshots")!
        defer { Config.defaults.removePersistentDomain(forName: "com.keithadler.stashmac.screenshots") }
        let key = MasterKey(entropy: Data((0..<32).map { UInt8(($0 * 37 + 11) & 0xff) }))
        KeyStore.save(key)
        let docs = tmp.appendingPathComponent("Documents"), desk = tmp.appendingPathComponent("Desktop"), drive = tmp.appendingPathComponent("iCloud Drive")
        for d in [docs, desk, drive] { try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true) }
        for (n, size) in [("Lease Woodland Ave.pdf", 240_000), ("Taxes 2025/return.pdf", 1_200_000), ("Family/recipes.md", 9_000), ("Photos/kids-2026.heic", 3_100_000)] {
            let u = docs.appendingPathComponent(n)
            try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: UInt8(n.count), count: size).write(to: u)
        }
        try Data(repeating: 1, count: 50_000).write(to: desk.appendingPathComponent("Notes.txt"))
        Config.sources = [docs, desk]; Config.destinations = [drive]
        _ = try Backup.run(sources: [docs, desk], destination: drive, key: key)
        try Data(repeating: 9, count: 1_600_000).write(to: docs.appendingPathComponent("Taxes 2025/return.pdf"))
        _ = try Backup.run(sources: [docs, desk], destination: drive, key: key)
        try Data(repeating: 4, count: 70_000).write(to: desk.appendingPathComponent("Notes.txt"))
        _ = try Backup.run(sources: [docs, desk], destination: drive, key: key)
        Config.lastBackup = Date().addingTimeInterval(-3600); Config.lastVerify = Date().addingTimeInterval(-2 * 86400)
        let model = StashModel.shared
        model.key = key; model.sources = Config.sources; model.destinations = Config.destinations; model.lastBackup = Config.lastBackup
        model.snapshots = Restore.snapshots(destination: drive, key: key)
        model.lastMessage = String(localized: "iCloud Drive: 5 files, 4.4 MB new")

        var written: [URL] = []
        for (suffix, appearance) in [("", NSAppearance.Name.darkAqua), ("-light", .aqua)] {
            app.appearance = NSAppearance(named: appearance)
            let main = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 520), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            main.title = "Stash for Mac"; main.contentView = NSHostingView(rootView: MainView()); main.center(); main.makeKeyAndOrderFront(nil)
            settle(); written.append(try capture(main, to: dir.appendingPathComponent("main\(suffix).png"))); main.orderOut(nil)

            let card = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 420), styleMask: [.titled], backing: .buffered, defer: false)
            card.title = String(localized: "Your recovery card"); card.contentView = NSHostingView(rootView: RecoveryCardView(key: key)); card.center(); card.makeKeyAndOrderFront(nil)
            settle(); written.append(try capture(card, to: dir.appendingPathComponent("card\(suffix).png"))); card.orderOut(nil)

            let snaps = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 480), styleMask: [.titled], backing: .buffered, defer: false)
            snaps.title = String(localized: "Snapshots"); snaps.contentView = NSHostingView(rootView: SnapshotsView()); snaps.center(); snaps.makeKeyAndOrderFront(nil)
            settle(); written.append(try capture(snaps, to: dir.appendingPathComponent("snapshots\(suffix).png"))); snaps.orderOut(nil)

            let settings = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 400), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            settings.title = String(localized: "Settings"); settings.contentView = NSHostingView(rootView: SettingsView()); settings.center(); settings.makeKeyAndOrderFront(nil)
            settle(); written.append(try capture(settings, to: dir.appendingPathComponent("settings\(suffix).png"))); settings.orderOut(nil)
        }
        if let pdf = QR.recoveryCard(key, stashName: "Documents and Desktop") {
            let url = dir.appendingPathComponent("recovery-card.pdf"); try pdf.write(to: url); written.append(url)
        }
        written += Promo.render(into: dir, icon: app.applicationIconImage)
        app.setActivationPolicy(.accessory)
        return written
    }

    /// Copies screenshots, promo cards, the announcement page and post drafts to ~/Desktop/Stash for Mac announcement.
    static func announce(from dir: URL) throws -> URL {
        let fm = FileManager.default
        let desk = fm.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/Stash for Mac announcement", isDirectory: true)
        try? fm.removeItem(at: desk)
        try fm.createDirectory(at: desk.appendingPathComponent("screenshots"), withIntermediateDirectories: true)
        try fm.createDirectory(at: desk.appendingPathComponent("promo"), withIntermediateDirectories: true)
        for f in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where f.hasSuffix(".png") || f.hasSuffix(".pdf") {
            try fm.copyItem(at: dir.appendingPathComponent(f), to: desk.appendingPathComponent("screenshots/\(f)"))
        }
        for f in (try? fm.contentsOfDirectory(atPath: dir.appendingPathComponent("promo").path)) ?? [] where f.hasSuffix(".png") {
            try fm.copyItem(at: dir.appendingPathComponent("promo/\(f)"), to: desk.appendingPathComponent("promo/\(f)"))
        }
        let docs = dir.deletingLastPathComponent(), repo = docs.deletingLastPathComponent()
        if let icon = NSImage(contentsOf: repo.appendingPathComponent("icon/StashMac.iconset/icon_256x256.png")), let tiff = icon.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) { try png.write(to: desk.appendingPathComponent("icon.png")) }
        if var html = try? String(contentsOf: docs.appendingPathComponent("announcement.html"), encoding: .utf8) {
            html = html.replacingOccurrences(of: "../icon/StashMac.iconset/icon_256x256.png", with: "icon.png")
            try html.write(to: desk.appendingPathComponent("announcement.html"), atomically: true, encoding: .utf8)
        }
        if fm.fileExists(atPath: docs.appendingPathComponent("post.txt").path) { try fm.copyItem(at: docs.appendingPathComponent("post.txt"), to: desk.appendingPathComponent("post.txt")) }
        return desk
    }

    @MainActor private static func settle(_ s: TimeInterval = 0.6) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

    private typealias WindowImageFn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
    private static let windowImage: WindowImageFn? = {
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return nil }
        return unsafeBitCast(sym, to: WindowImageFn.self)
    }()

    @MainActor
    private static func capture(_ window: NSWindow, to url: URL) throws -> URL {
        window.makeKeyAndOrderFront(nil); settle(0.3)
        let opts = CGWindowListOption.optionIncludingWindow.rawValue
        let imgOpts = CGWindowImageOption.boundsIgnoreFraming.rawValue | CGWindowImageOption.bestResolution.rawValue
        var cg = windowImage?(.null, opts, CGWindowID(window.windowNumber), imgOpts)?.takeRetainedValue()
        if cg == nil || cg!.width < 10, let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep); cg = rep.cgImage
        }
        guard let image = cg, let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw NSError(domain: "stashmac", code: 1, userInfo: [NSLocalizedDescriptionKey: "could not capture \(window.title)"])
        }
        try png.write(to: url, options: .atomic)
        return url
    }
}
