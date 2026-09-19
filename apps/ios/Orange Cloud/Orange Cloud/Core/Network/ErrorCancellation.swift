//
//  ErrorCancellation.swift
//  Orange Cloud
//
//  「被取消」不是加载失败。SwiftUI 的 .task(id:) 切换、.refreshable 与 .searchable 叠加、
//  用户离开页面，都会把飞行中的请求取消：结构化取消抛 CancellationError，URLSession 抛
//  URLError(.cancelled)，经 CFAPIClient 再包一层就是 APIError.networkError(URLError)。
//  ViewModel 在 catch 里先问一句 isCancellation，别把它写进 error 覆盖掉正在到来的新数据。
//

import Foundation

nonisolated extension Error {
    var isCancellation: Bool {
        if self is CancellationError { return true }
        if let urlError = self as? URLError, urlError.code == .cancelled { return true }
        if let api = self as? APIError, case .networkError(let inner) = api { return inner.isCancellation }
        return false
    }
}
