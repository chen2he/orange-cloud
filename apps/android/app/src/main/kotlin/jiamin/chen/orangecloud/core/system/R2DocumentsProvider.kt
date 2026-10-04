package jiamin.chen.orangecloud.core.system

import android.database.Cursor
import android.database.MatrixCursor
import android.os.CancellationSignal
import android.os.Handler
import android.os.HandlerThread
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import android.provider.DocumentsContract.Root
import android.provider.DocumentsProvider
import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.android.EntryPointAccessors
import dagger.hilt.components.SingletonComponent
import jiamin.chen.orangecloud.R
import jiamin.chen.orangecloud.core.auth.AuthRepository
import jiamin.chen.orangecloud.core.auth.Scopes
import jiamin.chen.orangecloud.core.logging.AppLog
import jiamin.chen.orangecloud.data.repository.AccountStore
import jiamin.chen.orangecloud.data.repository.StorageRepository
import kotlinx.coroutines.runBlocking
import java.io.File
import java.net.URLConnection

/**
 * 把 R2 对象桥进系统「文件」App（SAF DocumentsProvider，对应 iOS R2 接入文件 App / FileProvider）。
 * 浏览/打开（任意登录态）+ 上传(创建)/改名/移动/删除（需 R2 写权限）。
 * 复用登录态：经 Hilt EntryPoint 拿 StorageRepository / AccountStore / AuthRepository，未登录时无根。
 * 写入走 ParcelFileDescriptor 关闭回调（远端写完临时文件 → 上传 R2）。改名/移动用 字节级 拷贝+删源（跨桶亦可）。
 */
class R2DocumentsProvider : DocumentsProvider() {

    @EntryPoint
    @InstallIn(SingletonComponent::class)
    interface ProviderEntryPoint {
        fun storageRepository(): StorageRepository
        fun accountStore(): AccountStore
        fun authRepository(): AuthRepository
    }

    private val entryPoint by lazy {
        EntryPointAccessors.fromApplication(context!!.applicationContext, ProviderEntryPoint::class.java)
    }
    private val storage: StorageRepository get() = entryPoint.storageRepository()
    private val accounts: AccountStore get() = entryPoint.accountStore()
    private val canWrite: Boolean get() = entryPoint.authRepository().hasScope(Scopes.R2_WRITE)

    /** 上传关闭回调在此后台线程跑（阻塞网络，勿占主线程）。 */
    private val uploadThread by lazy { HandlerThread("r2-upload").apply { start() } }
    private val uploadHandler by lazy { Handler(uploadThread.looper) }

    override fun onCreate(): Boolean = true

    private fun authority(): String = context!!.packageName + ".r2documents"

    private fun currentAccountId(): String? = runCatching {
        runBlocking {
            accounts.ensureLoaded()
            accounts.selectedAccountId.value
        }
    }.getOrNull()

    // MARK: - 查询

    override fun queryRoots(projection: Array<out String>?): Cursor {
        val cursor = MatrixCursor(projection ?: DEFAULT_ROOT_PROJECTION)
        if (currentAccountId() == null) return cursor // 未登录：不暴露根
        cursor.newRow().apply {
            add(Root.COLUMN_ROOT_ID, ROOT_ID)
            add(Root.COLUMN_DOCUMENT_ID, DOC_ROOT)
            add(Root.COLUMN_TITLE, context!!.getString(R.string.r2_provider_root))
            add(Root.COLUMN_FLAGS, if (canWrite) Root.FLAG_SUPPORTS_CREATE else 0)
            add(Root.COLUMN_ICON, R.mipmap.ic_launcher)
        }
        return cursor
    }

    override fun queryDocument(documentId: String, projection: Array<out String>?): Cursor {
        val cursor = MatrixCursor(projection ?: DEFAULT_DOC_PROJECTION)
        when (typeOf(documentId)) {
            T_ROOT -> cursor.addDir(DOC_ROOT, context!!.getString(R.string.r2_provider_root), 0)
            T_BUCKET -> cursor.addDir(documentId, bucketDisplayName(payload(documentId)), bucketFlags())
            T_FOLDER -> {
                val (_, prefix) = bucketAndRest(documentId)
                cursor.addDir(documentId, prefix.trim('/').substringAfterLast('/'), folderFlags())
            }
            T_OBJECT -> {
                val (_, key) = bucketAndRest(documentId)
                cursor.addFile(documentId, key.substringAfterLast('/'), null, objectFlags())
            }
        }
        return cursor
    }

    override fun queryChildDocuments(parentDocumentId: String, projection: Array<out String>?, sortOrder: String?): Cursor {
        val cursor = MatrixCursor(projection ?: DEFAULT_DOC_PROJECTION)
        val accountId = currentAccountId() ?: return cursor
        try {
            when (typeOf(parentDocumentId)) {
                T_ROOT -> runBlocking { storage.listBuckets(accountId) }.forEach { bucket ->
                    val token = bucketToken(bucket.name, bucket.jurisdictionOrNull)
                    cursor.addDir(makeId(T_BUCKET, token, ""), bucketDisplayName(token), bucketFlags())
                }
                T_BUCKET, T_FOLDER -> {
                    val (bucket, prefix) = parentBucketPrefix(parentDocumentId)
                    val page = runBlocking { storage.listObjects(accountId, bucket.bucketName, prefix, null, bucket.bucketJurisdiction) }
                    page.folderPrefixes.toSet().filter { it != prefix }.forEach { p ->
                        cursor.addDir(makeId(T_FOLDER, bucket, p), p.removePrefix(prefix).trim('/'), folderFlags())
                    }
                    page.objects.filter { it.key != prefix && !it.key.endsWith("/") }.forEach { obj ->
                        cursor.addFile(makeId(T_OBJECT, bucket, obj.key), obj.key.removePrefix(prefix).substringAfterLast('/'), obj.size, objectFlags())
                    }
                }
            }
        } catch (e: Exception) {
            AppLog.network.error("R2 provider list 失败: ${e.message}")
        }
        return cursor
    }

    override fun isChildDocument(parentDocumentId: String, documentId: String): Boolean = when (typeOf(parentDocumentId)) {
        T_ROOT -> documentId != DOC_ROOT
        T_BUCKET -> bucketAndRest(documentId).first == payload(parentDocumentId)
        T_FOLDER -> {
            val (pb, pp) = bucketAndRest(parentDocumentId)
            val (cb, ck) = bucketAndRest(documentId)
            cb == pb && ck.startsWith(pp) && ck != pp
        }
        else -> false
    }

    // MARK: - 打开（读 = 下载临时只读；写 = 临时文件关闭后上传）

    override fun openDocument(documentId: String, mode: String, signal: CancellationSignal?): ParcelFileDescriptor {
        require(typeOf(documentId) == T_OBJECT) { "only objects can be opened" }
        val accountId = currentAccountId() ?: throw IllegalStateException("not signed in")
        val (bucket, key) = bucketAndRest(documentId)
        val isWrite = mode.contains('w')
        val temp = File.createTempFile("r2_", "_" + key.substringAfterLast('/').take(40), context!!.cacheDir)

        if (!isWrite) {
            temp.writeBytes(runBlocking { storage.getObjectBytes(accountId, bucket.bucketName, key, bucket.bucketJurisdiction) })
            temp.deleteOnExit()
            return ParcelFileDescriptor.open(temp, ParcelFileDescriptor.MODE_READ_ONLY)
        }

        if (!canWrite) throw IllegalStateException("no write permission")
        // 读改写（rw 非 truncate）先拉现有内容进临时文件
        if (mode.contains('r') && !mode.contains('t')) {
            runCatching { temp.writeBytes(runBlocking { storage.getObjectBytes(accountId, bucket.bucketName, key, bucket.bucketJurisdiction) }) }
        }
        val mime = URLConnection.guessContentTypeFromName(key) ?: "application/octet-stream"
        return ParcelFileDescriptor.open(temp, ParcelFileDescriptor.parseMode(mode), uploadHandler) { err ->
            try {
                if (err == null) {
                    runBlocking { storage.putObject(accountId, bucket.bucketName, key, temp.readBytes(), mime, bucket.bucketJurisdiction) }
                    notifyParentOf(documentId)
                }
            } catch (e: Exception) {
                AppLog.network.error("R2 provider 上传失败: ${e.message}")
            } finally {
                temp.delete()
            }
        }
    }

    // MARK: - 写：创建 / 改名 / 移动 / 删除

    override fun createDocument(parentDocumentId: String, mimeType: String, displayName: String): String {
        if (!canWrite) throw IllegalStateException("no write permission")
        val accountId = currentAccountId() ?: throw IllegalStateException("not signed in")
        val (bucket, prefix) = parentBucketPrefix(parentDocumentId)
        return if (mimeType == Document.MIME_TYPE_DIR) {
            val folderKey = prefix + displayName.trim('/') + "/"
            runBlocking {
                storage.putObject(accountId, bucket.bucketName, folderKey, ByteArray(0), "application/x-directory", bucket.bucketJurisdiction)
            }
            notifyChildren(parentDocumentId)
            makeId(T_FOLDER, bucket, folderKey)
        } else {
            val key = prefix + displayName
            val mime = mimeType.ifBlank { URLConnection.guessContentTypeFromName(displayName) ?: "application/octet-stream" }
            runBlocking { storage.putObject(accountId, bucket.bucketName, key, ByteArray(0), mime, bucket.bucketJurisdiction) }
            notifyChildren(parentDocumentId)
            makeId(T_OBJECT, bucket, key)
        }
    }

    override fun renameDocument(documentId: String, displayName: String): String? {
        if (!canWrite || typeOf(documentId) != T_OBJECT) throw UnsupportedOperationException("rename only objects")
        val accountId = currentAccountId() ?: throw IllegalStateException("not signed in")
        val (bucket, key) = bucketAndRest(documentId)
        val parentPrefix = if (key.contains('/')) key.substringBeforeLast('/') + "/" else ""
        val newKey = parentPrefix + displayName
        if (newKey == key) return documentId
        runBlocking {
            val bytes = storage.getObjectBytes(accountId, bucket.bucketName, key, bucket.bucketJurisdiction)
            storage.putObject(
                accountId, bucket.bucketName, newKey, bytes,
                URLConnection.guessContentTypeFromName(newKey) ?: "application/octet-stream", bucket.bucketJurisdiction,
            )
            storage.deleteObject(accountId, bucket.bucketName, key, bucket.bucketJurisdiction)
        }
        notifyParentOf(documentId)
        return makeId(T_OBJECT, bucket, newKey)
    }

    override fun moveDocument(sourceDocumentId: String, sourceParentDocumentId: String, targetParentDocumentId: String): String? {
        if (!canWrite || typeOf(sourceDocumentId) != T_OBJECT) throw UnsupportedOperationException("move only objects")
        val accountId = currentAccountId() ?: throw IllegalStateException("not signed in")
        val (srcBucket, srcKey) = bucketAndRest(sourceDocumentId)
        val (dstBucket, dstPrefix) = parentBucketPrefix(targetParentDocumentId)
        val newKey = dstPrefix + srcKey.substringAfterLast('/')
        if (dstBucket == srcBucket && newKey == srcKey) return sourceDocumentId
        runBlocking {
            val bytes = storage.getObjectBytes(accountId, srcBucket.bucketName, srcKey, srcBucket.bucketJurisdiction)
            storage.putObject(
                accountId, dstBucket.bucketName, newKey, bytes,
                URLConnection.guessContentTypeFromName(newKey) ?: "application/octet-stream", dstBucket.bucketJurisdiction,
            )
            storage.deleteObject(accountId, srcBucket.bucketName, srcKey, srcBucket.bucketJurisdiction)
        }
        notifyChildren(sourceParentDocumentId)
        notifyChildren(targetParentDocumentId)
        return makeId(T_OBJECT, dstBucket, newKey)
    }

    override fun deleteDocument(documentId: String) {
        if (!canWrite) throw IllegalStateException("no write permission")
        val accountId = currentAccountId() ?: throw IllegalStateException("not signed in")
        val (bucket, rest) = bucketAndRest(documentId)
        runBlocking {
            when (typeOf(documentId)) {
                T_OBJECT -> storage.deleteObject(accountId, bucket.bucketName, rest, bucket.bucketJurisdiction)
                T_FOLDER -> deletePrefix(accountId, bucket, rest)
                else -> Unit
            }
        }
        notifyParentOf(documentId)
    }

    /** 递归删空某前缀下全部对象 + 占位（分页 + 子文件夹），有页数上限防失控。 */
    private suspend fun deletePrefix(accountId: String, bucket: String, prefix: String, depth: Int = 0) {
        if (depth > 16) return
        var cursor: String? = null
        var pages = 0
        do {
            val page = storage.listObjects(accountId, bucket.bucketName, prefix, cursor, bucket.bucketJurisdiction)
            page.objects.forEach { storage.deleteObject(accountId, bucket.bucketName, it.key, bucket.bucketJurisdiction) }
            page.folderPrefixes.toSet().filter { it != prefix }.forEach { deletePrefix(accountId, bucket, it, depth + 1) }
            cursor = page.nextCursor
            pages++
        } while (cursor != null && pages < 100)
        runCatching { storage.deleteObject(accountId, bucket.bucketName, prefix, bucket.bucketJurisdiction) }
    }

    // MARK: - 通知系统刷新

    private fun notifyChildren(parentDocumentId: String) {
        runCatching {
            context!!.contentResolver.notifyChange(
                DocumentsContract.buildChildDocumentsUri(authority(), parentDocumentId), null,
            )
        }
    }

    private fun notifyParentOf(documentId: String) {
        val (bucket, rest) = bucketAndRest(documentId)
        val parentId = if (rest.contains('/')) {
            makeId(T_FOLDER, bucket, rest.substringBeforeLast('/') + "/")
        } else {
            makeId(T_BUCKET, bucket, "")
        }
        notifyChildren(parentId)
    }

    // MARK: - cursor 行

    private fun bucketFlags(): Int = if (canWrite) Document.FLAG_DIR_SUPPORTS_CREATE else 0
    private fun folderFlags(): Int = if (canWrite) Document.FLAG_DIR_SUPPORTS_CREATE or Document.FLAG_SUPPORTS_DELETE else 0
    private fun objectFlags(): Int = if (canWrite) {
        Document.FLAG_SUPPORTS_WRITE or Document.FLAG_SUPPORTS_DELETE or Document.FLAG_SUPPORTS_RENAME or Document.FLAG_SUPPORTS_MOVE or Document.FLAG_SUPPORTS_REMOVE
    } else 0

    private fun MatrixCursor.addDir(id: String, name: String, flags: Int) {
        newRow().apply {
            add(Document.COLUMN_DOCUMENT_ID, id)
            add(Document.COLUMN_DISPLAY_NAME, name)
            add(Document.COLUMN_MIME_TYPE, Document.MIME_TYPE_DIR)
            add(Document.COLUMN_FLAGS, flags)
            add(Document.COLUMN_SIZE, null)
        }
    }

    private fun MatrixCursor.addFile(id: String, name: String, size: Long?, flags: Int) {
        newRow().apply {
            add(Document.COLUMN_DOCUMENT_ID, id)
            add(Document.COLUMN_DISPLAY_NAME, name)
            add(Document.COLUMN_MIME_TYPE, URLConnection.guessContentTypeFromName(name) ?: "application/octet-stream")
            add(Document.COLUMN_FLAGS, flags)
            add(Document.COLUMN_SIZE, size)
        }
    }

    // MARK: - documentId 编码：<type char><bucket> <rest>（空格分隔 bucket 与 key/prefix）
    // 区域限制桶的 bucket 段写作 name@jurisdiction（桶名不允许 @，无歧义）；默认区域仍是裸桶名，
    // 既有文档 ID 不变。桶级调用都靠这个后缀带上 cf-r2-jurisdiction 头。

    private fun bucketToken(name: String, jurisdiction: String?): String =
        if (jurisdiction == null) name else "$name@$jurisdiction"
    private val String.bucketName: String get() = substringBefore('@')
    private val String.bucketJurisdiction: String? get() = substringAfter('@', "").ifEmpty { null }
    /** 同名桶可分属不同区域，文件选择器里用「name (EU)」区分。 */
    private fun bucketDisplayName(token: String): String =
        token.bucketJurisdiction?.let { "${token.bucketName} (${it.uppercase()})" } ?: token.bucketName

    private fun typeOf(id: String): Char = id.firstOrNull() ?: T_ROOT
    private fun makeId(type: Char, bucket: String, rest: String): String = "$type$bucket $rest"
    private fun payload(id: String): String = id.substring(1).substringBefore(' ')
    private fun bucketAndRest(id: String): Pair<String, String> {
        val body = id.substring(1)
        val sep = body.indexOf(' ')
        return if (sep < 0) body to "" else body.substring(0, sep) to body.substring(sep + 1)
    }

    /** 父文档（桶/文件夹）→ (bucket, prefix)，prefix 形如 a/b/ 或 空。 */
    private fun parentBucketPrefix(parentDocumentId: String): Pair<String, String> =
        if (typeOf(parentDocumentId) == T_BUCKET) payload(parentDocumentId) to "" else bucketAndRest(parentDocumentId)

    companion object {
        const val ROOT_ID = "orange-cloud-r2"
        const val DOC_ROOT = "/"
        const val T_ROOT = '/'
        const val T_BUCKET = 'b'
        const val T_FOLDER = 'd'
        const val T_OBJECT = 'o'

        private val DEFAULT_ROOT_PROJECTION = arrayOf(
            Root.COLUMN_ROOT_ID, Root.COLUMN_DOCUMENT_ID, Root.COLUMN_TITLE, Root.COLUMN_FLAGS, Root.COLUMN_ICON,
        )
        private val DEFAULT_DOC_PROJECTION = arrayOf(
            Document.COLUMN_DOCUMENT_ID, Document.COLUMN_DISPLAY_NAME, Document.COLUMN_MIME_TYPE,
            Document.COLUMN_FLAGS, Document.COLUMN_SIZE,
        )
    }
}
