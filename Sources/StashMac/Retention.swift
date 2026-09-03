//  Stash for Mac — MIT licensed. See LICENSE.
//
//  Which snapshots to keep. Two policies: the newest N, or "thin out": everything from the last
//  week, one a day for a month, one a week for a year, one a month after that. The choice is a pure
//  function of dates so it can be tested with made-up calendars.

import Foundation

enum Retention {
    enum Policy: String, CaseIterable, Identifiable {
        case last, thin
        var id: String { rawValue }
        var label: String {
            switch self {
            case .last: return String(localized: "Keep the newest snapshots")
            case .thin: return String(localized: "Thin out over time")
            }
        }
    }

    /// Indices (into `dates`, any order) of snapshots to keep under the thinning policy.
    /// Buckets are chosen by the local calendar; the newest snapshot in each bucket survives.
    static func thin(_ dates: [Date], now: Date = Date(), calendar: Calendar = .current) -> Set<Int> {
        var keep = Set<Int>()
        var dayBuckets: [String: (Int, Date)] = [:], weekBuckets: [String: (Int, Date)] = [:], monthBuckets: [String: (Int, Date)] = [:]
        let week = now.addingTimeInterval(-7 * 86400), month = now.addingTimeInterval(-30 * 86400), year = now.addingTimeInterval(-365 * 86400)
        for (i, d) in dates.enumerated() {
            if d >= week { keep.insert(i); continue }
            let c = calendar.dateComponents([.year, .month, .day, .weekOfYear, .yearForWeekOfYear], from: d)
            func newest(_ table: inout [String: (Int, Date)], _ key: String) { if let cur = table[key], cur.1 >= d { return }; table[key] = (i, d) }
            if d >= month { newest(&dayBuckets, "\(c.year!)-\(c.month!)-\(c.day!)") }
            else if d >= year { newest(&weekBuckets, "\(c.yearForWeekOfYear!)-w\(c.weekOfYear!)") }
            else { newest(&monthBuckets, "\(c.year!)-\(c.month!)") }
        }
        for t in [dayBuckets, weekBuckets, monthBuckets] { for (_, v) in t { keep.insert(v.0) } }
        if keep.isEmpty, let newest = dates.indices.max(by: { dates[$0] < dates[$1] }) { keep.insert(newest) }
        return keep
    }

    /// Indices to keep under the "newest N" policy.
    static func last(_ dates: [Date], keep n: Int) -> Set<Int> {
        let order = dates.indices.sorted { dates[$0] > dates[$1] }
        return Set(order.prefix(max(n, 1)))
    }
}
