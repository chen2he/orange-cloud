//
//  WorkersAIView.swift
//  Orange Cloud
//
//  Workers AI 模型目录（按任务类型分组，可搜索）。account 级，ai.read。
//  点模型查看详情；文本生成（Text Generation）与文生图（Text-to-Image）模型可试运行（Playground），
//  需 ai.read + ai.write。文生图返回图片二进制，走 CFAPIClient.postRaw。
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct WorkersAIView: View {

    let session: SessionStore
    @State private var vm: WorkersAIViewModel?
    @State private var searchText = ""
    @State private var detailTarget: AIModel?

    var body: some View {
        Group {
            if let vm { content(vm) } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .background { SkyBackground() }
        .navigationTitle("Workers AI")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "搜索模型")
        .sheet(item: $detailTarget) { model in
            AIModelDetailSheet(session: session, model: model)
        }
        .task {
            await session.ensureAccounts()
            guard vm == nil else { return }
            let model = WorkersAIViewModel(service: session.workersAIService, accountId: session.selectedAccount?.id)
            vm = model
            await model.load()
        }
    }

    @ViewBuilder
    private func content(_ vm: WorkersAIViewModel) -> some View {
        if vm.isLoading && !vm.loaded {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.models.isEmpty {
            ContentUnavailableView {
                Label("没有可用模型", systemImage: "brain")
            } description: {
                Text(vm.error ?? String(localized: "未能取到 Workers AI 模型目录。"))
            }
        } else {
            let groups = filteredGroups(vm)
            if groups.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List {
                    ForEach(groups, id: \.task) { group in
                        Section {
                            ForEach(group.models) { model in
                                Button { detailTarget = model } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(model.shortName).font(.callout.weight(.semibold)).lineLimit(1)
                                                .foregroundStyle(.primary)
                                            if let desc = model.description, !desc.isEmpty {
                                                Text(desc).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                            }
                                            Text(model.name ?? model.id)
                                                .font(.caption2.monospaced()).foregroundStyle(.tertiary)
                                                .lineLimit(1).truncationMode(.middle)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                                    }
                                    .padding(.vertical, 2)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        } header: {
                            Text(group.task)
                        }
                        .glassRow()
                    }
                }
                .daybreakList()
                .refreshable { await detachedRefresh { await vm.load() } }
            }
        }
    }

    private func filteredGroups(_ vm: WorkersAIViewModel) -> [(task: String, models: [AIModel])] {
        guard !searchText.isEmpty else { return vm.grouped }
        return vm.grouped.compactMap { group in
            let matches = group.models.filter {
                $0.shortName.localizedCaseInsensitiveContains(searchText)
                    || ($0.name ?? "").localizedCaseInsensitiveContains(searchText)
                    || ($0.description ?? "").localizedCaseInsensitiveContains(searchText)
            }
            return matches.isEmpty ? nil : (task: group.task, models: matches)
        }
    }
}

// MARK: - 模型详情 + 试运行 Playground（文本生成 / 文生图）

private struct AIModelDetailSheet: View {

    let session: SessionStore
    let model: AIModel

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var auth
    @State private var playVM: AIPlaygroundViewModel
    @State private var imageVM: AIImagePlaygroundViewModel

    init(session: SessionStore, model: AIModel) {
        self.session = session
        self.model = model
        _playVM = State(initialValue: AIPlaygroundViewModel(
            service: session.workersAIService,
            accountId: session.selectedAccount?.id,
            model: model
        ))
        _imageVM = State(initialValue: AIImagePlaygroundViewModel(
            service: session.workersAIService,
            accountId: session.selectedAccount?.id,
            model: model
        ))
    }

    private var hasAIWrite: Bool { auth.hasScope("ai.write") }

    var body: some View {
        @Bindable var playVM = playVM
        @Bindable var imageVM = imageVM
        NavigationStack {
            List {
                Section {
                    if let desc = model.description, !desc.isEmpty {
                        Text(desc).font(.callout)
                    }
                    if !model.taskName.isEmpty { LabeledContent("任务", value: model.taskName) }
                    LabeledContent("模型") {
                        Text(model.name ?? model.id).font(.caption.monospaced())
                            .foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }
                .glassRow()

                if model.isTextGen {
                    if hasAIWrite {
                        playground(text: $playVM.prompt, vm: playVM)
                    } else {
                        reauthorizeSection
                    }
                } else if model.isImageGen {
                    if hasAIWrite {
                        imagePlayground(text: $imageVM.prompt, vm: imageVM)
                    } else {
                        reauthorizeSection
                    }
                } else {
                    Section {} footer: {
                        Text("该模型的输入/输出格式与文本生成不同，暂不支持在 App 内试运行。")
                    }
                }
            }
            .daybreakList()
            .background { SkyBackground() }
            .navigationTitle(model.shortName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
    }

    @ViewBuilder
    private var reauthorizeSection: some View {
        Section {
            if let sessionId = auth.currentSessionId {
                ReauthorizeButton(sessionId: sessionId, scopes: ["ai.write"])
            }
        } header: {
            Text("试运行")
        } footer: {
            Text("在 App 内试运行模型需要 Workers AI 写权限（ai.write）。点上方按钮一键补齐授权，无需退出登录。")
        }
        .glassRow()
    }

    // MARK: - 文生图 Playground

    @ViewBuilder
    private func imagePlayground(text: Binding<String>, vm: AIImagePlaygroundViewModel) -> some View {
        Section {
            TextField("描述你想生成的画面", text: text, axis: .vertical)
                .lineLimit(3...8)
            Button {
                Task { await vm.run() }
            } label: {
                HStack {
                    Spacer()
                    if vm.isRunning {
                        ProgressView()
                    } else {
                        Label("生成图片", systemImage: "photo").fontWeight(.semibold)
                    }
                    Spacer()
                }
            }
            .disabled(!vm.canRun)
        } header: {
            Text("试运行")
        } footer: {
            Text("按提示词生成一张图片。会消耗账号的 Workers AI 用量（每天 1 万 Neuron 免费额度）。")
        }
        .glassRow()

        if vm.isRunning || vm.error != nil || vm.imageData != nil {
            Section {
                if let error = vm.error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                } else if vm.isRunning {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else {
                    generatedImage(vm)
                }
            } header: {
                Text("输出")
            }
            .glassRow()
        }
    }

    @ViewBuilder
    private func generatedImage(_ vm: AIImagePlaygroundViewModel) -> some View {
        #if canImport(UIKit)
        if let uiImage = vm.image {
            let image = Image(uiImage: uiImage)
            VStack(spacing: 10) {
                image
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                ShareLink(
                    item: image,
                    preview: SharePreview("生成的图片", image: image)
                ) {
                    Label("分享 / 存储", systemImage: "square.and.arrow.up")
                        .font(.callout)
                }
            }
            .padding(.vertical, 4)
        }
        #endif
    }

    @ViewBuilder
    private func playground(text: Binding<String>, vm: AIPlaygroundViewModel) -> some View {
        Section {
            TextField("输入提示词", text: text, axis: .vertical)
                .lineLimit(3...8)
            Button {
                Task { await vm.run() }
            } label: {
                HStack {
                    Spacer()
                    if vm.isRunning {
                        ProgressView()
                    } else {
                        Label("运行", systemImage: "play.fill").fontWeight(.semibold)
                    }
                    Spacer()
                }
            }
            .disabled(!vm.canRun)
        } header: {
            Text("试运行")
        } footer: {
            Text("发送一条用户消息并显示模型回复。会消耗账号的 Workers AI 用量（每天 1 万 Neuron 免费额度）。")
        }
        .glassRow()

        if vm.isRunning || !vm.output.isEmpty || vm.error != nil {
            Section {
                if let error = vm.error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                } else if vm.output.isEmpty && vm.isRunning {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else {
                    Text(vm.output).font(.callout).textSelection(.enabled)
                }
            } header: {
                Text("输出")
            }
            .glassRow()
        }
    }
}
