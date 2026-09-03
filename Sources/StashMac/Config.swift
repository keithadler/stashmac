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

    static func isFolder(_ url: URL) -> Bool {
        var d: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &d) && d.boolValue
    }
}
