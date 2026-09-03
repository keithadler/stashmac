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
            .defaultSize(width: 760, height: 540)
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

struct MainView: View {
    @State private var key: MasterKey? = KeyStore.load()
    @State private var showCard = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading) {
                    Text("Stash for Mac").font(.title).bold()
                    Text("Encrypted backup of the folders that matter, into storage you already have.").foregroundStyle(.secondary)
                }
            }
            Divider()
            if let key {
                Label(String(format: String(localized: "This Mac has a stash key (%@)."), key.fingerprint), systemImage: "key.fill")
                HStack {
                    Button("Show Recovery Card…") { showCard = true }
                    Button("Forget Key on This Mac", role: .destructive) { KeyStore.delete(); self.key = nil }
                }
                Text("Folders, destinations and schedules come next. This shell proves the key, the card, and the encryption.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text("No stash yet.").font(.headline)
                Text("The first step is a key. Stash for Mac makes it for you; you keep it as 24 words and a QR code on a card. Nothing else can read the backup, and the app never keeps a copy of the card.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Make a Key") { let k = MasterKey.random(); KeyStore.save(k); key = k; showCard = true }.keyboardShortcut(.defaultAction)
                    Button("I Have a Recovery Card…") { showCard = false; importCard() }
                }
            }
            Spacer()
        }
        .padding(24)
        .sheet(isPresented: $showCard) { if let key { RecoveryCardView(key: key) } }
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
        do { let k = try MasterKey(words: field.stringValue); KeyStore.save(k); key = k }
        catch { let e = NSAlert(error: error); e.runModal() }
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
