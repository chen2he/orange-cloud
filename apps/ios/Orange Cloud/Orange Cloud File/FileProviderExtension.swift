//
//  FileProviderExtension.swift
//  Orange Cloud File
//
//  把一个 R2 存储桶呈现为系统「文件」App 里的 NSFileProviderReplicatedExtension。
//  domain identifier 编码 sessionId|accountId|bucketName[|jurisdiction]，init 解析后构造 R2 客户端
//  （自共享 Keychain 取 token）+ 标识映射存储（[[FileProviderIdentifierStore]]）。
//  第四段是区域限制桶的辖区（eu / us / fedramp…），客户端据此给每个请求带 cf-r2-jurisdiction 头。
//
//  v1.1 能力：枚举 / 读取 / 新建文件夹 / 上传 / 改写内容 / 删除 / **改名 / 移动**。
//  改名移动靠稳定标识映射：标识不变，只改映射里的 R2 key/prefix；R2 无原子 rename，
//  实际是 copy(过设备)+delete，文件夹则整子树重写（先 copy 全部、再删源，失败回滚）。
//  单对象 > ~300MB 受 client/v4 限制（无 multipart），以 .cannotSynchronize 明确拒绝。
//

import FileProvider
import UniformTypeIdentifiers

final class FileProviderExtension: NSObject, NSFileProviderReplicatedExtension {

    private let client: R2FileProviderClient?
    private let store: FileProviderIdentifierStore?
    private let bucketName: String

    required init(domain: NSFileProviderDomain) {
        if let parsed = Self.parseDomain(domain.identifier.rawValue) {
            self.client = R2FileProviderClient(credentials: .init(
                sessionId: parsed.sessionId, accountId: parsed.accountId, bucketName: parsed.bucketName,
                jurisdiction: parsed.jurisdiction
            ))
            self.store = FileProviderIdentifierStore(
                accountId: parsed.accountId, bucketName: parsed.bucketName, jurisdiction: parsed.jurisdiction
            )
            self.bucketName = parsed.bucketName
        } else {
            self.client = nil
            self.store = nil
            self.bucketName = ""
        }
        super.init()
    }

    func invalidate() {}

    // MARK: - 单项查询

    func item(for identifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest, completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) -> Progress {
        guard let client, let store else {
            completionHandler(nil, NSFileProviderError(.notAuthenticated)); return Progress()
        }
        if identifier == .rootContainer {
            completionHandler(rootItem(), nil); return Progress()
        }
        Task {
            do {
                switch FileProviderIdentifierStore.kind(of: identifier.rawValue) {
                case .root:
                    completionHandler(self.rootItem(), nil)
                case .folder:
                    guard let prefix = await store.prefix(forFolderID: identifier.rawValue) else {
                        completionHandler(nil, NSFileProviderError(.noSuchItem)); return
                    }
                    completionHandler(await self.folderItem(id: identifier, prefix: prefix), nil)
                case .file:
                    guard let key = await store.key(forFileID: identifier.rawValue) else {
                        completionHandler(nil, NSFileProviderError(.noSuchItem)); return
                    }
                    guard let object = try await client.head(key: key) else {
                        await store.removeFile(id: identifier.rawValue)   // 服务端已不存在 → 清映射
                        completionHandler(nil, NSFileProviderError(.noSuchItem)); return
                    }
                    completionHandler(await self.fileItem(id: identifier, object: object), nil)
                }
            } catch {
                completionHandler(nil, Self.mapError(error))
            }
        }
        return Progress()
    }

    // MARK: - 取内容（下载）

    func fetchContents(for itemIdentifier: NSFileProviderItemIdentifier, version requestedVersion: NSFileProviderItemVersion?, request: NSFileProviderRequest, completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void) -> Progress {
        guard let client, let store else {
            completionHandler(nil, nil, NSFileProviderError(.notAuthenticated)); return Progress()
        }
        guard FileProviderIdentifierStore.kind(of: itemIdentifier.rawValue) == .file else {
            completionHandler(nil, nil, NSFileProviderError(.noSuchItem)); return Progress()
        }
        Task {
            do {
                guard let key = await store.key(forFileID: itemIdentifier.rawValue) else {
                    completionHandler(nil, nil, NSFileProviderError(.noSuchItem)); return
                }
                let url = try await client.download(key: key)
                let object = (try? await client.head(key: key))
                    ?? R2FileProviderClient.R2Obj(key: key, size: nil, etag: nil, lastModified: nil, contentType: nil)
                completionHandler(url, await self.fileItem(id: itemIdentifier, object: object), nil)
            } catch {
                completionHandler(nil, nil, Self.mapError(error))
            }
        }
        return Progress()
    }

    // MARK: - 新建（上传文件 / 新建文件夹）

    func createItem(basedOn itemTemplate: NSFileProviderItem, fields: NSFileProviderItemFields, contents url: URL?, options: NSFileProviderCreateItemOptions = [], request: NSFileProviderRequest, completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        guard let client, let store else {
            completionHandler(nil, [], false, NSFileProviderError(.notAuthenticated)); return Progress()
        }
        let filename = itemTemplate.filename
        let isFolder = itemTemplate.contentType == .folder

        Task {
            do {
                let parentPrefix = await self.prefix(ofContainer: itemTemplate.parentItemIdentifier, store: store)
                if isFolder {
                    let newPrefix = parentPrefix + filename + "/"
                    try await client.putFolderMarker(prefix: newPrefix)
                    let id = await store.folderID(forPrefix: newPrefix)
                    completionHandler(await self.folderItem(id: NSFileProviderItemIdentifier(id), prefix: newPrefix), [], false, nil)
                } else {
                    guard let url else {
                        completionHandler(nil, [], false, NSFileProviderError(.noSuchItem)); return
                    }
                    let key = parentPrefix + filename
                    let contentType = Self.mimeType(for: filename)
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    try await client.put(key: key, fileURL: url, contentType: contentType)
                    let id = await store.fileID(forKey: key)
                    let object = (try? await client.head(key: key))
                        ?? R2FileProviderClient.R2Obj(key: key, size: nil, etag: nil, lastModified: Date(), contentType: contentType)
                    completionHandler(await self.fileItem(id: NSFileProviderItemIdentifier(id), object: object), [], false, nil)
                }
            } catch {
                completionHandler(nil, [], false, Self.mapError(error))
            }
        }
        return Progress()
    }

    // MARK: - 修改（改写内容 + 改名 / 移动）

    func modifyItem(_ item: NSFileProviderItem, baseVersion version: NSFileProviderItemVersion, changedFields: NSFileProviderItemFields, contents newContents: URL?, options: NSFileProviderModifyItemOptions = [], request: NSFileProviderRequest, completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        guard let client, let store else {
            completionHandler(nil, [], false, NSFileProviderError(.notAuthenticated)); return Progress()
        }
        let identifier = item.itemIdentifier
        let kind = FileProviderIdentifierStore.kind(of: identifier.rawValue)

        Task {
            do {
                switch kind {
                case .file:
                    try await self.modifyFile(item: item, identifier: identifier,
                                              changedFields: changedFields, newContents: newContents,
                                              client: client, store: store, completionHandler: completionHandler)
                case .folder:
                    try await self.modifyFolder(item: item, identifier: identifier,
                                                changedFields: changedFields,
                                                client: client, store: store, completionHandler: completionHandler)
                case .root:
                    completionHandler(self.rootItem(), [], false, nil)
                }
            } catch {
                completionHandler(nil, [], false, Self.mapError(error))
            }
        }
        return Progress()
    }

    private func modifyFile(item: NSFileProviderItem, identifier: NSFileProviderItemIdentifier,
                            changedFields: NSFileProviderItemFields, newContents: URL?,
                            client: R2FileProviderClient, store: FileProviderIdentifierStore,
                            completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) async throws {
        guard let oldKey = await store.key(forFileID: identifier.rawValue) else {
            completionHandler(nil, [], false, NSFileProviderError(.noSuchItem)); return
        }
        let parentPrefix = changedFields.contains(.parentItemIdentifier)
            ? await self.prefix(ofContainer: item.parentItemIdentifier, store: store)
            : FileProviderItem.parentPrefix(of: oldKey)
        let name = changedFields.contains(.filename) ? item.filename : FileProviderItem.lastComponent(oldKey)
        let finalKey = parentPrefix + name

        if changedFields.contains(.contents), let newContents {
            // 内容改写（可能同时改名/移动）：直接写到目标 key，再删旧 key
            let contentType = Self.mimeType(for: name)
            let accessing = newContents.startAccessingSecurityScopedResource()
            defer { if accessing { newContents.stopAccessingSecurityScopedResource() } }
            try await client.put(key: finalKey, fileURL: newContents, contentType: contentType)
            if finalKey != oldKey { try await client.delete(key: oldKey) }
        } else if finalKey != oldKey {
            // 纯改名/移动：copy + delete（先校验体积，避免下到一半才失败）
            if let size = (try await client.head(key: oldKey))?.size, size > R2FileProviderClient.maxUploadBytes {
                throw R2FileProviderClient.ClientError.tooLarge
            }
            try await client.copy(sourceKey: oldKey, destinationKey: finalKey)
            try await client.delete(key: oldKey)
        }

        if finalKey != oldKey { await store.renameFile(id: identifier.rawValue, toKey: finalKey) }
        let object = (try? await client.head(key: finalKey))
            ?? R2FileProviderClient.R2Obj(key: finalKey, size: nil, etag: nil, lastModified: Date(), contentType: nil)
        completionHandler(await self.fileItem(id: identifier, object: object), [], false, nil)
    }

    private func modifyFolder(item: NSFileProviderItem, identifier: NSFileProviderItemIdentifier,
                              changedFields: NSFileProviderItemFields,
                              client: R2FileProviderClient, store: FileProviderIdentifierStore,
                              completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) async throws {
        guard let oldPrefix = await store.prefix(forFolderID: identifier.rawValue) else {
            completionHandler(nil, [], false, NSFileProviderError(.noSuchItem)); return
        }
        let parentPrefix = changedFields.contains(.parentItemIdentifier)
            ? await self.prefix(ofContainer: item.parentItemIdentifier, store: store)
            : FileProviderItem.parentPrefix(of: oldPrefix)
        let name = changedFields.contains(.filename) ? item.filename : FileProviderItem.lastComponent(oldPrefix)
        let newPrefix = parentPrefix + name + "/"

        if newPrefix != oldPrefix {
            // 整子树重写：先把整棵树 copy 到新前缀，再删源；任一 copy 失败回滚已建副本
            let all = try await client.listAll(prefix: oldPrefix)
            if all.contains(where: { $0.size > R2FileProviderClient.maxUploadBytes }) {
                throw R2FileProviderClient.ClientError.tooLarge
            }
            var copied: [String] = []
            do {
                for (key, _) in all {
                    let newKey = newPrefix + key.dropFirst(oldPrefix.count)
                    try await client.copy(sourceKey: key, destinationKey: newKey)
                    copied.append(newKey)
                }
            } catch {
                for newKey in copied { try? await client.delete(key: newKey) }   // 回滚
                throw error
            }
            for (key, _) in all { try? await client.delete(key: key) }
            await store.renameFolderSubtree(folderID: identifier.rawValue, oldPrefix: oldPrefix, newPrefix: newPrefix)
        }
        completionHandler(await self.folderItem(id: identifier, prefix: newPrefix), [], false, nil)
    }

    // MARK: - 删除

    func deleteItem(identifier: NSFileProviderItemIdentifier, baseVersion version: NSFileProviderItemVersion, options: NSFileProviderDeleteItemOptions = [], request: NSFileProviderRequest, completionHandler: @escaping (Error?) -> Void) -> Progress {
        guard let client, let store else {
            completionHandler(NSFileProviderError(.notAuthenticated)); return Progress()
        }
        Task {
            do {
                switch FileProviderIdentifierStore.kind(of: identifier.rawValue) {
                case .file:
                    if let key = await store.key(forFileID: identifier.rawValue) {
                        try await client.delete(key: key)
                        await store.removeFile(id: identifier.rawValue)
                    }
                case .folder:
                    if let prefix = await store.prefix(forFolderID: identifier.rawValue) {
                        try await client.deletePrefix(prefix)
                        await store.removeFolderSubtree(prefix: prefix)
                    }
                case .root:
                    break
                }
                completionHandler(nil)
            } catch {
                completionHandler(Self.mapError(error))
            }
        }
        return Progress()
    }

    // MARK: - 枚举器

    func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest) throws -> NSFileProviderEnumerator {
        FileProviderEnumerator(containerIdentifier: containerItemIdentifier, client: client, store: store)
    }

    // MARK: - Item 构造

    private func rootItem() -> FileProviderItem {
        FileProviderItem(id: .rootContainer, parentID: .rootContainer, filename: bucketName, content: .root(bucketName: bucketName))
    }

    private func folderItem(id: NSFileProviderItemIdentifier, prefix: String) async -> FileProviderItem {
        let parentID = await parentIdentifier(forPath: prefix)
        return FileProviderItem(id: id, parentID: parentID, filename: FileProviderItem.lastComponent(prefix), content: .folder(prefix: prefix))
    }

    private func fileItem(id: NSFileProviderItemIdentifier, object: R2FileProviderClient.R2Obj) async -> FileProviderItem {
        let parentID = await parentIdentifier(forPath: object.key)
        return FileProviderItem(id: id, parentID: parentID, filename: FileProviderItem.lastComponent(object.key), content: .file(object))
    }

    /// 某 key/prefix 的父容器标识（根 → .rootContainer，否则取/铸父文件夹标识）
    private func parentIdentifier(forPath path: String) async -> NSFileProviderItemIdentifier {
        let pp = FileProviderItem.parentPrefix(of: path)
        guard !pp.isEmpty, let store else { return .rootContainer }
        return NSFileProviderItemIdentifier(await store.folderID(forPrefix: pp))
    }

    /// 容器标识 → R2 前缀（根 ""，文件夹查映射）
    private func prefix(ofContainer identifier: NSFileProviderItemIdentifier, store: FileProviderIdentifierStore) async -> String {
        if identifier == .rootContainer { return "" }
        if FileProviderIdentifierStore.kind(of: identifier.rawValue) == .folder {
            return await store.prefix(forFolderID: identifier.rawValue) ?? ""
        }
        return ""
    }

    // MARK: - 辅助

    private static func mimeType(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension
        if !ext.isEmpty, let type = UTType(filenameExtension: ext), let mime = type.preferredMIMEType {
            return mime
        }
        return "application/octet-stream"
    }

    /// 与主 App Shared/FileProviderDomainID.parse 同口径（extension 不编译 Shared）：
    /// 三段 = 默认辖区；第四段为区域限制桶的辖区，空 / default 视同默认。
    private static func parseDomain(_ identifier: String) -> (sessionId: UUID, accountId: String, bucketName: String, jurisdiction: String?)? {
        let parts = identifier.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3 || parts.count == 4, let sessionId = UUID(uuidString: parts[0]),
              !parts[1].isEmpty, !parts[2].isEmpty else { return nil }
        var jurisdiction: String?
        if parts.count == 4 {
            let value = parts[3].trimmingCharacters(in: .whitespaces).lowercased()
            jurisdiction = (value.isEmpty || value == "default") ? nil : value
        }
        return (sessionId, parts[1], parts[2], jurisdiction)
    }

    private static func mapError(_ error: Error) -> Error {
        guard let clientError = error as? R2FileProviderClient.ClientError else { return error }
        switch clientError {
        case .notAuthenticated:
            return NSFileProviderError(.notAuthenticated)
        case .tooLarge:
            return NSError(domain: NSFileProviderError.errorDomain,
                           code: NSFileProviderError.cannotSynchronize.rawValue,
                           userInfo: [NSLocalizedDescriptionKey: "文件超过约 300 MB，Cloudflare API 无法分片上传，请用更小的文件。"])
        case .http(let status) where status == 404:
            return NSFileProviderError(.noSuchItem)
        case .http, .badResponse:
            return NSFileProviderError(.serverUnreachable)
        }
    }
}
