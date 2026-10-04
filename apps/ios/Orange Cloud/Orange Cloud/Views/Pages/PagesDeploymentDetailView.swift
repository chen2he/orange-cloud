//
//  PagesDeploymentDetailView.swift
//  Orange Cloud
//
//  Pages 部署详情：概览 + 构建阶段 + 操作（重试 / 回滚 / 删除）。
//  操作复用项目详情 VM，成功后刷新部署列表并返回。
//

import SwiftUI

struct PagesDeploymentDetailView: View {

    let deployment: PagesDeployment
    let viewModel: PagesProjectDetailViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var pendingAction: DeployAction?

    private var trigger: PagesTriggerMetadata? { deployment.deploymentTrigger?.metadata }

    var body: some View {
        List {
            overviewSection
            stagesSection
            actionsSection
        }
        .daybreakList()
        .navigationTitle(deployment.shortId ?? String(localized: "部署"))
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: viewModel.didMutate)
        .confirmationDialog(
            pendingAction?.title ?? "",
            isPresented: .init(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }),
            titleVisibility: .visible,
            presenting: pendingAction
        ) { action in
            Button(action.confirmLabel, role: action.isDestructive ? .destructive : nil) {
                Task { await perform(action) }
            }
        } message: { action in
            Text(action.message)
        }
        .alert("出错了", isPresented: .init(
            get: { viewModel.error != nil }, set: { if !$0 { viewModel.error = nil } }
        )) {
            apiErrorDocButton(for: viewModel.error)
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.error ?? "")
        }
    }

    private var overviewSection: some View {
        Section {
            HStack {
                Text("状态")
                Spacer()
                PagesStatusBadge(status: deployment.status)
            }
            infoRow("环境", value: deployment.isProduction ? String(localized: "生产") : String(localized: "预览"))
            if let url = deployment.url, let u = URL(string: url) {
                Link(destination: u) {
                    HStack {
                        Text("预览地址")
                        Spacer()
                        Text(url).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
            if let branch = trigger?.branch {
                infoRow("分支", value: branch)
            }
            if let hash = trigger?.shortHash {
                HStack {
                    Text("提交")
                    Spacer()
                    Text(hash).font(.callout.monospaced()).foregroundStyle(.secondary)
                }
            }
            if let msg = trigger?.commitMessage, !msg.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("提交信息").font(.caption).foregroundStyle(.secondary)
                    Text(msg).font(.callout)
                }
            }
            if let date = WorkerScript.parseDate(deployment.createdOn) {
                infoRow("创建于", value: date.formatted(.dateTime.year().month().day().hour().minute()))
            }
        } header: {
            Text("部署")
        }
        .glassRow()
    }

    @ViewBuilder
    private var stagesSection: some View {
        if let stages = deployment.stages, !stages.isEmpty {
            Section {
                ForEach(stages) { stage in
                    HStack {
                        Text(stageLabel(stage.name))
                        Spacer()
                        PagesStatusBadge(status: stage.statusValue)
                    }
                }
            } header: {
                Text("构建阶段")
            }
            .glassRow()
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                pendingAction = .retry
            } label: {
                actionLabel(String(localized: "重试部署"), icon: "arrow.clockwise", tint: .ocOrange)
            }
            if deployment.isProduction {
                Button {
                    pendingAction = .rollback
                } label: {
                    actionLabel(String(localized: "回滚到此部署"), icon: "arrow.uturn.backward", tint: .blue)
                }
            }
            Button(role: .destructive) {
                pendingAction = .delete
            } label: {
                actionLabel(String(localized: "删除部署"), icon: "trash", tint: .red)
            }
        } header: {
            Text("操作")
        } footer: {
            Text("重试会用相同的源重新构建；回滚使此次部署重新生效（仅生产环境）；删除不可撤销，且不能删除当前生效的部署。")
        }
        .glassRow()
        .disabled(viewModel.isMutating)
    }

    private func actionLabel(_ title: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            TintIcon(systemImage: icon, color: tint)
            Text(title).foregroundStyle(.primary)
            if viewModel.isMutating {
                Spacer()
                ProgressView()
            }
        }
    }

    private func infoRow(_ title: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        }
    }

    private func stageLabel(_ name: String?) -> String {
        switch name {
        case "queued":     String(localized: "排队")
        case "initialize": String(localized: "初始化")
        case "clone_repo": String(localized: "拉取代码")
        case "build":      String(localized: "构建")
        case "deploy":     String(localized: "部署")
        default:           name ?? String(localized: "阶段")
        }
    }

    private func perform(_ action: DeployAction) async {
        let ok: Bool
        switch action {
        case .retry:    ok = await viewModel.retry(deployment)
        case .rollback: ok = await viewModel.rollback(deployment)
        case .delete:   ok = await viewModel.deleteDeployment(deployment)
        }
        if ok { dismiss() }
    }

    enum DeployAction: Identifiable {
        case retry, rollback, delete
        var id: String { String(describing: self) }

        var title: String {
            switch self {
            case .retry:    String(localized: "重试此部署？")
            case .rollback: String(localized: "回滚到此部署？")
            case .delete:   String(localized: "删除此部署？")
            }
        }
        var confirmLabel: String {
            switch self {
            case .retry:    String(localized: "重试")
            case .rollback: String(localized: "回滚")
            case .delete:   String(localized: "删除")
            }
        }
        var isDestructive: Bool { self == .delete }
        var message: String {
            switch self {
            case .retry:    String(localized: "将用相同的源重新构建并部署。")
            case .rollback: String(localized: "将使此次部署重新成为生产环境的当前版本。")
            case .delete:   String(localized: "删除后不可恢复；不能删除当前生效的部署。")
            }
        }
    }
}
