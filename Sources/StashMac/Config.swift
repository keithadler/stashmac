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
    static var keepSnapshots: Int { let v = defaults.integer(forKey: "keepSnapshots"); return v > 0 ? v : 30 }
    static var weeklyVerify: Bool { defaults.object(forKey: "weeklyVerify") as? Bool ?? true }
    static var menuBar: Bool { defaults.object(forKey: "menuBar") as? Bool ?? true }

    static func isFolder(_ url: URL) -> Bool {
        var d: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &d) && d.boolValue
    }
}
