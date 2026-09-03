//  Stash for Mac — encrypted backup of the folders that matter, into the free storage you already have.
//  MIT licensed. See LICENSE.
//
//  App entry point. A normal windowed app (this one has a Dock icon: backups deserve a window).
//  The init hook hands `stashmac <command>` invocations to CLI.swift, which exits before any UI.

import SwiftUI

@main
struct StashMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    init() { CLI.runIfRequested() }

    var body: some Scene {
        WindowGroup("Stash for Mac", id: "main") { MainView() }
            .defaultSize(width: 860, height: 520)
            .windowResizability(.contentMinSize)
            .commands {
                CommandGroup(replacing: .newItem) { }
                CommandGroup(after: .appInfo) { Button("Check for Updates…") { Updates.checkAndPresent() } }
                CommandGroup(replacing: .help) {
                    Button("Stash for Mac Help") { NSWorkspace.shared.open(URL(string: "https://github.com/keithadler/stashmac#readme")!) }
                }
            }
        Settings { SettingsView() }
    }
}

@MainActor
final class StashModel: ObservableObject {
    @Published var key: MasterKey? = KeyStore.load()
    @Published var sources: [URL] = Config.sources
    @Published var destinations: [URL] = Config.destinations
    @Published var snapshots: [SnapshotInfo] = []
    @Published var busy: String?
    @Published var progress: Double = 0
    @Published var lastMessage = ""
    @Published var lastBackup = Config.lastBackup

    func refreshSnapshots() {
        guard let key, let d = destinations.first else { snapshots = []; return }
        Task.detached { [key, d] in
            let s = Restore.snapshots(destination: d, key: key)
            await MainActor.run { self.snapshots = s }
        }
    }

    func addSource(_ u: URL) { if !sources.contains(u) { sources.append(u); Config.sources = sources } }
    func removeSource(_ u: URL) { sources.removeAll { $0 == u }; Config.sources = sources }
    func addDestination(_ u: URL) { if !destinations.contains(u) { destinations.append(u); Config.destinations = destinations }; refreshSnapshots() }
    func removeDestination(_ u: URL) { destinations.removeAll { $0 == u }; Config.destinations = destinations; refreshSnapshots() }

    func backUp() {
        guard let key, busy == nil else { return }
        let sources = self.sources, dests = self.destinations
        busy = String(localized: "Backing up…"); progress = 0
        Task.detached { [key] in
            var lines: [String] = []
            for d in dests {
                do {
                    let r = try Backup.run(sources: sources, destination: d, key: key) { done, total, _ in
                        Task { @MainActor in self.progress = total > 0 ? Double(done) / Double(total) : 1 }
                    }
                    lines.append(String(format: String(localized: "%@: %lld files, %@ new"), d.lastPathComponent, r.files, ByteCountFormatter.string(fromByteCount: r.newBytes, countStyle: .file))
                                 + (r.skippedPlaceholders > 0 ? String(format: String(localized: ", %lld cloud placeholders listed"), r.skippedPlaceholders) : ""))
                } catch { lines.append("\(d.lastPathComponent): \(error.localizedDescription)") }
            }
            let summary = lines.joined(separator: "\n")
            await MainActor.run {
                Config.lastBackup = Date(); self.lastBackup = Config.lastBackup
                self.lastMessage = summary; self.busy = nil; self.refreshSnapshots()
            }
        }
    }

    func verify() {
        guard let key, let d = destinations.first, busy == nil else { return }
        busy = String(localized: "Verifying…"); progress = 0
        Task.detached { [key] in
            let msg: String
            do {
                let v = try Restore.verify(destination: d, key: key) { done, total in Task { @MainActor in self.progress = Double(done) / Double(max(total, 1)) } }
                msg = String(format: String(localized: "%lld chunks checked, %lld bad, %lld missing. Sample restore %@."), v.chunksChecked, v.chunksBad.count, v.chunksMissing.count,
                             v.sampleOK == true ? String(localized: "OK") : String(localized: "FAILED"))
                Config.lastVerify = Date()
            } catch { msg = error.localizedDescription }
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
    @StateObject private var model = StashModel()
    @State private var showCard = false

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

struct RecoveryCardView: View {
    let key: MasterKey
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            Text("Your recovery card").font(.title2).bold()
            Text("Print it or write it down, then put it somewhere safe. Stash for Mac does not keep a copy.").foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(alignment: .top, spacing: 24) {
                Text(Mnemonic.card(key.words)).font(.system(.body, design: .monospaced)).textSelection(.enabled)
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
        .padding(24).frame(width: 640)
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
    @AppStorage("autoUpdateCheck") private var autoUpdate = false
    var body: some View {
        Form {
            Section("Updates") {
                Toggle("Check for a new version once a day", isOn: $autoUpdate)
                Text("One request to GitHub, no identifiers. A new version is offered as a download; nothing installs by itself.").font(.caption).foregroundStyle(.secondary)
            }
            Section { Text("Folders, destinations and schedules arrive in the next milestones.").font(.caption).foregroundStyle(.secondary) }
        }
        .formStyle(.grouped).frame(width: 480, height: 220)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Updates.scheduleBackgroundChecks()
    }
}
