//
//  FileProviderIdentifierStore.swift
//  Orange Cloud File
//
//  v1.1 改名/移动的地基：稳定标识 ↔ 当前 R2 key/prefix 的持久化双向映射。
//  v1 用「key 即标识」，改名后 key 变标识就漂移，违反 FileProvider「标识终身不变」契约。
//  这里给每个文件/文件夹铸一个稳定 UUID 标识（文件 `F-…`、文件夹 `D-…`，根仍 .rootContainer），
//  改名/移动只改映射里的路径、标识不动。映射按桶存一份 JSON 到 App Group 容器，跨进程存活。
//
//  说明：映射随枚举过的对象增长，超大桶会偏大（v1.1 已知限制，后续可换增量存储）。
//

import Foundation

actor FileProviderIdentifierStore {

    static let filePrefix = "F-"
    static let folderPrefix = "D-"
    private static let appGroup = "group.jiamin.chen.Orange-Cloud"

    private let fileURL: URL
    private var files: [String: String] = [:]      // id -> key
    private var folders: [String: String] = [:]    // id -> prefix(以 / 结尾)
    private var keyToFileID: [String: String] = [:]
    private var prefixToFolderID: [String: String] = [:]
    private var loaded = false

    init(accountId: String, bucketName: String, jurisdiction: String? = nil) {
        let base = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: Self.appGroup)?
            .appendingPathComponent("FileProviderMaps", isDirectory: true)
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        // accountId 是十六进制、bucket 仅 [a-z0-9-]，直接拼文件名安全。
        // 区域限制桶追加辖区（同名桶在不同辖区是两个桶，映射不能共用）；默认辖区沿用老文件名
        let suffix = jurisdiction.map { "__\($0)" } ?? ""
        self.fileURL = base.appendingPathComponent("\(accountId)__\(bucketName)\(suffix).json")
    }

    // MARK: - 标识种类（仅看前缀，无需查表）

    enum Kind { case root, folder, file }

    nonisolated static func kind(of identifier: String) -> Kind {
        if identifier.hasPrefix(folderPrefix) { return .folder }
        if identifier.hasPrefix(filePrefix) { return .file }
        return .root   // .rootContainer 等
    }

    // MARK: - 取/铸标识

    func fileID(forKey key: String) -> String {
        ensureLoaded()
        if let id = keyToFileID[key] { return id }
        let id = Self.filePrefix + UUID().uuidString
        files[id] = key
        keyToFileID[key] = id
        persist()
        return id
    }

    func folderID(forPrefix prefix: String) -> String {
        ensureLoaded()
        if let id = prefixToFolderID[prefix] { return id }
        let id = Self.folderPrefix + UUID().uuidString
        folders[id] = prefix
        prefixToFolderID[prefix] = id
        persist()
        return id
    }

    func key(forFileID id: String) -> String? {
        ensureLoaded(); return files[id]
    }

    func prefix(forFolderID id: String) -> String? {
        ensureLoaded(); return folders[id]
    }

    // MARK: - 改名/移动后的映射维护

    /// 文件改 key（标识不变）
    func renameFile(id: String, toKey newKey: String) {
        ensureLoaded()
        if let old = files[id] { keyToFileID[old] = nil }
        files[id] = newKey
        keyToFileID[newKey] = id
        persist()
    }

    /// 文件夹整子树改前缀：folderID 自身 + 所有后代（文件与子文件夹）路径批量改写
    func renameFolderSubtree(folderID: String, oldPrefix: String, newPrefix: String) {
        ensureLoaded()
        for (id, key) in files where key.hasPrefix(oldPrefix) {
            files[id] = newPrefix + key.dropFirst(oldPrefix.count)
        }
        for (id, prefix) in folders where prefix.hasPrefix(oldPrefix) {
            folders[id] = newPrefix + prefix.dropFirst(oldPrefix.count)
        }
        rebuildReverseIndex()
        persist()
    }

    // MARK: - 删除后清理

    func removeFile(id: String) {
        ensureLoaded()
        if let key = files[id] { keyToFileID[key] = nil }
        files[id] = nil
        persist()
    }

    /// 删除文件夹：清掉该前缀下所有文件与子文件夹（含自身）的映射
    func removeFolderSubtree(prefix: String) {
        ensureLoaded()
        files = files.filter { !$0.value.hasPrefix(prefix) }
        folders = folders.filter { !$0.value.hasPrefix(prefix) }
        rebuildReverseIndex()
        persist()
    }

    // MARK: - 持久化

    private struct Persisted: Codable {
        var files: [String: String]
        var folders: [String: String]
    }

    private func ensureLoaded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(Persisted.self, from: data) else { return }
        files = decoded.files
        folders = decoded.folders
        rebuildReverseIndex()
    }

    private func rebuildReverseIndex() {
        keyToFileID = Dictionary(files.map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        prefixToFolderID = Dictionary(folders.map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(Persisted(files: files, folders: folders)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
