//  Stash for Mac — MIT licensed. See LICENSE.

import Foundation

enum RetentionSuite {
    static func days(_ n: Double, before now: Date) -> Date { now.addingTimeInterval(-n * 86400) }

    static let suite = TestSuite(name: "Retention", cases: [
        TestCase(name: "thinning keeps a week, then daily, weekly, monthly") { t in
            var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
            let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 2, hour: 12))!
            // Hourly for the last 2 days, daily for 60 days, then every 3 days out to 500 days.
            var dates: [Date] = []
            for h in 0..<48 { dates.append(now.addingTimeInterval(-Double(h) * 3600)) }
            for d in 2..<60 { dates.append(days(Double(d), before: now)) }
            for d in stride(from: 60, to: 500, by: 3) { dates.append(days(Double(d), before: now)) }
            let keep = Retention.thin(dates, now: now, calendar: cal)
            let kept = keep.map { dates[$0] }
            t.equal(kept.filter { $0 >= days(7, before: now) }.count, dates.filter { $0 >= days(7, before: now) }.count, "everything inside a week")
            let dayRange = kept.filter { $0 < days(7, before: now) && $0 >= days(30, before: now) }
            t.check(dayRange.count >= 20 && dayRange.count <= 24, "about one per day for the rest of the month (\(dayRange.count))")
            let weekRange = kept.filter { $0 < days(30, before: now) && $0 >= days(365, before: now) }
            t.check(weekRange.count >= 46 && weekRange.count <= 50, "about one per week for the year (\(weekRange.count))")
            let monthRange = kept.filter { $0 < days(365, before: now) }
            t.check(monthRange.count >= 4 && monthRange.count <= 6, "about one per month after (\(monthRange.count))")
            t.check(keep.count < dates.count / 2, "thinning actually thins (\(keep.count) of \(dates.count))")
            // Within a bucket the newest survives.
            let twoDaysApart = [days(20, before: now), days(20.5, before: now)]
            let k = Retention.thin(twoDaysApart, now: now, calendar: cal)
            t.check(k.count == 1 && k.contains(0), "newest of the day wins")
        },
        TestCase(name: "newest-N and edge cases") { t in
            let now = Date()
            let dates = (0..<10).map { days(Double($0), before: now) }
            t.equal(Retention.last(dates, keep: 3), Set([0, 1, 2]), "three newest")
            t.equal(Retention.last(dates, keep: 0), Set([0]), "never fewer than one")
            t.equal(Retention.thin([days(400, before: now)], now: now), Set([0]), "a lone old snapshot is kept")
            t.check(Retention.thin([], now: now).isEmpty, "nothing to keep")
        },
        TestCase(name: "unique sizes and deleting one snapshot") { t in
            let src = try BackupSuite.tempDir("src"), dest = try BackupSuite.tempDir("dest")
            defer { [src, dest].forEach { try? FileManager.default.removeItem(at: $0) } }
            let key = MasterKey.random()
            try BackupSuite.write(src, "keep.txt", Data(repeating: 1, count: 10_000))
            try BackupSuite.write(src, "change.txt", Data(repeating: 2, count: 20_000))
            _ = try Backup.run(sources: [src], destination: dest, key: key)
            try BackupSuite.write(src, "change.txt", Data(repeating: 3, count: 30_000))
            _ = try Backup.run(sources: [src], destination: dest, key: key)
            let snaps = Restore.snapshots(destination: dest, key: key)
            let sizes = Prune.uniqueSizes(destination: dest, key: key)
            t.equal(sizes.count, 2, "one entry per snapshot")
            let older = sizes[snaps[1].fileName] ?? -1, newer = sizes[snaps[0].fileName] ?? -1
            t.check(older > 20_000 && older < 21_000, "older snapshot uniquely holds the old change.txt (\(older))")
            t.check(newer > 30_000 && newer < 31_000, "newer uniquely holds the new one (\(newer))")
            let before = Prune.size(destination: dest, key: key)
            let r = try Prune.delete(snapshot: snaps[1].fileName, destination: dest, key: key)
            t.equal(r.snapshotsRemoved, 1, "one removed")
            t.equal(r.chunksRemoved, 1, "its unique chunk freed")
            t.check(Prune.size(destination: dest, key: key) < before, "space went down")
            t.equal(Restore.snapshots(destination: dest, key: key).count, 1, "newest remains")
            t.check((try? Prune.delete(snapshot: "nope.stsm", destination: dest, key: key)) == nil, "unknown snapshot is an error")
            t.check((try? Prune.delete(snapshot: snaps[0].fileName, destination: dest, key: MasterKey.random())) == nil, "wrong key cannot delete")
            t.equal(Restore.snapshots(destination: dest, key: key).count, 1, "still there")
        },
        TestCase(name: "prune with the thinning policy end to end") { t in
            let src = try BackupSuite.tempDir("src"), dest = try BackupSuite.tempDir("dest")
            defer { [src, dest].forEach { try? FileManager.default.removeItem(at: $0) } }
            let key = MasterKey.random()
            try BackupSuite.write(src, "a.txt", Data("a".utf8))
            for _ in 0..<5 { _ = try Backup.run(sources: [src], destination: dest, key: key) }
            let far = Date().addingTimeInterval(400 * 86400)   // pretend it is next year: all five fall in one month bucket
            let r = try Prune.run(destination: dest, key: key, policy: .thin, now: far)
            t.equal(r.snapshotsRemoved, 4, "one per month survives")
            t.equal(Restore.snapshots(destination: dest, key: key).count, 1, "newest kept")
        },
    ])
}
