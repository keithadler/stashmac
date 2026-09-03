//  Stash for Mac — MIT licensed. See LICENSE.
//
//  Announcement cards, 1600×900 at 2×, rendered by `stashmac screenshots <dir>` into <dir>/promo.
//  Concrete view types on purpose; opaque helpers shared across cards have crashed off-screen
//  rendering before.

import SwiftUI
import AppKit

enum Promo {
    static let size = CGSize(width: 1600, height: 900)
    static var green: LinearGradient {
        LinearGradient(colors: [Color(red: 0.06, green: 0.36, blue: 0.27), Color(red: 0.12, green: 0.52, blue: 0.38), Color(red: 0.22, green: 0.66, blue: 0.47)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static var night: LinearGradient {
        LinearGradient(colors: [Color(red: 0.07, green: 0.09, blue: 0.10), Color(red: 0.11, green: 0.18, blue: 0.16)], startPoint: .top, endPoint: .bottom)
    }

    struct Shot: View {
        let image: NSImage?; let width: CGFloat
        var body: some View {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(width: width)
                    .clipShape(RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.white.opacity(0.25)))
                    .shadow(color: .black.opacity(0.4), radius: 30, y: 16)
            } else { Color.clear.frame(width: width, height: 10) }
        }
    }
    struct Bullet: View {
        let text: String; var symbol = "checkmark.circle.fill"
        var body: some View { HStack(spacing: 12) { Image(systemName: symbol).font(.system(size: 26)).foregroundStyle(.white); Text(text).font(.system(size: 26)).foregroundStyle(.white) } }
    }

    struct Hero: View {
        let icon: NSImage; let main: NSImage?
        var body: some View {
            ZStack {
                green
                HStack(spacing: 40) {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack(spacing: 18) { Image(nsImage: icon).resizable().frame(width: 110, height: 110); Text("Stash for Mac").font(.system(size: 64, weight: .bold)).foregroundStyle(.white) }
                        Text("Encrypted backup into the\nfree storage you already have.").font(.system(size: 36, weight: .medium)).foregroundStyle(.white.opacity(0.95)).lineSpacing(4)
                        VStack(alignment: .leading, spacing: 12) {
                            Bullet(text: "Google Drive, OneDrive, iCloud, Dropbox, any disk")
                            Bullet(text: "The provider only ever sees ciphertext")
                            Bullet(text: "Your key: 24 words and a QR code on a card")
                            Bullet(text: "Free and open source · MIT · no account")
                        }.padding(.top, 6)
                    }.frame(width: 720, alignment: .leading)
                    Shot(image: main, width: 700)
                }.padding(.horizontal, 70)
            }
        }
    }

    struct CardCard: View {
        let card: NSImage?
        var body: some View {
            ZStack {
                night
                HStack(spacing: 50) {
                    Shot(image: card, width: 760)
                    VStack(alignment: .leading, spacing: 20) {
                        Text("No password.\nA card.").font(.system(size: 58, weight: .bold)).foregroundStyle(.white).lineSpacing(2)
                        Text("Stash for Mac makes a random key and shows it once as 24 words and a QR code. Print it, put it in a drawer. A typo is caught by a checksum; a photo of the card restores everything on a new Mac.")
                            .font(.system(size: 24)).foregroundStyle(.white.opacity(0.9)).lineSpacing(4)
                        Text("The app never keeps a copy. Lose the card and the backup is unreadable by anyone, which is the point.")
                            .font(.system(size: 20)).foregroundStyle(.white.opacity(0.7)).lineSpacing(3)
                    }.frame(width: 640, alignment: .leading)
                }.padding(.horizontal, 60)
            }
        }
    }

    struct Honest: View {
        var body: some View {
            ZStack {
                LinearGradient(colors: [Color(red: 0.10, green: 0.14, blue: 0.13), Color(red: 0.15, green: 0.26, blue: 0.22)], startPoint: .topLeading, endPoint: .bottomTrailing)
                HStack(spacing: 60) {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("A backup you\ncan check.").font(.system(size: 58, weight: .bold)).foregroundStyle(.white).lineSpacing(2)
                        Text("Most people find out their backup was broken the day they need it. Stash for Mac restores a random file every week to prove the whole path still works, and says so in plain words.")
                            .font(.system(size: 24)).foregroundStyle(.white.opacity(0.9)).lineSpacing(4)
                    }.frame(width: 640, alignment: .leading)
                    VStack(alignment: .leading, spacing: 22) {
                        Row(symbol: "lock.shield.fill", title: "Encrypted on your Mac", detail: "ChaChaPoly chunks with keyed names. Sizes and timing are all the provider learns.")
                        Row(symbol: "arrow.triangle.2.circlepath", title: "Only what changed", detail: "Identical content is stored once. A second backup of an unchanged folder uploads nothing.")
                        Row(symbol: "icloud.slash", title: "Never downloads behind your back", detail: "Files that only exist in the cloud are listed, not fetched.")
                        Row(symbol: "trash.slash", title: "Old snapshots age out", detail: "Keep the last 30; pieces nobody references are deleted, so the free tier stays free.")
                    }.frame(width: 720, alignment: .leading)
                }.padding(.horizontal, 70)
            }
        }
    }
    struct Row: View {
        let symbol: String, title: String, detail: String
        var body: some View {
            HStack(alignment: .top, spacing: 18) {
                Image(systemName: symbol).font(.system(size: 30)).foregroundStyle(Color(red: 0.98, green: 0.80, blue: 0.25)).frame(width: 44)
                VStack(alignment: .leading, spacing: 4) { Text(title).font(.system(size: 27, weight: .semibold)).foregroundStyle(.white); Text(detail).font(.system(size: 20)).foregroundStyle(.white.opacity(0.85)).lineSpacing(2) }
            }
        }
    }

    struct CLIcard: View {
        var body: some View {
            ZStack {
                night
                HStack(spacing: 50) {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Also a real\ncommand line.").font(.system(size: 58, weight: .bold)).foregroundStyle(.white)
                        Text("Same binary as the app. --json everywhere, exit codes, scriptable restores.").font(.system(size: 24)).foregroundStyle(.white.opacity(0.9)).lineSpacing(4)
                        Text("Swift, CryptoKit, no dependencies, no Xcode project. Universal binary, macOS 14+.").font(.system(size: 20)).foregroundStyle(.white.opacity(0.7))
                    }.frame(width: 600, alignment: .leading)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 8) {
                            Circle().fill(Color(red: 1, green: 0.37, blue: 0.34)).frame(width: 14, height: 14)
                            Circle().fill(Color(red: 1, green: 0.74, blue: 0.18)).frame(width: 14, height: 14)
                            Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.26)).frame(width: 14, height: 14)
                            Spacer()
                        }.padding(16)
                        Text("""
                        $ stashmac add ~/Documents
                        $ stashmac dest "~/Library/CloudStorage/GoogleDrive/My Drive"
                        $ stashmac backup
                        My Drive: 2,314 files, 6.1 GB; uploaded 41 chunks (160 MB), reused 1,559

                        $ stashmac verify
                        My Drive: 1,600 chunks checked, 0 bad, 0 missing; restored Taxes/return.pdf OK

                        $ stashmac restore latest ~/Desktop/Restored --only Photos/2026
                        restored 312 files (2.9 GB) into /Users/sam/Desktop/Restored
                        """)
                        .font(.system(size: 19, design: .monospaced)).foregroundStyle(Color(red: 0.85, green: 0.93, blue: 0.85)).padding(.horizontal, 22).padding(.bottom, 22)
                    }
                    .frame(width: 800, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(red: 0.05, green: 0.06, blue: 0.09)))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.15))).shadow(color: .black.opacity(0.5), radius: 30, y: 16)
                }.padding(.horizontal, 70)
            }
        }
    }

    @MainActor
    static func render(into dir: URL, icon: NSImage) -> [URL] {
        let out = dir.appendingPathComponent("promo")
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        func img(_ n: String) -> NSImage? { NSImage(contentsOf: dir.appendingPathComponent("\(n).png")) }
        let cards: [(String, AnyView)] = [
            ("1-hero", AnyView(Hero(icon: icon, main: img("main")))),
            ("2-card", AnyView(CardCard(card: img("card")))),
            ("3-honest", AnyView(Honest())),
            ("4-cli", AnyView(CLIcard())),
        ]
        var written: [URL] = []
        for (name, view) in cards {
            if let png = snapshot(view, size: size) { let u = out.appendingPathComponent("\(name).png"); try? png.write(to: u); written.append(u) }
        }
        return written
    }

    @MainActor
    static func snapshot(_ view: AnyView, size: CGSize) -> Data? {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        let win = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: .darkAqua); win.contentView = host
        win.setFrameOrigin(NSPoint(x: -10_000, y: -10_000)); win.orderFront(nil)
        for _ in 0..<6 { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep); win.orderOut(nil)
        return rep.representation(using: .png, properties: [:])
    }
}
