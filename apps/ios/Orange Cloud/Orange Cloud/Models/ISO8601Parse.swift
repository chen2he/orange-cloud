//
//  ISO8601Parse.swift
//  Orange Cloud
//
//  进程级共享的 ISO8601 解析器。ISO8601DateFormatter 构造相当重（内部建 NSCalendar/时区），
//  以前 WorkerScript.parseDate 等在列表行 body 与排序比较器里每次调用都新建一个，
//  百条列表一次滚动就是几百次构造。ISO8601DateFormatter 线程安全，做成 static let 全局复用。
//

import Foundation

nonisolated enum ISO8601Parse {

    /// 带 6 位小数秒（CF 大多数端点：2026-03-22T20:05:13.916883Z）
    static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// 不带小数秒（GraphQL datetime、计费周期等）
    static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// 先按带小数秒解析，失败再按整秒解析
    static func date(_ string: String?) -> Date? {
        guard let string else { return nil }
        return fractional.date(from: string) ?? plain.date(from: string)
    }
}
