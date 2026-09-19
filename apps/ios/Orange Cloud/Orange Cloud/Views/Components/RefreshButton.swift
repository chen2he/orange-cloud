//
//  RefreshButton.swift
//  Orange Cloud
//
//  工具栏刷新按钮：加载中旋转、完成即停；失败时变红并在旁边显示「刷新失败」提示词，点按重试。
//  用于取代「加载失败」弹窗——状态类（刷新/加载）失败不该弹窗打断，更不该让人以为崩了。
//

import SwiftUI

struct RefreshButton: View {

    let isLoading: Bool
    let failed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if failed && !isLoading {
                // 失败态：红色「刷新失败」+ 红色刷新箭头，整体可点重试
                HStack(spacing: 4) {
                    Text("刷新失败")
                    Image(systemName: "arrow.clockwise")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.red)
            } else {
                // 正常/加载态：刷新箭头，加载时持续旋转、完成即停。
                // 用 Label 而非裸 Image：工具栏里仍只显示符号，但标题会被系统拿去做
                // 溢出菜单的条目名（Duo 竖轴放不下时刷新会溢出到菜单里，没标题就只剩一个图标）。
                Label("刷新", systemImage: "arrow.clockwise")
                    .loadingSpinSymbolEffect(isActive: isLoading)
            }
        }
        .animation(.snappy, value: failed)
        .accessibilityLabel(failed && !isLoading ? "刷新失败，点按重试" : "刷新")
    }
}

/// 内联刷新失败提示条：用于没有工具栏刷新按钮、靠下拉刷新的页面（Dashboard、流量分析）。
/// 同样不弹窗——红色一条「刷新失败，点按重试」，点按重试。
struct RefreshFailedBanner: View {

    let retry: () -> Void

    var body: some View {
        Button(action: retry) {
            Label("刷新失败，点按重试", systemImage: "arrow.clockwise")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        VStack {
            RefreshFailedBanner(retry: {})
            Text("内容")
        }
        .padding()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                RefreshButton(isLoading: false, failed: true, action: {})
            }
        }
    }
}
