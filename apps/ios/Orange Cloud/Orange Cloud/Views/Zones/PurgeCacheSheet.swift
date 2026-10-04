//
//  PurgeCacheSheet.swift
//  Orange Cloud
//
//  按目标清理缓存：URL / 前缀 / 主机名 / Cache-Tag 四种粒度。
//  每行一个目标，单次最多 30 个。2025-04 起所有套餐均可用全部粒度。
//  顶部「清除 / 标记过期」切换动作：标记过期走 invalidate_cache（2026-09-28 GA），
//  请求体与权限都和清除相同，只是保留缓存、下次请求回源校验。
//

import SwiftUI

/// 缓存清理粒度
nonisolated enum PurgeMode: String, CaseIterable, Identifiable {
    case url, prefix, host, tag

    var id: String { rawValue }

    var label: String {
        switch self {
        case .url:    String(localized: "URL")
        case .prefix: String(localized: "前缀")
        case .host:   String(localized: "主机名")
        case .tag:    String(localized: "标签")
        }
    }

    /// 输入提示（部分粒度需要带上当前域名做示例）
    func hint(zoneName: String) -> String {
        switch self {
        case .url:    String(localized: "每行一个完整 URL，例如 https://\(zoneName)/style.css")
        case .prefix: String(localized: "每行一个 URL 前缀，例如 \(zoneName)/news")
        case .host:   String(localized: "每行一个主机名，例如 assets.\(zoneName)")
        case .tag:    String(localized: "每行一个 Cache-Tag（需源站返回 Cache-Tag 响应头）")
        }
    }

    var usesURLKeyboard: Bool { self == .url || self == .prefix || self == .host }
}

struct PurgeCacheSheet: View {

    let zoneName: String
    /// 交给 ViewModel 执行；调用方按 mode 分发到对应的 purge 方法，action 区分清除 / 标记过期
    let onPurge: (PurgeMode, [String], CacheClearAction) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var action: CacheClearAction = .purge
    @State private var mode: PurgeMode = .url
    @State private var text = ""
    @State private var isPurging = false

    private static let maxItems = 30

    /// 逐行拆分、去空白、过滤空行
    private var items: [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var overLimit: Bool { items.count > Self.maxItems }

    private var isValid: Bool {
        guard !items.isEmpty, !overLimit else { return false }
        switch mode {
        case .url:
            // 单文件 purge 要求完整 URL
            return items.allSatisfy { $0.hasPrefix("http://") || $0.hasPrefix("https://") }
        case .prefix, .host, .tag:
            // 前缀/主机名/标签不带 scheme，单行内不应含空格
            return items.allSatisfy { !$0.contains(" ") }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("操作", selection: $action) {
                        Text("清除").tag(CacheClearAction.purge)
                        Text("标记过期").tag(CacheClearAction.invalidate)
                    }
                    .pickerStyle(.segmented)

                    if action == .invalidate {
                        Label("保留缓存但标记为过期，下次请求时向源站校验；内容没变（304）就继续用缓存。需要源站返回 ETag 或 Last-Modified。",
                              systemImage: "clock.arrow.circlepath")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Picker("清理粒度", selection: $mode) {
                        ForEach(PurgeMode.allCases) { m in
                            Text(m.label).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(mode.hint(zoneName: zoneName))
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $text)
                        .font(.callout.monospaced())
                        .frame(minHeight: 180)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .glassIsland(cornerRadius: OCLayout.chipRadius)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(mode.usesURLKeyboard ? .URL : .default)

                    HStack {
                        if !items.isEmpty {
                            Text("\(items.count) / \(Self.maxItems)")
                                .font(.caption)
                                .foregroundStyle(overLimit ? Color.red : Color.secondary)
                        }
                        Spacer()
                        Text("单次最多 \(Self.maxItems) 个")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding()
            }
            .background { SkyBackground() }
            .navigationTitle("按目标清理缓存")
            .navigationBarTitleDisplayMode(.inline)
            // 切换粒度时清空已输入内容，避免把 URL 当成标签误提交
            .onChange(of: mode) { text = "" }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .disabled(isPurging)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isPurging {
                        ProgressView()
                    } else {
                        Button(action == .invalidate ? String(localized: "标记过期") : String(localized: "清理")) {
                            let targets = items
                            let m = mode
                            let a = action
                            Task {
                                isPurging = true
                                await onPurge(m, targets, a)
                                isPurging = false
                                dismiss()
                            }
                        }
                        .disabled(!isValid)
                    }
                }
            }
        }
    }
}
