//  DateGrouping.swift
//  CoinFlow · M3.2
//
//  把流水按天分组，提供 H3 段头文案：
//  - 今天 / 昨天 / 5月8日 周五
//  - 内部用 IANA 时区，按用户当前 timezone 计算「今天」的边界

import Foundation

struct DayGroup: Identifiable {
    /// 当地日期 00:00:00（UTC，在用户 timezone 下）
    let day: Date
    let records: [Record]
    var id: TimeInterval { day.timeIntervalSince1970 }

    /// 段头文案，§5.5.7 H3 规格
    var headerText: String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "今天" }
        if cal.isDateInYesterday(day) { return "昨天" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEEE"
        return f.string(from: day)
    }
}

enum DateGrouping {
    /// 按"用户当前时区下的日期"分组，最近的在前。
    static func group(_ records: [Record]) -> [DayGroup] {
        let cal = Calendar.current
        var buckets: [Date: [Record]] = [:]
        for r in records {
            let dayStart = cal.startOfDay(for: r.occurredAt)
            buckets[dayStart, default: []].append(r)
        }
        return buckets
            .map { (day, recs) in
                DayGroup(day: day, records: recs.sorted { $0.occurredAt > $1.occurredAt })
            }
            .sorted { $0.day > $1.day }
    }
}
