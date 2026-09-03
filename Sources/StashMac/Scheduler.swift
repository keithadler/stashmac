//  Stash for Mac — MIT licensed. See LICENSE.
//
//  Runs backups on the chosen schedule and a verify once a week, only while the app is open and
//  only when a destination is reachable. Checks every few minutes; the decision is a pure function
//  so it can be tested without waiting an hour.

import Foundation

@MainActor
final class Scheduler {
    static let shared = Scheduler()
    private var timer: Timer?

    /// When the next scheduled backup is due, for the menu bar.
    var nextRun: Date? {
        guard let interval = Config.schedule.interval else { return nil }
        return (Config.lastBackup ?? Date()).addingTimeInterval(interval)
    }

    /// Pure: is a run due? A little slack so "daily" still runs when the Mac wakes a few minutes early.
    static func isDue(last: Date?, interval: TimeInterval?, now: Date = Date()) -> Bool {
        guard let interval else { return false }
        guard let last else { return true }
        return now.timeIntervalSince(last) >= interval * 0.95
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in Task { @MainActor in self.tick() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { self.tick() }
    }

    func tick() {
        let model = StashModel.shared
        guard model.busy == nil, model.key != nil, !model.sources.isEmpty, !model.availableDestinations.isEmpty else { return }
        if Scheduler.isDue(last: Config.lastBackup, interval: Config.schedule.interval) {
            model.backUp(reason: "schedule")
        } else if Config.weeklyVerify, Scheduler.isDue(last: Config.lastVerify, interval: 7 * 86400), Config.lastBackup != nil {
            model.verify(reason: "schedule")
        }
    }
}
