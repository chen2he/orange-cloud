//
//  RefreshTask.swift
//  Orange Cloud
//
//  .refreshable 与 .searchable 叠加在同一个 List 上时，下拉刷新闭包所在的子任务会被 SwiftUI 取消
//  （实测 100% 复现「网络错误：已取消」，见 ZoneListViewModel.refresh 的说明）。
//  把真正的加载放进一个独立的非结构化 Task，再从外面等它：取消只波及等待方，请求本身照常跑完。
//

import Foundation

@MainActor
func detachedRefresh(_ operation: @escaping @MainActor () async -> Void) async {
    let task = Task { @MainActor in await operation() }
    await task.value
}
