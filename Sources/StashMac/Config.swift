//  Stash for Mac — MIT licensed. See LICENSE.
//
//  What to back up and where. Plain paths in UserDefaults; the key is never here.

import Foundation

enum Config {
    nonisolated(unsafe) static var defaults = UserDefaults.standard

    static var sources: [URL] {
        get { (defaults.stringArray(forKey: "sources") ?? []).map { URL(fileURLWithPath: $0, isDirectory: true) } }
        set { defaults.set(newValue.map(\.path), forKey: "sources") }
    }
    static var destinations: [URL] {
        get { (defaults.stringArray(forKey: "destinations") ?? []).map { URL(fileURLWithPath: $0, isDirectory: true) } }
        set { defaults.set(newValue.map(\.path), forKey: "destinations") }
    }
    static var lastBackup: Date? {
        get { let t = defaults.double(forKey: "lastBackup"); return t > 0 ? Date(timeIntervalSince1970: t) : nil }
        set { defaults.set(newValue?.timeIntervalSince1970 ?? 0, forKey: "lastBackup") }
    }
    static var lastVerify: Date? {
        get { let t = defaults.double(forKey: "lastVerify"); return t > 0 ? Date(timeIntervalSince1970: t) : nil }
        set { defaults.set(newValue?.timeIntervalSince1970 ?? 0, forKey: "lastVerify") }
    }

    enum Schedule: String, CaseIterable, Identifiable {
        case off, hourly, daily
        var id: String { rawValue }
        var interval: TimeInterval? { self == .off ? nil : (self == .hourly ? 3600 : 86400) }
        var label: String {
            switch self { case .off: return String(localized: "Only when I click Back Up Now"); case .hourly: return String(localized: "Every hour"); case .daily: return String(localized: "Once a day") }
        }
    }
    static var schedule: Schedule {
        get { Schedule(rawValue: defaults.string(forKey: "schedule") ?? "") ?? .daily }
        set { defaults.set(newValue.rawValue, forKey: "schedule") }
    }
    static var retention: Retention.Policy {
        get { Retention.Policy(rawValue: defaults.string(forKey: "retention") ?? "") ?? .last }
        set { defaults.set(newValue.rawValue, forKey: "retention") }
    }
    static let defaultExcludes = ["*.tmp", "*.part", "*.crdownload", "Cache", "Caches", ".cache", "*.photoslibrary", "*.vmdk", "*.vdi"]
    static var excludePatterns: [String] {
        get { defaults.stringArray(forKey: "excludePatterns") ?? defaultExcludes }
        set { defaults.set(newValue, forKey: "excludePatterns") }
    }
    /// 0 means no cap.
    static var maxFileBytes: Int64 { Int64(defaults.integer(forKey: "maxFileMB")) * 1_048_576 }
    static var keepSnapshots: Int { let v = defaults.integer(forKey: "keepSnapshots"); return v > 0 ? v : 30 }
    static var weeklyVerify: Bool { defaults.object(forKey: "weeklyVerify") as? Bool ?? true }
    static var menuBar: Bool { defaults.object(forKey: "menuBar") as? Bool ?? true }

    /// Why a folder cannot be added as a source or destination, in plain words; nil when it can.
    static func objection(toSource url: URL, sources: [URL], destinations: [URL]) -> String? {
        let p = url.standardizedFileURL.path
        if p == "/" { return String(localized: "The whole disk is too much. Choose the folders that matter.") }
        for d in destinations {
            if isInside(p, d.standardizedFileURL.path) || isInside(d.standardizedFileURL.path, p) { return String(format: String(localized: "%@ overlaps the destination %@. A backup must not contain itself."), url.lastPathComponent, d.lastPathComponent) }
        }
        for s in sources where isInside(p, s.standardizedFileURL.path) { return String(format: String(localized: "%@ is already inside %@, which is backed up."), url.lastPathComponent, s.lastPathComponent) }
        return nil
    }
    static func objection(toDestination url: URL, sources: [URL]) -> String? {
        let p = url.standardizedFileURL.path
        for s in sources {
            if isInside(p, s.standardizedFileURL.path) || isInside(s.standardizedFileURL.path, p) { return String(format: String(localized: "%@ overlaps %@, which is backed up. A backup must not contain itself."), url.lastPathComponent, s.lastPathComponent) }
        }
        return nil
    }
    static func isInside(_ path: String, _ folder: String) -> Bool { path == folder || path.hasPrefix(folder.hasSuffix("/") ? folder : folder + "/") }
    static var isHome: (URL) -> Bool = { $0.standardizedFileURL.path == FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path }

    static func isFolder(_ url: URL) -> Bool {
        var d: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &d) && d.boolValue
    }
}
