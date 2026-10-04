//
//  R2ObjectListView.swift
//  Orange Cloud
//
//  R2 对象列表（上传/删除/游标分页）→ 对象详情（QuickLook 预览）。
//  入口：StorageView 的 R2 段。
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import QuickLook

struct R2ObjectListView: View {

    let bucket: R2Bucket

    @Environment(SessionStore.self) private var session
    @Environment(AuthManager.self) private var auth
    @State private var viewModel: R2ObjectListViewModel
    @State private var selectedObject: R2Object?
    @State private var objectToDelete: R2Object?
    @State private var showDenied = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var previewURL: URL?
    @State private var transferTarget: TransferRequest?
    @State private var showTooLarge = false
    @State private var showSettings = false

    init(bucket: R2Bucket, session: SessionStore) {
        self.bucket = bucket
        _viewModel = State(initialValue: R2ObjectListViewModel(
            service: session.r2Service,
            accountId: session.selectedAccount?.id ?? "",
            bucketName: bucket.name,
            jurisdiction: bucket.jurisdiction
        ))
    }

    private var canWrite: Bool { auth.hasScope("workers-r2.write") }

    var body: some View {
        Group {
            if viewModel.isContentEmpty && viewModel.isLoading {
                SkeletonList(rows: 9, trailing: true)
            } else if viewModel.isContentEmpty && viewModel.currentPrefix.isEmpty {
                ContentUnavailableView {
                    Label("空存储桶", systemImage: "archivebox")
                } description: {
                    Text(canWrite ? String(localized: "点击右上角上传第一个文件") : String(localized: "这个存储桶里还没有对象"))
                }
            } else {
                objectList
            }
        }
        .background { SkyBackground() }
        .navigationTitle(viewModel.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Label("桶设置", systemImage: "gearshape")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.isUploading {
                    ProgressView()
                } else {
                    Menu {
                        if canWrite {
                            Button {
                                showPhotoPicker = true
                            } label: {
                                Label("上传照片或视频", systemImage: "photo")
                            }
                            Button {
                                showFileImporter = true
                            } label: {
                                Label("上传文件", systemImage: "doc")
                            }
                        } else {
                            Button {
                                showDenied = true
                            } label: {
                                Label("需要 R2 写权限", systemImage: "lock")
                            }
                        }
                    } label: {
                        Label("上传", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .any(of: [.images, .videos]))
        .quickLookPreview($previewURL)
        .overlay {
            if viewModel.isDownloading {
                ZStack {
                    Color.black.opacity(0.15).ignoresSafeArea()
                    ProgressView("下载中…")
                        .padding(18)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
        .task { await viewModel.load() }
        .onChange(of: photoItem) {
            guard let item = photoItem else { return }
            photoItem = nil
            guard canWrite else { showDenied = true; return }
            Task { await uploadPhoto(item) }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item]) { result in
            guard canWrite else { showDenied = true; return }
            if case .success(let url) = result {
                Task { await uploadFile(url) }
            }
        }
        .sheet(item: $selectedObject) { object in
            R2ObjectDetailView(object: object, viewModel: viewModel, canWrite: canWrite)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showSettings) {
            R2BucketSettingsView(bucket: bucket, session: session, canWrite: canWrite)
        }
        .confirmationDialog(
            "删除对象",
            isPresented: .init(
                get: { objectToDelete != nil },
                set: { if !$0 { objectToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let object = objectToDelete {
                Button("删除 \(object.key)", role: .destructive) {
                    Task { _ = await viewModel.delete(key: object.key) }
                }
            }
        } message: {
            Text("此操作不可撤销。")
        }
        .alert("权限不足", isPresented: $showDenied) {
            Button("好", role: .cancel) {}
        } message: {
            Text("当前授权未包含 R2 写权限（workers-r2.write）。\n请在设置中退出登录后重新授权以启用此功能。")
        }
        .alert("出错了", isPresented: .init(
            get: { viewModel.error != nil && selectedObject == nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            apiErrorDocButton(for: viewModel.error)
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.error ?? "")
        }
        .sensoryFeedback(.success, trigger: viewModel.didUpload)
        .sensoryFeedback(.success, trigger: viewModel.didTransfer)
        .sheet(item: $transferTarget) { request in
            R2TransferSheet(object: request.object, mode: request.mode) { destinationKey in
                Task {
                    switch request.mode {
                    case .copy: _ = await viewModel.copyObject(request.object, to: destinationKey)
                    case .move: _ = await viewModel.moveObject(request.object, to: destinationKey)
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .alert("对象过大", isPresented: $showTooLarge) {
            Button("好", role: .cancel) {}
        } message: {
            Text("Cloudflare API 单次上传上限约 300 MB，超过的对象无法在 App 内复制或移动。")
        }
        .overlay {
            if viewModel.isTransferring {
                TransferProgressOverlay(
                    label: viewModel.transferLabel ?? String(localized: "处理中…"),
                    progress: viewModel.transferProgress
                )
            }
        }
    }

    /// 发起复制 / 移动：先过写权限与 300MB 体积守卫，再弹目标 Key 编辑表单
    private func startTransfer(_ object: R2Object, _ mode: TransferRequest.Mode) {
        guard canWrite else { showDenied = true; return }
        guard viewModel.canTransfer(object) else { showTooLarge = true; return }
        transferTarget = TransferRequest(object: object, mode: mode)
    }

    /// 可预览：50 MB 以内（QuickLook 需要完整下载）
    private func previewable(_ object: R2Object) -> Bool {
        (object.size ?? 0) <= 50_000_000
    }

    /// 点击对象：可预览的直接下载打开，超限的退回详情页
    private func open(_ object: R2Object) {
        guard previewable(object) else {
            selectedObject = object
            return
        }
        guard !viewModel.isDownloading else { return }
        Task {
            previewURL = await viewModel.downloadToTemp(object: object)
        }
    }

    private var objectList: some View {
        List {
            folderRows
            ForEach(viewModel.objects) { object in
                HStack(spacing: 8) {
                    Button {
                        open(object)
                    } label: {
                        R2ObjectRow(object: object)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.primary)

                    Button {
                        selectedObject = object
                    } label: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(Color.ocOrangeText)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("详细信息")
                }
                .contextMenu {
                    if previewable(object) {
                        Button {
                            open(object)
                        } label: {
                            Label("预览", systemImage: "eye")
                        }
                    }
                    Button {
                        selectedObject = object
                    } label: {
                        Label("详情", systemImage: "info.circle")
                    }
                    Button {
                        startTransfer(object, .copy)
                    } label: {
                        Label("复制", systemImage: "doc.on.doc")
                    }
                    Button {
                        startTransfer(object, .move)
                    } label: {
                        Label("移动 / 重命名", systemImage: "folder")
                    }
                    Button(role: .destructive) {
                        if canWrite {
                            objectToDelete = object
                        } else {
                            showDenied = true
                        }
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        if canWrite {
                            objectToDelete = object
                        } else {
                            showDenied = true
                        }
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
                .glassRow()
            }
            if viewModel.hasMore {
                Button {
                    Task { await viewModel.loadMore() }
                } label: {
                    if viewModel.isLoadingMore {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("加载更多").frame(maxWidth: .infinity)
                    }
                }
                .glassRow()
            }
        }
        .scrollContentBackground(.hidden)
        .refreshable { await viewModel.load() }
    }

    /// 文件夹行：非根层先放「..」上级，再列出当前层的子文件夹
    @ViewBuilder
    private var folderRows: some View {
        if !viewModel.currentPrefix.isEmpty {
            Button {
                Task { await viewModel.openParentFolder() }
            } label: {
                R2FolderRow(title: "..", subtitle: String(localized: "上级文件夹"), systemImage: "arrow.up")
            }
            .buttonStyle(.plain)
            .glassRow()
        }
        ForEach(viewModel.folders) { folder in
            Button {
                Task { await viewModel.open(folder: folder) }
            } label: {
                R2FolderRow(title: folder.name, subtitle: nil)
            }
            .buttonStyle(.plain)
            .glassRow()
        }
    }

    // MARK: - 上传

    private func uploadPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        let type = item.supportedContentTypes.first
        let ext = type?.preferredFilenameExtension ?? "bin"
        let mime = type?.preferredMIMEType ?? "application/octet-stream"
        let name = "upload-\(Date().formatted(.iso8601.year().month().day().timeSeparator(.omitted).time(includingFractionalSeconds: false))).\(ext)"
        _ = await viewModel.upload(data: data, filename: name, contentType: mime)
    }

    private func uploadFile(_ url: URL) async {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
            ?? "application/octet-stream"
        _ = await viewModel.upload(data: data, filename: url.lastPathComponent, contentType: mime)
    }
}

private struct R2FolderRow: View {
    let title: String
    let subtitle: String?
    var systemImage: String = "folder"

    var body: some View {
        HStack(spacing: 12) {
            TintIcon(systemImage: systemImage, color: .ocOrange, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

private struct R2ObjectRow: View {
    let object: R2Object

    private var icon: String {
        let ext = (object.key as NSString).pathExtension.lowercased()
        if let type = UTType(filenameExtension: ext) {
            if type.conforms(to: .image) { return "photo" }
            if type.conforms(to: .movie) || type.conforms(to: .video) { return "film" }
            if type.conforms(to: .audio) { return "waveform" }
            if type.conforms(to: .pdf) { return "doc.richtext" }
            if type.conforms(to: .text) { return "doc.text" }
        }
        return "doc"
    }

    var body: some View {
        HStack(spacing: 12) {
            TintIcon(systemImage: icon, color: .ocOrange, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(object.key)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    if let size = object.size {
                        Text(Int64(size).ocBytes)
                    }
                    if let modified = WorkerScript.parseDate(object.lastModified) {
                        Text(modified, format: .relative(presentation: .named))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }
}

// MARK: - 对象详情（元数据 + QuickLook 预览 + 删除）

private struct R2ObjectDetailView: View {

    let object: R2Object
    let viewModel: R2ObjectListViewModel
    let canWrite: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var previewURL: URL?
    @State private var showDeleteConfirm = false

    /// 预览大小阈值：50 MB
    private var previewable: Bool {
        (object.size ?? 0) <= 50_000_000
    }

    var body: some View {
        NavigationStack {
            List {
                Section("对象") {
                    LabeledContent("Key") {
                        Text(object.key)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .multilineTextAlignment(.trailing)
                    }
                    if let size = object.size {
                        LabeledContent("大小", value: Int64(size).ocBytes)
                    }
                    if let contentType = object.httpMetadata?.contentType {
                        LabeledContent("Content-Type", value: contentType)
                    }
                    if let storageClass = object.storageClass {
                        LabeledContent("存储类型", value: storageClass)
                    }
                    if let etag = object.etag {
                        LabeledContent("ETag") {
                            Text(etag)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                    if let modified = WorkerScript.parseDate(object.lastModified) {
                        LabeledContent("修改时间") {
                            Text(modified, format: .dateTime.year().month().day().hour().minute())
                        }
                    }
                }

                Section {
                    Button {
                        Task {
                            previewURL = await viewModel.downloadToTemp(object: object)
                        }
                    } label: {
                        HStack {
                            Label("预览", systemImage: "eye")
                            Spacer()
                            if viewModel.isDownloading {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(!previewable || viewModel.isDownloading)

                    if canWrite {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("删除对象", systemImage: "trash")
                        }
                    }
                } footer: {
                    if !previewable {
                        Text("超过 50 MB 的对象暂不支持在 App 内预览。")
                    } else {
                        Text("图片、视频、PDF、Office 文档等均可预览（QuickLook）。")
                    }
                }
            }
            .navigationTitle("对象详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .quickLookPreview($previewURL)
            .confirmationDialog("删除对象？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("删除 \(object.key)", role: .destructive) {
                    Task {
                        if await viewModel.delete(key: object.key) {
                            dismiss()
                        }
                    }
                }
            } message: {
                Text("此操作不可撤销。")
            }
        }
    }
}

// MARK: - 复制 / 移动

private struct TransferRequest: Identifiable {
    enum Mode { case copy, move }
    let id = UUID()
    let object: R2Object
    let mode: Mode
}

/// 复制 / 移动目标 Key 编辑表单。仅收集目标 Key 后回调，真正的传输由列表持有 Task 执行，
/// 这样关掉表单后进度仍在列表（前台）或系统 UI（iOS 26 后台）里继续。
private struct R2TransferSheet: View {

    let object: R2Object
    let mode: TransferRequest.Mode
    let onConfirm: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var destinationKey: String

    init(object: R2Object, mode: TransferRequest.Mode, onConfirm: @escaping (String) -> Void) {
        self.object = object
        self.mode = mode
        self.onConfirm = onConfirm
        _destinationKey = State(initialValue: mode == .copy ? Self.copyName(of: object.key) : object.key)
    }

    private var title: String { mode == .copy ? String(localized: "复制对象") : String(localized: "移动 / 重命名") }
    private var actionLabel: String { mode == .copy ? String(localized: "复制") : String(localized: "移动") }
    private var trimmed: String { destinationKey.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isValid: Bool { !trimmed.isEmpty && trimmed != object.key }

    var body: some View {
        NavigationStack {
            Form {
                Section("源对象") {
                    Text(object.key)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Section {
                    TextField("目标 Key", text: $destinationKey, axis: .vertical)
                        .font(.callout.monospaced())
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text(mode == .copy ? "复制为" : "新名称")
                } footer: {
                    Text("Key 可包含 / 表示文件夹层级。超过 300 MB 的对象受 API 限制不可复制 / 移动。")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(actionLabel) {
                        onConfirm(trimmed)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }

    /// 复制默认名：在扩展名前插入「-副本」（无扩展名则末尾追加）
    private static func copyName(of key: String) -> String {
        let suffix = String(localized: "-副本")
        let ns = key as NSString
        let ext = ns.pathExtension
        guard !ext.isEmpty else { return key + suffix }
        return "\(ns.deletingPathExtension)\(suffix).\(ext)"
    }
}

/// 前台传输进度浮层（iOS 26 后台路径由系统 UI 接管，不会用到此浮层）
private struct TransferProgressOverlay: View {
    let label: String
    let progress: Double

    var body: some View {
        ZStack {
            Color.black.opacity(0.15).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.ocOrange)
                    .frame(width: 200)
                Text(label)
                    .font(.callout)
                Text(progress.formatted(.percent.precision(.fractionLength(0))))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(22)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}
