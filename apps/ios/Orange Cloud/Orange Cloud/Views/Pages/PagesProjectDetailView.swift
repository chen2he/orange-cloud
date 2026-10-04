//
//  PagesProjectDetailView.swift
//  Orange Cloud
//
//  Pages 项目详情：信息 + 部署列表（→ 重试 / 回滚 / 删除）+ 环境变量（只读）+ 构建配置 + 删项目。
//

import SwiftUI

struct PagesProjectDetailView: View {

    @Environment(AuthManager.self) private var auth
    @State private var viewModel: PagesProjectDetailViewModel
    @State private var deployViewModel: PagesDeployViewModel
    @State private var showDeleteConfirm = false
    @State private var showDeploy = false
    // 子页（域名 / 部署详情 / 构建配置）走 sheet，不走 push：见 infoSection 内注释
    @State private var showDomains = false
    @State private var showBuildConfig = false
    @State private var deploymentDetail: PagesDeployment?
    @Environment(\.dismiss) private var dismiss

    private let session: SessionStore

    init(project: PagesProject, session: SessionStore) {
        self.session = session
        let accountId = session.selectedAccount?.id ?? ""
        _viewModel = State(initialValue: PagesProjectDetailViewModel(
            project: project,
            accountId: accountId,
            service: session.pagesService
        ))
        _deployViewModel = State(initialValue: PagesDeployViewModel(
            service: session.pagesService,
            accountId: accountId,
            projectName: project.name
        ))
    }

    private var project: PagesProject { viewModel.project }
    private var canWrite: Bool { auth.hasScope("page.write") }

    var body: some View {
        List {
            infoSection
            if canWrite { deploySection }
            deploymentsSection
            envVarsSection
            configSection
            dangerSection
        }
        .daybreakList()
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadDeployments() }
        .refreshable {
            await viewModel.refreshProject()
            await viewModel.loadDeployments()
        }
        .sheet(isPresented: $showDeploy) {
            PagesDeployView(viewModel: deployViewModel) {
                Task {
                    await viewModel.loadDeployments()
                    await viewModel.refreshProject()
                }
            }
        }
        .sheet(isPresented: $showDomains) {
            NavigationStack {
                PagesDomainsView(project: project, session: session)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("完成") { showDomains = false }
                        }
                    }
            }
        }
        .sheet(item: $deploymentDetail) { dep in
            NavigationStack {
                PagesDeploymentDetailView(deployment: dep, viewModel: viewModel)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("完成") { deploymentDetail = nil }
                        }
                    }
            }
        }
        .sheet(isPresented: $showBuildConfig) {
            NavigationStack {
                PagesBuildConfigEditorView(viewModel: viewModel)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("取消") { showBuildConfig = false }
                        }
                    }
            }
        }
        .sensoryFeedback(.success, trigger: viewModel.didMutate)
        .sensoryFeedback(.success, trigger: deployViewModel.phase == .done)
        .confirmationDialog("删除项目「\(project.name)」？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除项目", role: .destructive) {
                Task { if await viewModel.deleteProject() { dismiss() } }
            }
        } message: {
            Text("将移除该项目的所有部署，且不可撤销。")
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

    // MARK: - 信息

    private var infoSection: some View {
        Section {
            if let sub = project.subdomain, let url = URL(string: "https://\(sub)") {
                Link(destination: url) {
                    HStack {
                        Text("访问地址")
                        Spacer()
                        Text(sub).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
            if let branch = project.productionBranch {
                infoRow("生产分支", value: branch)
            }
            if let repo = project.source?.config?.repoLabel {
                infoRow(project.source?.type == "gitlab" ? "GitLab" : "GitHub", value: repo)
            }
            // ⚠️ 本页经两层 value push 进 DevHub 栈后，行内 eager NavigationLink 在
            // iOS 17.0 点击不触发（2026-07-07 模拟器实测；26.5 正常）。子页一律改 sheet
            // （同 Workers 实时日志的先例），别改回 push。
            Button {
                showDomains = true
            } label: {
                HStack {
                    Text("自定义域名")
                        .foregroundStyle(.primary)
                    Spacer()
                    if let domains = project.domains, !domains.isEmpty {
                        Text("\(domains.count) 个域名")
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            if let date = WorkerScript.parseDate(project.createdOn) {
                infoRow("创建于", value: date.formatted(.dateTime.year().month().day()))
            }
        } header: {
            Text("项目")
        }
        .glassRow()
    }

    // MARK: - 上传部署（Direct Upload）

    private var deploySection: some View {
        Section {
            Button {
                showDeploy = true
            } label: {
                HStack(spacing: 12) {
                    TintIcon(systemImage: "arrow.up.circle", color: .ocOrange)
                    Text("上传部署")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        } footer: {
            Text("粘贴代码或选择文件 / ZIP，直接上传生成一次新部署。")
        }
        .glassRow()
    }

    // MARK: - 部署

    private var deploymentsSection: some View {
        Section {
            if viewModel.isLoadingDeployments && !viewModel.deploymentsLoaded {
                ProgressView().frame(maxWidth: .infinity)
            } else if viewModel.deployments.isEmpty {
                Text("暂无部署").font(.footnote).foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.deployments.prefix(20)) { dep in
                    Button {
                        deploymentDetail = dep
                    } label: {
                        deploymentRow(dep)
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("部署")
        } footer: {
            Text("点按查看构建阶段，并可重试 / 回滚 / 删除。")
        }
        .glassRow()
    }

    private func deploymentRow(_ dep: PagesDeployment) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    PagesStatusBadge(status: dep.status)
                    Text(dep.isProduction ? String(localized: "生产") : String(localized: "预览"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let msg = dep.deploymentTrigger?.metadata?.commitMessage, !msg.isEmpty {
                    Text(msg).font(.caption).foregroundStyle(.primary).lineLimit(1)
                } else if let branch = dep.deploymentTrigger?.metadata?.branch {
                    Text(branch).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if let date = WorkerScript.parseDate(dep.createdOn) {
                Text(date, format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - 环境变量（只读）

    @ViewBuilder
    private var envVarsSection: some View {
        if let envVars = project.deploymentConfigs?.production?.envVars, !envVars.isEmpty {
            Section {
                ForEach(envVars.keys.sorted(), id: \.self) { key in
                    HStack {
                        Text(key).font(.callout.monospaced()).lineLimit(1)
                        Spacer()
                        if let v = envVars[key] {
                            Text(v.isSecret ? "••••••" : (v.value ?? ""))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            } header: {
                Text("生产环境变量")
            } footer: {
                Text("环境变量在 App 内只读；密钥值已隐藏。需修改请在 Cloudflare 控制台操作。")
            }
            .glassRow()
        }
    }

    // MARK: - 配置

    private var configSection: some View {
        Section {
            Button {
                showBuildConfig = true
            } label: {
                HStack(spacing: 12) {
                    TintIcon(systemImage: "hammer", color: .blue)
                    Text("构建配置")
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        } header: {
            Text("配置")
        }
        .glassRow()
    }

    // MARK: - 危险操作

    private var dangerSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                HStack(spacing: 12) {
                    TintIcon(systemImage: "trash", color: .red)
                    Text("删除项目")
                    if viewModel.isMutating {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(viewModel.isMutating)
        } footer: {
            Text("删除项目会移除所有部署，且不可撤销。")
        }
        .glassRow()
    }

    private func infoRow(_ title: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
