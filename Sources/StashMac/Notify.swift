//  Stash for Mac — MIT licensed. See LICENSE.
//
//  One notification when a scheduled backup or verify fails, and one when the first backup to a
//  destination completes. Nothing chatty: a backup that works should be invisible.

import Foundation
import UserNotifications

enum Notify {
    static func requestPermissionIfNeeded() {
        guard Bundle.main.bundleIdentifier != nil else { return }   // not from a bare binary
        UNUserNotificationCenter.current().getNotificationSettings { s in
            if s.authorizationStatus == .notDetermined {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
            }
        }
    }

    static func post(_ title: String, _ body: String, id: String = UUID().uuidString) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body; c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: c, trigger: nil))
    }
}
