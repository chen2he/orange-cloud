//
//  TestFlightSunset.swift
//  Orange Cloud
//
//  TestFlight 测试轨停用公告的判定：只在 TestFlight 构建、且落在公告窗口内才成立。
//  商店版永不触发——判据是 receipt 文件名（TestFlight 装的包是 sandboxReceipt），
//  不用编译开关：同一份代码进了商店也不会弹，省掉「忘了摘开关」这类事故。
//

import Foundation

nonisolated enum TestFlightSunset {

    /// 公告开始展示（含当天）
    static let noticeStart = utcDate(2026, 9, 18)
    /// 优惠码申请截止（含当天）
    static let codeDeadline = utcDate(2026, 9, 30)
    /// TestFlight 构建到期日：这天之后包会被 TestFlight 停用、无法再启动
    static let buildExpiry = utcDate(2026, 10, 6)

    static let appStoreURL = URL(string: "https://apps.apple.com/app/id6779323783")!

    /// 领码来信的收件人 = 公司支持邮箱（与设置页「帮助与反馈」同一个地址）


    /// 当前包是否来自 TestFlight。App Store 包的 receipt 叫 `receipt`，
    /// TestFlight（与模拟器/开发包）叫 `sandboxReceipt`。
    static var isTestFlightBuild: Bool {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }

    /// 是否该弹公告。`acted` = 用户已点过「领码」或「去 App Store」；
    /// `shownCount` 给一个上限，避免误关一次就再也看不到（TestFlight 的「测试内容」里另有同样说明）。
    static func shouldPresent(now: Date = .now, acted: Bool, shownCount: Int) -> Bool {
        #if DEBUG
        // 模拟器巡检：ORANGE_TF_SUNSET=1 时跳过日期与来源判定直接弹。
        // 模拟器的 receipt 路径不等同真机，别拿 isTestFlightBuild 当这里的前置条件。
        if ProcessInfo.processInfo.environment["ORANGE_TF_SUNSET"] == "1" { return true }
        #endif
        guard isTestFlightBuild, !acted, shownCount < maxPresentations else { return false }
        return now >= noticeStart && now < buildExpiry
    }

    static let maxPresentations = 3

    private static func utcDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        return calendar.date(from: components) ?? .distantFuture
    }
}
