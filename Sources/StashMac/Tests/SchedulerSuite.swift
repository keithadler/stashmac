//  Stash for Mac — MIT licensed. See LICENSE.

import Foundation

enum SchedulerSuite {
    static let suite = TestSuite(name: "Scheduler", cases: [
        TestCase(name: "due logic") { t in
            let now = Date()
            t.check(!Scheduler.isDue(last: nil, interval: nil, now: now), "off never runs")
            t.check(Scheduler.isDue(last: nil, interval: 3600, now: now), "first run is due")
            t.check(!Scheduler.isDue(last: now.addingTimeInterval(-1800), interval: 3600, now: now), "half an hour in, not due")
            t.check(Scheduler.isDue(last: now.addingTimeInterval(-3500), interval: 3600, now: now), "slack: 58 minutes counts as an hour")
            t.check(Scheduler.isDue(last: now.addingTimeInterval(-3 * 86400), interval: 86400, now: now), "overdue")
            t.check(!Scheduler.isDue(last: now.addingTimeInterval(-6 * 86400), interval: 7 * 86400, now: now), "weekly verify not yet")
            t.check(Scheduler.isDue(last: now.addingTimeInterval(-7 * 86400), interval: 7 * 86400, now: now), "weekly verify due")
        },
        TestCase(name: "schedule choices") { t in
            t.equal(Config.Schedule.hourly.interval, 3600, "hourly")
            t.equal(Config.Schedule.daily.interval, 86400, "daily")
            t.check(Config.Schedule.off.interval == nil, "off")
            t.equal(Config.Schedule.allCases.count, 3, "three choices")
        },
    ])
}
