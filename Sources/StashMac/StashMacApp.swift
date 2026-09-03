//  Stash for Mac — encrypted backup of the folders that matter, into the free storage you already have.
//  MIT licensed. See LICENSE.
//
//  App entry point. A normal windowed app (this one has a Dock icon: backups deserve a window).
//  The init hook hands `stashmac <command>` invocations to CLI.swift, which exits before any UI.

import SwiftUI
import ServiceManagement

@main
struct StashMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("menuBar") private var menuBar = true
    init() { CLI.runIfRequested() }

    var body: some Scene {
        WindowGroup("Stash for Mac", id: "main") { MainView() }
            .defaultSize(width: 860, height: 520)
            .windowResizability(.contentMinSize)
            .commands {
                CommandGroup(replacing: .newItem) { }
                CommandGroup(after: .appInfo) { Button("Check for Updates…") { Updates.checkAndPresent() } }
                CommandGroup(replacing: .help) {
                    Button("Stash for Mac Help") { Help.open() }.keyboardShortcut("?")
                    Button("Report a Problem…") { NSWorkspace.shared.open(URL(string: "https://github.com/keithadler/stashmac/issues")!) }
                }
            }
        Settings { SettingsView() }

        MenuBarExtra(isInserted: $menuBar) { MenuBarContent() } label: { MenuBarLabel() }
    }
}

struct MenuBarLabel: View {
    @ObservedObject private var model = StashModel.shared
    var body: some View {
        Image(systemName: model.busy != nil ? "arrow.triangle.2.circlepath" : (model.lastBackup == nil ? "externaldrive.badge.questionmark" : "externaldrive.badge.checkmark"))
    }
}

struct MenuBarContent: View {
    @ObservedObject private var model = StashModel.shared
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        if let busy = model.busy { Text("\(busy) \(Int(model.progress * 100))%") }
        else if let last = model.lastBackup { Text(String(format: String(localized: "Last backup %@"), last.formatted(date: .abbreviated, time: .shortened))) }
        else { Text("No backup yet") }
        if let next = Scheduler.shared.nextRun { Text(String(format: String(localized: "Next %@"), next.formatted(date: .omitted, time: .shortened))) }
        Divider()
        Button("Back Up Now") { model.backUp() }.disabled(model.busy != nil || model.sources.isEmpty || model.availableDestinations.isEmpty)
        Button("Verify Now") { model.verify() }.disabled(model.busy != nil || model.availableDestinations.isEmpty)
        Divider()
        Button("Open Stash for Mac") { NSApp.activate(); openWindow(id: "main") }
        Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

@MainActor
final class StashModel: ObservableObject {
    static let shared = StashModel()
    @Published var key: MasterKey? = KeyStore.load()
    @Published var sources: [URL] = Config.sources
    @Published var destinations: [URL] = Config.destinations
    @Published var snapshots: [SnapshotInfo] = []
    @Published var uniqueSizes: [String: Int64] = [:]
    @Published var stashSize: Int64 = 0
    @Published var busy: String?
    @Published var progress: Double = 0
    @Published var lastMessage = ""
    @Published var lastBackup = Config.lastBackup

    func refreshSnapshots() {
        guard let key, let d = availableDestinations.first else { snapshots = []; uniqueSizes = [:]; stashSize = 0; return }
        Task.detached { [key, d] in
            let s = Restore.snapshots(destination: d, key: key)
            let u = Prune.uniqueSizes(destination: d, key: key)
            let total = Prune.size(destination: d, key: key)
            await MainActor.run { self.snapshots = s; self.uniqueSizes = u; self.stashSize = total }
        }
    }

    func deleteSnapshot(_ snap: SnapshotInfo) {
        guard let key, let d = availableDestinations.first, busy == nil else { return }
        busy = String(localized: "Deleting snapshot…"); progress = 0
        Task.detached { [key] in
            let msg: String
            do {
                let r = try Prune.delete(snapshot: snap.fileName, destination: d, key: key)
                msg = String(format: String(localized: "Deleted the snapshot and reclaimed %@."), ByteCountFormatter.string(fromByteCount: r.bytesFreed, countStyle: .file))
            } catch { msg = error.localizedDescription }
            await MainActor.run { self.lastMessage = msg; self.busy = nil; self.refreshSnapshots() }
        }
    }

    func pruneNow() {
        guard let key, busy == nil else { return }
        let dests = availableDestinations
        busy = String(localized: "Tidying snapshots…"); progress = 0
        Task.detached { [key] in
            var lines: [String] = []
            for d in dests {
                do { let r = try Prune.run(destination: d, key: key); lines.append(String(format: String(localized: "%@: removed %lld snapshots, reclaimed %@"), d.lastPathComponent, r.snapshotsRemoved, ByteCountFormatter.string(fromByteCount: r.bytesFreed, countStyle: .file))) }
                catch { lines.append("\(d.lastPathComponent): \(error.localizedDescription)") }
            }
            let summary = lines.joined(separator: "\n")
            await MainActor.run { self.lastMessage = summary; self.busy = nil; self.refreshSnapshots() }
        }
    }

    func addSource(_ u: URL) { if !sources.contains(u) { sources.append(u); Config.sources = sources } }
    func removeSource(_ u: URL) { sources.removeAll { $0 == u }; Config.sources = sources }
    func addDestination(_ u: URL) { if !destinations.contains(u) { destinations.append(u); Config.destinations = destinations }; refreshSnapshots() }
    func removeDestination(_ u: URL) { destinations.removeAll { $0 == u }; Config.destinations = destinations; refreshSnapshots() }

    /// Destinations that are reachable right now (a NAS or a disk may be unplugged).
    var availableDestinations: [URL] { destinations.filter { Config.isFolder($0) } }

    func backUp(reason: String = "manual") {
        guard let key, busy == nil else { return }
        let sources = self.sources, dests = availableDestinations
        guard !sources.isEmpty, !dests.isEmpty else { lastMessage = String(localized: "No destination is reachable right now."); return }
        busy = String(localized: "Backing up…"); progress = 0
        Task.detached { [key] in
            var lines: [String] = []
            var failures: [String] = []
            for d in dests {
                do {
                    let r = try Backup.run(sources: sources, destination: d, key: key) { done, total, _ in
                        Task { @MainActor in self.progress = total > 0 ? Double(done) / Double(total) : 1 }
                    }
                    let pruned = try? Prune.run(destination: d, key: key)
                    lines.append(String(format: String(localized: "%@: %lld files, %@ new"), d.lastPathComponent, r.files, ByteCountFormatter.string(fromByteCount: r.newBytes, countStyle: .file))
                                 + (r.skippedPlaceholders > 0 ? String(format: String(localized: ", %lld cloud placeholders listed"), r.skippedPlaceholders) : "")
                                 + ((pruned?.bytesFreed ?? 0) > 0 ? String(format: String(localized: ", %@ reclaimed"), ByteCountFormatter.string(fromByteCount: pruned!.bytesFreed, countStyle: .file)) : ""))
                    if !r.unreadable.isEmpty { failures.append(String(format: String(localized: "%lld files could not be read in %@"), r.unreadable.count, d.lastPathComponent)) }
                } catch { lines.append("\(d.lastPathComponent): \(error.localizedDescription)"); failures.append("\(d.lastPathComponent): \(error.localizedDescription)") }
            }
            let summary = lines.joined(separator: "\n")
            if !failures.isEmpty && reason == "schedule" { Notify.post(String(localized: "Backup needs attention"), failures.joined(separator: "\n")) }
            await MainActor.run {
                Config.lastBackup = Date(); self.lastBackup = Config.lastBackup
                self.lastMessage = summary; self.busy = nil; self.refreshSnapshots()
            }
        }
    }

    func verify(reason: String = "manual") {
        guard let key, let d = availableDestinations.first, busy == nil else { return }
        busy = String(localized: "Verifying…"); progress = 0
        Task.detached { [key] in
            let msg: String
            var ok = true
            do {
                let v = try Restore.verify(destination: d, key: key) { done, total in Task { @MainActor in self.progress = Double(done) / Double(max(total, 1)) } }
                ok = v.chunksBad.isEmpty && v.chunksMissing.isEmpty && v.sampleOK != false
                msg = String(format: String(localized: "%lld chunks checked, %lld bad, %lld missing. Sample restore %@."), v.chunksChecked, v.chunksBad.count, v.chunksMissing.count,
                             v.sampleOK == true ? String(localized: "OK") : String(localized: "FAILED"))
                Config.lastVerify = Date()
            } catch { msg = error.localizedDescription; ok = false }
            if !ok && reason == "schedule" { Notify.post(String(localized: "Backup check failed"), msg) }
            await MainActor.run { self.lastMessage = msg; self.busy = nil }
        }
    }

    func restore(_ snap: SnapshotInfo, to target: URL) {
        guard let key, let d = destinations.first, busy == nil else { return }
        busy = String(localized: "Restoring…"); progress = 0
        Task.detached { [key] in
            let msg: String
            do {
                let r = try Restore.run(snapshot: snap.fileName, destination: d, key: key, to: target) { done, total in Task { @MainActor in self.progress = Double(done) / Double(max(total, 1)) } }
                msg = String(format: String(localized: "Restored %lld files into %@."), r.restored, target.lastPathComponent) + (r.failed.isEmpty ? "" : "\n" + r.failed.joined(separator: "\n"))
            } catch { msg = error.localizedDescription }
            await MainActor.run { self.lastMessage = msg; self.busy = nil }
        }
    }
}

struct MainView: View {
    @ObservedObject private var model = StashModel.shared
    @State private var showCard = false
    @State private var showSnapshots = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading) {
                    Text("Stash for Mac").font(.title).bold()
                    Text("Encrypted backup of the folders that matter, into storage you already have.").foregroundStyle(.secondary)
                }
                Spacer()
                if let key = model.key {
                    Button { showCard = true } label: { Label(key.fingerprint, systemImage: "key.fill") }.help("Show the recovery card")
                }
            }
            if model.key == nil { keySetup } else { plan }
            Spacer(minLength: 0)
            if let busy = model.busy {
                HStack { ProgressView(value: model.progress); Text(busy).font(.caption).foregroundStyle(.secondary) }
            }
            if !model.lastMessage.isEmpty { Text(model.lastMessage).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
        }
        .padding(24)
        .frame(minWidth: 760, idealWidth: 860, minHeight: 420, idealHeight: 520)
        .sheet(isPresented: $showCard) { if let key = model.key { RecoveryCardView(key: key) } }
        .sheet(isPresented: $showSnapshots) { SnapshotsView() }
        .onAppear { model.refreshSnapshots() }
    }

    private var keySetup: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Step 1 of 3: a key").font(.headline)
            Text("Stash for Mac makes it for you; you keep it as 24 words and a QR code on a card. Nothing else can read the backup, and the app never keeps a copy of the card.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Make a Key") { let k = MasterKey.random(); KeyStore.save(k); model.key = k; showCard = true }.keyboardShortcut(.defaultAction)
                Button("I Have a Recovery Card…") { importCard() }
            }
        }
    }

    private var plan: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Folders to protect").font(.headline)
                list(model.sources, empty: "Nothing yet. Documents and Desktop are the usual first two.", remove: model.removeSource)
                Button("Add Folder…") { pick(message: "Choose a folder to back up.") { model.addSource($0) } }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Where it goes").font(.headline)
                list(model.destinations, empty: "Nothing yet. Your iCloud Drive, Google Drive, OneDrive or Dropbox folder, a disk, or a NAS.", remove: model.removeDestination)
                Button("Add Destination…") { pick(message: "Choose where the encrypted backup goes. A folder your cloud app syncs works best.") { model.addDestination($0) } }
                if model.destinations.count == 1 { Text("Two destinations are safer: an account can be lost.").font(.caption).foregroundStyle(.orange) }
                if model.stashSize > 0, let d = model.availableDestinations.first {
                    Text(String(format: String(localized: "Using %@ at %@"), ByteCountFormatter.string(fromByteCount: model.stashSize, countStyle: .file), d.lastPathComponent)).font(.caption).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Snapshots").font(.headline)
                if model.snapshots.isEmpty { Text("No backup yet.").font(.caption).foregroundStyle(.secondary) }
                ForEach(model.snapshots.prefix(8)) { s in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(s.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.callout)
                            Text(String(format: String(localized: "%lld files, %@, from %@"), s.files, ByteCountFormatter.string(fromByteCount: s.bytes, countStyle: .file), s.host)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Restore…") { pick(message: "Choose where to put the restored files. They go into a folder named after the original.") { model.restore(s, to: $0) } }.font(.caption)
                    }
                }
                HStack {
                    Button("Back Up Now") { model.backUp() }.keyboardShortcut(.defaultAction).disabled(model.sources.isEmpty || model.destinations.isEmpty || model.busy != nil)
                    Button("Verify") { model.verify() }.disabled(model.snapshots.isEmpty || model.busy != nil)
                }
                if let last = model.lastBackup { Text(String(format: String(localized: "Last backup %@"), last.formatted(date: .abbreviated, time: .shortened))).font(.caption).foregroundStyle(.secondary) }
                if !model.snapshots.isEmpty { Button("Manage Snapshots…") { showSnapshots = true }.font(.caption) }
            }
        }
    }

    private func list(_ urls: [URL], empty: LocalizedStringKey, remove: @escaping (URL) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if urls.isEmpty { Text(empty).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            ForEach(urls, id: \.self) { u in
                HStack {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: u.path)).resizable().frame(width: 18, height: 18)
                    Text(u.lastPathComponent).help(u.path)
                    Spacer()
                    Button { remove(u) } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
        }
        .frame(minWidth: 200)
    }

    private func pick(message: String, _ done: @escaping (URL) -> Void) {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true; p.message = message
        if p.runModal() == .OK, let u = p.url { done(u.standardizedFileURL) }
    }

    private func importCard() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Type the 24 words")
        alert.informativeText = String(localized: "In order, separated by spaces. Capitalisation doesn't matter.")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 72))
        field.placeholderString = "abandon ability able …"
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "Use This Key"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do { let k = try MasterKey(words: field.stringValue); KeyStore.save(k); model.key = k; model.refreshSnapshots() }
        catch { NSAlert(error: error).runModal() }
    }
}

/// Every snapshot with what deleting it would free, the stash's size, and the retention policy.
struct SnapshotsView: View {
    @ObservedObject private var model = StashModel.shared
    @AppStorage("retention") private var retention = Retention.Policy.last.rawValue
    @AppStorage("keepSnapshots") private var keepSnapshots = 30
    @Environment(\.dismiss) private var dismiss
    @State private var confirm: SnapshotInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Snapshots").font(.title2).bold()
                Spacer()
                if let d = model.availableDestinations.first {
                    Text(String(format: String(localized: "%lld snapshots · using %@ at %@"), model.snapshots.count, ByteCountFormatter.string(fromByteCount: model.stashSize, countStyle: .file), d.lastPathComponent)).foregroundStyle(.secondary)
                }
            }
            Text("A snapshot is small on its own: unchanged files are stored once and shared. \"Frees\" is what deleting that snapshot alone would give back, the old versions only it still holds.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Table(model.snapshots) {
                TableColumn("When") { s in Text(s.createdAt.formatted(date: .abbreviated, time: .shortened)) }
                TableColumn("Files") { s in Text("\(s.files)") }.width(60)
                TableColumn("Size") { s in Text(ByteCountFormatter.string(fromByteCount: s.bytes, countStyle: .file)) }.width(80)
                TableColumn("Frees") { s in Text(ByteCountFormatter.string(fromByteCount: model.uniqueSizes[s.fileName] ?? 0, countStyle: .file)).foregroundStyle(.secondary) }.width(80)
                TableColumn("From") { s in Text(s.host).foregroundStyle(.secondary) }
                TableColumn("") { s in Button("Delete") { confirm = s }.disabled(model.busy != nil) }.width(70)
            }
            .frame(minHeight: 220)
            Divider()
            HStack(alignment: .firstTextBaseline) {
                Picker("Keep", selection: $retention) { ForEach(Retention.Policy.allCases) { Text($0.label).tag($0.rawValue) } }.frame(width: 300)
                if retention == Retention.Policy.last.rawValue {
                    Stepper(value: $keepSnapshots, in: 1...365) { Text(String(format: String(localized: "newest %lld"), keepSnapshots)) }
                }
            }
            Text(retention == Retention.Policy.thin.rawValue
                 ? "Everything from the last week, one a day for a month, one a week for a year, one a month after that. Runs after each backup."
                 : "Older snapshots and the pieces only they used are deleted after each backup.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Apply Now") { model.pruneNow() }.disabled(model.busy != nil)
                if let busy = model.busy { ProgressView().controlSize(.small); Text(busy).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).frame(width: 720, height: 480)
        .confirmationDialog(confirm.map { String(format: String(localized: "Delete the snapshot from %@?"), $0.createdAt.formatted(date: .abbreviated, time: .shortened)) } ?? "", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }), titleVisibility: .visible) {
            Button("Delete Snapshot", role: .destructive) { if let s = confirm { model.deleteSnapshot(s) }; confirm = nil }
        } message: { Text("Files that exist only in this snapshot are gone for good. Files that also exist in other snapshots are unaffected.") }
    }
}

struct RecoveryCardView: View {
    let key: MasterKey
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            Text("Your recovery card").font(.title2).bold()
            Text("Print it or write it down, then put it somewhere safe. Stash for Mac does not keep a copy.").foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(alignment: .top, spacing: 24) {
                let words = key.words
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                    ForEach(0..<6, id: \.self) { row in
                        GridRow {
                            ForEach(0..<4, id: \.self) { col in
                                let i = row * 4 + col
                                HStack(spacing: 4) {
                                    Text("\(i + 1).").font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary).frame(width: 28, alignment: .trailing)
                                    Text(words[i]).font(.system(.body, design: .monospaced)).bold()
                                }
                            }
                        }
                    }
                }
                .textSelection(.enabled)
                Spacer(minLength: 0)
                if let img = QR.image(key.qrPayload, size: 400) { Image(nsImage: img).resizable().interpolation(.none).frame(width: 180, height: 180) }
            }
            Text(String(format: String(localized: "Key fingerprint %@"), key.fingerprint)).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Save as PDF…") { savePDF() }
                Button("Print…") { print() }
                Spacer()
                Button("I've Kept It Safe") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 720)
    }

    private func savePDF() {
        let p = NSSavePanel(); p.nameFieldStringValue = "Stash for Mac recovery card \(key.fingerprint).pdf"
        if p.runModal() == .OK, let url = p.url, let pdf = QR.recoveryCard(key, stashName: "default") { try? pdf.write(to: url) }
    }

    private func print() {
        guard let pdf = QR.recoveryCard(key, stashName: "default"), let doc = PDFDocumentBox(data: pdf) else { return }
        doc.print()
    }
}

/// Thin PDFKit wrapper so printing the card works without an NSDocument.
import PDFKit
struct PDFDocumentBox {
    let document: PDFDocument
    init?(data: Data) { guard let d = PDFDocument(data: data) else { return nil }; document = d }
    @MainActor func print() {
        guard let op = document.printOperation(for: NSPrintInfo.shared, scalingMode: .pageScaleToFit, autoRotate: true) else { return }
        op.run()
    }
}

struct SettingsView: View {
    @AppStorage("autoUpdateCheck") private var autoUpdate = true
    @AppStorage("schedule") private var schedule = Config.Schedule.daily.rawValue
    @AppStorage("weeklyVerify") private var weeklyVerify = true
    @AppStorage("keepSnapshots") private var keepSnapshots = 30
    @AppStorage("retention") private var retention = Retention.Policy.last.rawValue
    @AppStorage("menuBar") private var menuBar = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    var body: some View {
        Form {
            Section("When to back up") {
                Picker("Back up", selection: $schedule) { ForEach(Config.Schedule.allCases) { Text($0.label).tag($0.rawValue) } }
                Text("Runs quietly in the background when a destination is reachable. Uploads only what changed.").font(.caption).foregroundStyle(.secondary)
                Picker("Keep", selection: $retention) { ForEach(Retention.Policy.allCases) { Text($0.label).tag($0.rawValue) } }
                if retention == Retention.Policy.last.rawValue {
                    Stepper(value: $keepSnapshots, in: 1...365) { Text(String(format: String(localized: "Keep the last %lld snapshots"), keepSnapshots)) }
                }
                Text("Older snapshots and the pieces only they used are deleted after each backup, so the destination stays a sensible size. See every snapshot and what it holds under Manage Snapshots in the main window.").font(.caption).foregroundStyle(.secondary)
                Toggle("Check the backup once a week by restoring a random file", isOn: $weeklyVerify)
                Toggle("Show Stash for Mac in the menu bar", isOn: $menuBar)
                Toggle("Open Stash for Mac when I log in", isOn: $launchAtLogin).onChange(of: launchAtLogin) { _, on in
                    do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                    catch { launchAtLogin = SMAppService.mainApp.status == .enabled }
                }
                Text("Scheduled backups only happen while the app is open, so opening at login is the usual choice.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Updates") {
                Toggle("Check for a new version once a day", isOn: $autoUpdate)
                Text("One request to GitHub, no identifiers. A new version is offered as a download; nothing installs by itself.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped).frame(width: 520, height: 400)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Scheduled backups only run while the app is open: register as a login item once, the
        // first time this version runs (not in test or screenshot runs). Settings turns it off.
        if ProcessInfo.processInfo.environment["STASHMAC_TEST"] == nil, !UserDefaults.standard.bool(forKey: "loginItemOffered") {
            UserDefaults.standard.set(true, forKey: "loginItemOffered")
            try? SMAppService.mainApp.register()
        }
        Updates.scheduleBackgroundChecks()
        Scheduler.shared.start()
        if Config.schedule != .off { Notify.requestPermissionIfNeeded() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !Config.menuBar }
}


/// Help lives inside the bundle (docs/Help.html, Help.es.html by locale); GitHub is the fallback.
enum Help {
    static var pageName: String { (Locale.preferredLanguages.first ?? "en").hasPrefix("es") ? "Help.es" : "Help" }
    static var bundledPage: URL? {
        if let url = Bundle.main.url(forResource: pageName, withExtension: "html") { return url }
        var url = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath()
        while url.path != "/" {
            if url.pathExtension == "app", let u = Bundle(url: url)?.url(forResource: pageName, withExtension: "html") { return u }
            url = url.deletingLastPathComponent()
        }
        return nil
    }
    @MainActor static func open() {
        NSWorkspace.shared.open(bundledPage ?? URL(string: "https://github.com/keithadler/stashmac#readme")!)
    }
}
