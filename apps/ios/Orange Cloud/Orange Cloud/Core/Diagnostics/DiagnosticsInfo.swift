//
//  DiagnosticsInfo.swift
//  Orange Cloud
//
//  反馈邮件自动附带的诊断头与收件邮箱。诊断头不含任何隐私（无账号名 / 令牌 / 密钥）。
//

import Foundation
import UIKit

nonisolated enum DiagnosticsInfo {

    /// 反馈收件邮箱（与官网 /contact 一致）
    static let supportEmail = "support@zhe.ltd"

    /// 自动附带到反馈正文的诊断头。accountCount 只传数量，不传账号标识。
    @MainActor
    static func summary(accountCount: Int) -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build   = info?["CFBundleVersion"] as? String ?? "?"
        let os      = "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
        let formatter = ISO8601DateFormatter()
        return """
        —— 诊断信息（自动附带）——
        App: Orange Cloud \(version) (\(build))
        设备: \(deviceModel())
        系统: \(os)
        语言/地区: \(Locale.current.identifier)
        已登录账号数: \(accountCount)
        时间: \(formatter.string(from: Date()))
        """
    }

    /// 设备型号标识（如 iPhone15,2），不映射营销名
    static func deviceModel() -> String {
        var sysinfo = utsname()
        uname(&sysinfo)
        let identifier = Mirror(reflecting: sysinfo.machine).children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            result.append(Character(UnicodeScalar(UInt8(value))))
        }
        return identifier.isEmpty ? "Unknown" : identifier
    }
}
