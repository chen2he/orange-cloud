//
//  ZoneTrafficDetailsSection.swift
//  Orange Cloud
//
//  域名分析区下方的两张卡：「访问明细」（Top 10，按国家/地区 · 状态码 · 路径 · 主机名切换）
//  与「安全事件」（按处置方式 / 按来源计数 + 最近 20 条）。时间范围跟随上方分析区的选择器
//  （24h 免费、7d/30d 由选择器按 ProFeature.analyticsRange 把关），本区不再单独设闸门。
//

import SwiftUI

struct ZoneTrafficDetailsSection: View {

    /// 宿主页持有并传入，下拉刷新与本区共用同一实例
    @Bindable var viewModel: ZoneTrafficDetailsViewModel
    let range: AnalyticsTimeRange

    var body: some View {
        VStack(spacing: 14) {
            trafficCard
            securityCard
        }
        .task(id: range) { await viewModel.load(range: range) }
    }

    // MARK: - 访问明细

    private var trafficCard: some View {
        card(String(localized: "访问明细")) {
            let state = viewModel.snapshot?.traffic
            if state == nil && viewModel.isLoading {
                skeletonRows
            } else if state?.unavailable == true {
                note(String(localized: "此域名当前无法查询该数据集"))
            } else if let error = state?.error {
                note(error)
            } else if let breakdown = state?.value {
                Picker("访问明细", selection: $viewModel.dimension) {
                    ForEach(TrafficBreakdownDimension.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                let items = breakdown.items[viewModel.dimension] ?? []
                if items.isEmpty {
                    note(String(localized: "所选时间范围内没有流量数据"))
                } else {
                    rankedRows(items) { displayValue($0, dimension: viewModel.dimension) }
                }
                clampNote(state?.window)
            }
        }
    }

    // MARK: - 安全事件

    private var securityCard: some View {
        card(String(localized: "安全事件")) {
            let state = viewModel.snapshot?.security
            if state == nil && viewModel.isLoading {
                skeletonRows
            } else if state?.unavailable == true {
                note(String(localized: "此域名当前无法查询该数据集"))
            } else if let error = state?.error {
                note(error)
            } else if let value = state?.value {
                if value.summary.byAction.isEmpty && value.summary.bySource.isEmpty && value.events.isEmpty {
                    note(String(localized: "所选时间范围内没有安全事件"))
                } else {
                    if !value.summary.byAction.isEmpty {
                        subheader(String(localized: "按处置方式"))
                        rankedRows(value.summary.byAction) { SecurityEventAction.label($0) }
                    }
                    if !value.summary.bySource.isEmpty {
                        subheader(String(localized: "按来源"))
                        rankedRows(value.summary.bySource) { $0 }
                    }
                    if !value.events.isEmpty {
                        // 独立键：中文「最近事件」已被状态页（Recent Incidents）占用
                        subheader(String(localized: "security_events.recent", defaultValue: "最近事件"))
                        VStack(spacing: 0) {
                            ForEach(value.events) { event in
                                eventRow(event)
                                if event.id != value.events.last?.id {
                                    Divider().opacity(0.4)
                                }
                            }
                        }
                    }
                }
                clampNote(state?.window)
            }
        }
    }

    private func eventRow(_ event: SecurityEvent) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(SecurityEventAction.label(event.action))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(actionColor(event.action))
                if let source = event.source, !source.isEmpty {
                    Text(source)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if let date = event.date {
                    Text(date, format: .relative(presentation: .named))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Text((event.clientRequestHTTPHost ?? "") + (event.clientRequestPath ?? ""))
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: 6) {
                if let ip = event.clientIP { Text(ip) }
                if let country = event.clientCountryName, !country.isEmpty {
                    Text(countryName(country))
                }
                Spacer(minLength: 4)
                if let ray = event.rayName {
                    Text(verbatim: "Ray \(ray)")
                        .textSelection(.enabled)
                }
            }
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.vertical, 6)
        // IP / 路径 / Ray 恒定 LTR，避免 RTL 语言下被镜像
        .environment(\.layoutDirection, .leftToRight)
    }

    // MARK: - 通用块

    /// Top N 行：取值 + 数量 + 占比条（以首项为满格）
    private func rankedRows(_ items: [TrafficBreakdownItem], label: @escaping (String) -> String) -> some View {
        let top = max(items.first?.count ?? 1, 1)
        return VStack(spacing: 8) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(label(item.value))
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Text(item.count.formatted(.number.notation(.compactName)))
                            .font(.callout.weight(.semibold))
                            .monospacedDigit()
                    }
                    GeometryReader { proxy in
                        Capsule()
                            .fill(Color.ocOrange.opacity(0.7))
                            .frame(width: max(proxy.size.width * CGFloat(item.count) / CGFloat(top), 3))
                    }
                    .frame(height: 4)
                    .accessibilityHidden(true)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func displayValue(_ raw: String, dimension: TrafficBreakdownDimension) -> String {
        dimension == .country ? countryName(raw) : raw
    }

    private func countryName(_ code: String) -> String {
        guard code.count == 2 else { return code }
        return Locale.current.localizedString(forRegionCode: code) ?? code
    }

    private func actionColor(_ action: String?) -> Color {
        switch action {
        case "block":                                              .red
        case "challenge", "managed_challenge", "jschallenge", "js_challenge": .orange
        default:                                                   .secondary
        }
    }

    @ViewBuilder
    private func clampNote(_ window: AdaptiveWindow?) -> some View {
        if let window, window.isClamped {
            let span = Duration.seconds(window.duration)
                .formatted(.units(allowed: [.days, .hours], width: .wide, maximumUnitCount: 1))
            note(String(localized: "受数据集限制，仅统计最近 \(span)"))
        }
    }

    private func subheader(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var skeletonRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(0..<4, id: \.self) { index in
                HStack {
                    SkeletonBlock(width: 90 + CGFloat((index * 37) % 70), height: 11)
                    Spacer()
                    SkeletonBlock(width: 40, height: 11)
                }
            }
        }
        .skeletonPulse()
    }

    private func card(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassIsland()
    }
}
