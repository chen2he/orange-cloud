//
//  WorkerLogsView.swift
//  Orange Cloud
//
//  历史日志（Workers Logs / Observability）：可回溯的日志查询。
//  与「实时日志」互补——tail 只播放连接期间的调用，这里查已经落库的事件。
//

import SwiftUI
import UIKit

struct WorkerLogsView: View {

    @State private var viewModel: WorkerLogsViewModel
    @State private var detailEvent: IdentifiedLogEvent?
    @State private var copyTick = 0
    @Environment(\.colorScheme) private var colorScheme

    init(accountId: String, scriptName: String, session: SessionStore) {
        _viewModel = State(initialValue: WorkerLogsViewModel(
            service: session.workerLogsService,
            accountId: accountId,
            scriptName: scriptName
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .sensoryFeedback(.success, trigger: copyTick)
        .sheet(item: $detailEvent) { item in
            LogEventDetailSheet(event: item.event) { copy(item.event) }
        }
        .navigationTitle("历史日志")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                RefreshButton(
                    isLoading: viewModel.isLoading,
                    failed: viewModel.error != nil && !viewModel.events.isEmpty
                ) {
                    Task { await viewModel.load() }
                }
            }
        }
        // 时间窗与级别都下推给服务端，改了就重查
        .task(id: viewModel.range) { await viewModel.load() }
        .task(id: viewModel.levelFilter) { await viewModel.load() }
    }

    // MARK: - 顶部筛选

    private var header: some View {
        VStack(spacing: 8) {
            Picker("时间范围", selection: $viewModel.range) {
                ForEach(WorkerLogsViewModel.TimeRange.allCases) { range in
                    Text(range.label).tag(range)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 8) {
                searchField
                levelMenu
            }

            if let total = viewModel.totalCount, !viewModel.events.isEmpty {
                HStack {
                    Text("命中 \(total) 条，已载入 \(viewModel.events.count) 条")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.footnote)
                .foregroundStyle(.secondary)
            TextField("搜索日志", text: $viewModel.searchText)
                .font(.footnote)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { Task { await viewModel.load() } }
            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                    Task { await viewModel.load() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(OCGlass.fill(for: colorScheme), in: .rect(cornerRadius: 9))
    }

    private var levelMenu: some View {
        Menu {
            Picker("级别", selection: $viewModel.levelFilter) {
                ForEach(WorkerLogsViewModel.LevelFilter.allCases) { level in
                    Text(level.title).tag(level)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label(viewModel.levelFilter.title, systemImage: "line.3.horizontal.decrease.circle")
                .font(.footnote)
                .foregroundStyle(viewModel.levelFilter == .all ? Color.secondary : Color.ocOrangeText)
        }
        .accessibilityLabel("按级别筛选")
    }

    // MARK: - 列表

    @ViewBuilder
    private var content: some View {
        ScrollView {
            if viewModel.isLoading && viewModel.events.isEmpty {
                loadingSkeleton
            } else if let error = viewModel.error, viewModel.events.isEmpty {
                errorHint(error)
            } else if viewModel.events.isEmpty {
                emptyHint
            } else {
                eventList
            }
        }
        .background { SkyBackground() }
        .refreshable { await viewModel.load() }
    }

    private var eventList: some View {
        LazyVStack(alignment: .leading, spacing: 4) {
            ForEach(viewModel.events) { item in
                LogEventRow(
                    event: item.event,
                    onCopy: { copy(item.event) },
                    onOpen: { detailEvent = item }
                )
            }
            if viewModel.canLoadMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .task { await viewModel.loadMore() }
            }
        }
        .padding(12)
        // 日志正文恒定 LTR，避免 RTL 语言下 URL / JSON 被镜像
        .environment(\.layoutDirection, .leftToRight)
    }

    private var loadingSkeleton: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(0..<8, id: \.self) { index in
                HStack(spacing: 8) {
                    SkeletonBlock(width: 56, height: 10)
                    SkeletonBlock(width: 120 + CGFloat((index * 37) % 90), height: 10)
                    Spacer()
                }
            }
        }
        .skeletonPulse()
        .padding(16)
    }

    private var emptyHint: some View {
        ContentUnavailableView {
            Label("这段时间没有日志", systemImage: "clock.badge.questionmark")
        } description: {
            Text("换个时间范围看看。若这个 Worker 从未出现日志，多半是没有开启 Observability——在 wrangler.toml 里打开 [observability] 后重新部署即可。")
        }
        .padding(.top, 60)
    }

    private func errorHint(_ message: String) -> some View {
        ContentUnavailableView {
            Label("查询失败", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("重试") { Task { await viewModel.load() } }
                .buttonStyle(.bordered)
                .tint(Color.ocOrange)
            APIErrorDocLink(message: message)
        }
        .padding(.top, 60)
    }

    private func copy(_ event: TelemetryEvent) {
        UIPasteboard.general.string = event.displayText
        copyTick += 1
    }
}

// MARK: - 单条事件行

private struct LogEventRow: View {
    let event: TelemetryEvent
    let onCopy: () -> Void
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(event.date, format: .dateTime.month(.twoDigits).day(.twoDigits)
                        .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)

                Text(event.displayText)
                    .font(.caption.monospaced())
                    .foregroundStyle(LogEventStyle.color(for: event))
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let status = event.metadata?.statusCode {
                    Text(String(status))
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(LogEventStyle.statusColor(status))
                }
            }
            .padding(.vertical, 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("复制此行", systemImage: "doc.on.doc", action: onCopy)
        }
        .accessibilityHint(Text("轻点查看详情，长按复制整行"))
    }
}

private enum LogEventStyle {
    static func color(for event: TelemetryEvent) -> Color {
        switch event.level {
        case "error", "exception": .red
        case "warn":               .orange
        case "event":              .secondary
        default:                   .primary
        }
    }

    static func statusColor(_ code: Int) -> Color {
        switch code {
        case 500...: .red
        case 400...: .orange
        default:     .secondary
        }
    }
}

// MARK: - 事件详情

private struct LogEventDetailSheet: View {
    let event: TelemetryEvent
    let onCopy: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    metaSection
                    requestSection
                    bodySection
                }
                .padding(16)
            }
            .background { SkyBackground() }
            .navigationTitle("日志详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("复制全部", systemImage: "doc.on.doc", action: onCopy)
                        .tint(Color.ocOrange)
                }
            }
        }
    }

    private var metaSection: some View {
        island {
            fieldRow(title: Text("级别"), value: event.level, tint: LogEventStyle.color(for: event))
            Divider().opacity(0.4)
            fieldRow(title: Text("时间"),
                     value: event.date.formatted(date: .abbreviated, time: .standard),
                     tint: .secondary)
            if let outcome = event.workers?.outcome, !outcome.isEmpty {
                Divider().opacity(0.4)
                fieldRow(title: Text("结果"), value: outcome, tint: .secondary)
            }
            if let eventType = event.workers?.eventType, !eventType.isEmpty {
                Divider().opacity(0.4)
                fieldRow(title: Text("事件类型"), value: eventType, tint: .secondary)
            }
        }
    }

    @ViewBuilder
    private var requestSection: some View {
        let metadata = event.metadata
        if metadata?.trigger != nil || metadata?.url != nil || metadata?.statusCode != nil
            || metadata?.requestId != nil || metadata?.rayId != nil || metadata?.duration != nil {
            island {
                if let trigger = metadata?.trigger, !trigger.isEmpty {
                    fieldRow(title: Text("触发"), value: trigger, tint: .primary)
                }
                if let url = metadata?.url, !url.isEmpty {
                    Divider().opacity(0.4)
                    fieldRow(title: Text("请求地址"), value: url, tint: .primary)
                }
                if let status = metadata?.statusCode {
                    Divider().opacity(0.4)
                    fieldRow(title: Text("状态码"), value: String(status),
                             tint: LogEventStyle.statusColor(status))
                }
                if let duration = metadata?.duration {
                    Divider().opacity(0.4)
                    fieldRow(title: Text("耗时"), value: String(format: "%.1f ms", duration), tint: .secondary)
                }
                if let requestId = metadata?.requestId, !requestId.isEmpty {
                    Divider().opacity(0.4)
                    fieldRow(title: Text("请求 ID"), value: requestId, tint: .secondary)
                }
                if let rayId = metadata?.rayId, !rayId.isEmpty {
                    Divider().opacity(0.4)
                    fieldRow(title: Text("Ray ID"), value: rayId, tint: .secondary)
                }
            }
        }
    }

    private var bodySection: some View {
        island {
            VStack(alignment: .leading, spacing: 8) {
                Text("完整内容")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(event.displayText)
                    .font(.callout.monospaced())
                    .foregroundStyle(LogEventStyle.color(for: event))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .environment(\.layoutDirection, .leftToRight)
                Text("长按可选中其中的片段单独复制")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private func fieldRow(title: Text, value: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            title
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.footnote.monospaced())
                .foregroundStyle(tint)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.layoutDirection, .leftToRight)
        }
        .padding(.vertical, 4)
    }

    /// 玻璃岛：OCGlass 纯色近似，不用真材质（backdrop blur 会掉帧）
    @ViewBuilder
    private func island<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OCGlass.fill(for: colorScheme), in: .rect(cornerRadius: 16))
    }
}
