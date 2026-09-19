package jiamin.chen.orangecloud.core.network

import jiamin.chen.orangecloud.core.logging.AppLog
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.KSerializer
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.serializer
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.asRequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.File
import java.io.IOException
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

/**
 * 所有 Cloudflare API 调用的统一入口（对应 iOS Core/Network/CFAPIClient.swift）。
 * 自动注入 Bearer、临期主动刷新、401 刷新后重试一次、统一错误解析。
 *
 * path 视为已编码：KV key 等特殊字符由调用方预先百分号编码，直接拼到 baseURL 后。
 */
@Singleton
class CfApiClient @Inject constructor(
    private val httpClient: OkHttpClient,
    @PublishedApi internal val json: Json,
    private val tokenProvider: AccessTokenProvider,
) {

    suspend inline fun <reified T> get(path: String, query: List<Pair<String, String>> = emptyList()): T {
        val bytes = executeRaw("GET", path, query, null, JSON_MEDIA_TYPE)
        return decodeResult(bytes, serializer<T>())
    }

    /** 列表端点：返回数据 + 分页信息（result_info） */
    suspend inline fun <reified T> getList(path: String, query: List<Pair<String, String>> = emptyList()): Paged<T> {
        val bytes = executeRaw("GET", path, query, null, JSON_MEDIA_TYPE)
        val env = json.decodeFromString(CfEnvelope.serializer(ListSerializer(serializer<T>())), bytes.decodeToString())
        if (!env.success) throw ApiError.Cloudflare(env.errors.map { ApiError.CfError(it.code, it.message) })
        return Paged(env.result ?: emptyList(), env.resultInfo)
    }

    suspend inline fun <reified T, reified B> post(path: String, body: B): T {
        val payload = json.encodeToString(serializer<B>(), body).encodeToByteArray()
        return decodeResult(executeRaw("POST", path, emptyList(), payload, JSON_MEDIA_TYPE), serializer<T>())
    }

    suspend inline fun <reified T, reified B> put(path: String, body: B): T {
        val payload = json.encodeToString(serializer<B>(), body).encodeToByteArray()
        return decodeResult(executeRaw("PUT", path, emptyList(), payload, JSON_MEDIA_TYPE), serializer<T>())
    }

    suspend inline fun <reified T, reified B> patch(path: String, body: B): T {
        val payload = json.encodeToString(serializer<B>(), body).encodeToByteArray()
        return decodeResult(executeRaw("PATCH", path, emptyList(), payload, JSON_MEDIA_TYPE), serializer<T>())
    }

    /**
     * 不走 CF 标准信封的 2xx JSON 端点（URL Scanner v2、Email Routing suppression 列表等）：
     * 顶层就是目标对象，没有 success/result 包装。非 2xx 仍由 executeRaw 统一抛错。
     */
    suspend inline fun <reified T> getBare(path: String, query: List<Pair<String, String>> = emptyList()): T {
        val bytes = executeRaw("GET", path, query, null, JSON_MEDIA_TYPE)
        return decodeBare(bytes, serializer<T>())
    }

    suspend inline fun <reified T, reified B> postBare(path: String, body: B): T {
        val payload = json.encodeToString(serializer<B>(), body).encodeToByteArray()
        return decodeBare(executeRaw("POST", path, emptyList(), payload, JSON_MEDIA_TYPE), serializer<T>())
    }

    /** 只关心 success 的请求（DELETE 等）。非 2xx 由 executeRaw 抛错。 */
    suspend fun delete(path: String) {
        executeRaw("DELETE", path, emptyList(), null, JSON_MEDIA_TYPE)
    }

    /** 任意方法 + JSON body 并解码 result（Bulk Redirects 的 DELETE 带 body 等）。 */
    suspend inline fun <reified T, reified B> requestJson(method: String, path: String, body: B): T {
        val payload = json.encodeToString(serializer<B>(), body).encodeToByteArray()
        return decodeResult(executeRaw(method, path, emptyList(), payload, JSON_MEDIA_TYPE), serializer<T>())
    }

    /** 用外部 bearer（Pages 直接上传的短期 JWT）发 JSON 请求，返回原始字节。资源端点用此 JWT 鉴权。 */
    suspend fun bearerJson(method: String, path: String, bearer: String, body: ByteArray): ByteArray {
        val request = Request.Builder()
            .url("$BASE_URL/$path".toHttpUrl())
            .header("Authorization", "Bearer $bearer")
            .method(method, body.toRequestBody(JSON_MEDIA_TYPE.toMediaTypeOrNull()))
            .build()
        val (code, bytes) = try {
            withContext(Dispatchers.IO) {
                httpClient.newCall(request).execute().use { resp ->
                    resp.code to (resp.body?.bytes() ?: ByteArray(0))
                }
            }
        } catch (e: IOException) {
            throw ApiError.Network(e)
        }
        if (code !in 200..299) {
            val cfErrors = runCatching {
                json.decodeFromString(CfEnvelope.serializer(JsonElement.serializer()), bytes.decodeToString()).errors
            }.getOrNull().orEmpty()
            if (cfErrors.isNotEmpty()) throw ApiError.Cloudflare(cfErrors.map { ApiError.CfError(it.code, it.message) })
            throw ApiError.Http(code)
        }
        return bytes
    }

    /** POST multipart 表单字段（Pages 创建部署带 manifest 字段），走 OAuth 鉴权，解码 result。 */
    suspend inline fun <reified T> postMultipart(path: String, fields: Map<String, String>): T {
        val boundary = "OrangeCloud-${UUID.randomUUID()}"
        val bytes = executeRaw("POST", path, emptyList(), buildMultipartBody(boundary, fields), "multipart/form-data; boundary=$boundary")
        return decodeResult(bytes, serializer<T>())
    }

    /** JSON POST，只校验 success（写端点 result 可能为 null，如切换子域）。 */
    suspend inline fun <reified B> postChecked(path: String, body: B) {
        val payload = json.encodeToString(serializer<B>(), body).encodeToByteArray()
        checkSuccess(executeRaw("POST", path, emptyList(), payload, JSON_MEDIA_TYPE))
    }

    /** JSON PUT，只校验 success（写端点 result 可能为 null）。 */
    suspend inline fun <reified B> putChecked(path: String, body: B) {
        val payload = json.encodeToString(serializer<B>(), body).encodeToByteArray()
        checkSuccess(executeRaw("PUT", path, emptyList(), payload, JSON_MEDIA_TYPE))
    }

    /** JSON PATCH，只校验 success（secrets-bulk 等写端点 result 可能为 null）。 */
    suspend inline fun <reified B> patchChecked(path: String, body: B) {
        val payload = json.encodeToString(serializer<B>(), body).encodeToByteArray()
        checkSuccess(executeRaw("PATCH", path, emptyList(), payload, JSON_MEDIA_TYPE))
    }

    /** KV value 等非 JSON 信封端点：返回原始字节 */
    suspend fun getRaw(path: String, query: List<Pair<String, String>> = emptyList()): ByteArray =
        executeRaw("GET", path, query, null, null)

    /** JSON body POST，返回原始字节（Workers AI 文生图直接回图片二进制，不走 JSON 信封解码）。 */
    suspend inline fun <reified B> postRaw(path: String, body: B): ByteArray {
        val payload = json.encodeToString(serializer<B>(), body).encodeToByteArray()
        return executeRaw("POST", path, emptyList(), payload, JSON_MEDIA_TYPE)
    }

    /** 原始字节 PUT（R2 对象上传等），自带 Content-Type */
    suspend inline fun <reified T> putRaw(path: String, body: ByteArray, contentType: String): T =
        decodeResult(executeRaw("PUT", path, emptyList(), body, contentType), serializer<T>())

    /** multipart/form-data 写入（KV 写值要求 value + metadata 两个 part） */
    suspend inline fun <reified T> putMultipart(path: String, fields: Map<String, String>): T {
        val boundary = "OrangeCloud-${UUID.randomUUID()}"
        val bytes = executeRaw("PUT", path, emptyList(), buildMultipartBody(boundary, fields), "multipart/form-data; boundary=$boundary")
        return decodeResult(bytes, serializer<T>())
    }

    /** multipart 写入，只校验 success（KV 写值返回 result=null，不强制解码 result）。 */
    suspend fun putMultipartVoid(path: String, fields: Map<String, String>) {
        val boundary = "OrangeCloud-${UUID.randomUUID()}"
        executeRaw("PUT", path, emptyList(), buildMultipartBody(boundary, fields), "multipart/form-data; boundary=$boundary")
    }

    /** 原始字节 PUT，只校验 success（R2 上传等 result 可能为 null）。 */
    suspend fun putRawVoid(path: String, body: ByteArray, contentType: String) {
        executeRaw("PUT", path, emptyList(), body, contentType)
    }

    /** 流式下载到文件（R2 大对象复制/移动用，避免整体读入内存）。401 刷新重试一次。 */
    suspend fun downloadToFile(path: String, dest: File, isRetry: Boolean = false) {
        val token = tokenProvider.validAccessToken()
        val request = Request.Builder()
            .url("$BASE_URL/$path".toHttpUrl())
            .header("Authorization", "Bearer $token")
            .get()
            .build()
        val code = try {
            withContext(Dispatchers.IO) {
                httpClient.newCall(request).execute().use { resp ->
                    if (resp.isSuccessful) {
                        resp.body?.byteStream()?.use { input -> dest.outputStream().use { input.copyTo(it) } }
                    }
                    resp.code
                }
            }
        } catch (e: IOException) {
            throw ApiError.Network(e)
        }
        if (code == 401 && !isRetry) {
            tokenProvider.refreshAccessToken()
            return downloadToFile(path, dest, isRetry = true)
        }
        if (code !in 200..299) throw ApiError.Http(code)
    }

    /** 流式上传文件（R2 大对象上传/复制），只校验 success。401 刷新重试一次。 */
    suspend fun putFile(path: String, file: File, contentType: String, isRetry: Boolean = false) {
        val token = tokenProvider.validAccessToken()
        val request = Request.Builder()
            .url("$BASE_URL/$path".toHttpUrl())
            .header("Authorization", "Bearer $token")
            .put(file.asRequestBody(contentType.toMediaTypeOrNull()))
            .build()
        val (code, bytes) = try {
            withContext(Dispatchers.IO) {
                httpClient.newCall(request).execute().use { resp -> resp.code to (resp.body?.bytes() ?: ByteArray(0)) }
            }
        } catch (e: IOException) {
            throw ApiError.Network(e)
        }
        if (code == 401 && !isRetry) {
            tokenProvider.refreshAccessToken()
            return putFile(path, file, contentType, isRetry = true)
        }
        if (code !in 200..299) {
            val cfErrors = runCatching {
                json.decodeFromString(CfEnvelope.serializer(JsonElement.serializer()), bytes.decodeToString()).errors
            }.getOrNull().orEmpty()
            if (cfErrors.isNotEmpty()) throw ApiError.Cloudflare(cfErrors.map { ApiError.CfError(it.code, it.message) })
            throw ApiError.Http(code)
        }
    }

    /**
     * 单 JSON part 的 multipart 请求（method 任意），只校验 success。
     * Worker 改设置 PATCH .../settings 用——CF 要求 settings 作为 multipart form part 而非裸 JSON body。
     */
    suspend fun requestMultipartJsonChecked(
        method: String,
        path: String,
        partName: String,
        bodyJson: String,
        query: List<Pair<String, String>> = emptyList(),
    ) {
        val boundary = "OrangeCloud-${UUID.randomUUID()}"
        val sb = StringBuilder()
        sb.append("--").append(boundary).append("\r\n")
        sb.append("Content-Disposition: form-data; name=\"").append(partName).append("\"\r\n")
        sb.append("Content-Type: application/json\r\n\r\n")
        sb.append(bodyJson).append("\r\n")
        sb.append("--").append(boundary).append("--\r\n")
        val bytes = executeRaw(method, path, query, sb.toString().encodeToByteArray(), "multipart/form-data; boundary=$boundary")
        checkSuccess(bytes)
    }

    /** 校验 2xx 响应体信封的 success（HTTP 200 但 success:false 时透出 CF 业务错误）。 */
    @PublishedApi
    internal fun checkSuccess(bytes: ByteArray) {
        val env = runCatching {
            json.decodeFromString(CfEnvelope.serializer(JsonElement.serializer()), bytes.decodeToString())
        }.getOrNull()
        if (env != null && !env.success) {
            throw ApiError.Cloudflare(env.errors.map { ApiError.CfError(it.code, it.message) })
        }
    }

    /** Snippets 创建/更新：multipart 带 metadata part + JS 模块文件 part（application/javascript+module）。 */
    suspend inline fun <reified T> putMultipartFile(
        path: String,
        metadataJson: String,
        fileName: String,
        fileText: String,
        fileContentType: String,
        query: List<Pair<String, String>> = emptyList(),
    ): T {
        val boundary = "OrangeCloud-${UUID.randomUUID()}"
        val body = buildMultipartFileBody(boundary, metadataJson, fileName, fileText, fileContentType)
        val bytes = executeRaw("PUT", path, query, body, "multipart/form-data; boundary=$boundary")
        return decodeResult(bytes, serializer<T>())
    }

    @PublishedApi
    internal fun buildMultipartFileBody(
        boundary: String,
        metadataJson: String,
        fileName: String,
        fileText: String,
        fileContentType: String,
    ): ByteArray {
        val sb = StringBuilder()
        sb.append("--").append(boundary).append("\r\n")
        sb.append("Content-Disposition: form-data; name=\"metadata\"\r\n\r\n")
        sb.append(metadataJson).append("\r\n")
        sb.append("--").append(boundary).append("\r\n")
        sb.append("Content-Disposition: form-data; name=\"").append(fileName).append("\"; filename=\"").append(fileName).append("\"\r\n")
        sb.append("Content-Type: ").append(fileContentType).append("\r\n\r\n")
        sb.append(fileText).append("\r\n")
        sb.append("--").append(boundary).append("--\r\n")
        return sb.toString().encodeToByteArray()
    }

    @PublishedApi
    internal fun buildMultipartBody(boundary: String, fields: Map<String, String>): ByteArray {
        val sb = StringBuilder()
        for ((name, value) in fields) {
            sb.append("--").append(boundary).append("\r\n")
            sb.append("Content-Disposition: form-data; name=\"").append(name).append("\"\r\n\r\n")
            sb.append(value).append("\r\n")
        }
        sb.append("--").append(boundary).append("--\r\n")
        return sb.toString().encodeToByteArray()
    }

    /** GraphQL Analytics：信封 {data, errors}，GraphQL 错误时 HTTP 仍 200 */
    suspend inline fun <reified D, reified V> graphQL(query: String, variables: V): D =
        graphQLAllowingPartialAuthz<D, V>(query, variables).first

    /**
     * 同 graphQL，但把「部分字段 authz、其余字段照常返回」这一情况回给调用方（second = true）。
     *
     * GraphQL 允许错误与数据同时出现——免费账号最典型：today 窗口有数据、month 窗口 authz。
     * 此时 data 已经解出来了，整包丢掉等于把手上的数据扔了（概览用量会整块误降级成
     * 「无账户级数据」）。故：authz 且 data 非空就返回部分数据，只有 data 为空才抛给调用方降级。
     * 非 authz 的错误（查询写错、schema 不支持等）照旧抛出，不静默吞掉。
     */
    suspend inline fun <reified D, reified V> graphQLAllowingPartialAuthz(
        query: String,
        variables: V,
    ): Pair<D, Boolean> {
        val payload = json.encodeToString(GraphQLRequest.serializer(serializer<V>()), GraphQLRequest(query, variables)).encodeToByteArray()
        val bytes = executeRaw("POST", "graphql", emptyList(), payload, JSON_MEDIA_TYPE)
        val env = json.decodeFromString(GraphQLResponse.serializer(serializer<D>()), bytes.decodeToString())
        env.errors.firstOrNull()?.let { first ->
            val data = env.data
            if (env.errors.any { it.isAuthz } && data != null) return data to true
            throw ApiError.Cloudflare(listOf(ApiError.CfError(0, first.message)))
        }
        return (env.data ?: throw ApiError.Decoding(IllegalStateException("GraphQL data missing"))) to false
    }

    // MARK: - 内部实现（@PublishedApi internal 供上方 inline 函数引用）

    @PublishedApi
    internal fun <T> decodeBare(bytes: ByteArray, serializer: KSerializer<T>): T = try {
        json.decodeFromString(serializer, bytes.decodeToString())
    } catch (e: Exception) {
        throw ApiError.Decoding(e)
    }

    @PublishedApi
    internal fun <T> decodeResult(bytes: ByteArray, elementSerializer: KSerializer<T>): T {
        val env = try {
            json.decodeFromString(CfEnvelope.serializer(elementSerializer), bytes.decodeToString())
        } catch (e: Exception) {
            throw ApiError.Decoding(e)
        }
        if (!env.success) throw ApiError.Cloudflare(env.errors.map { ApiError.CfError(it.code, it.message) })
        return env.result ?: throw ApiError.Decoding(IllegalStateException("result missing"))
    }

    /**
     * 对 Cloudflare 系外部主机（如 R2 SQL 的 api.sql.cloudflarestorage.com）发 JSON POST，
     * 复用 OAuth Bearer 与 401 刷新重试，返回 2xx 原始响应体。
     * 注意：这些主机不一定走 client/v4 信封，错误体尽力解析 CF 业务错误。
     */
    suspend fun postExternalJson(url: String, body: ByteArray, isRetry: Boolean = false): ByteArray {
        val token = tokenProvider.validAccessToken()
        val request = Request.Builder()
            .url(url.toHttpUrl())
            .header("Authorization", "Bearer $token")
            .method("POST", body.toRequestBody(JSON_MEDIA_TYPE.toMediaTypeOrNull()))
            .build()
        val (code, bytes) = try {
            withContext(Dispatchers.IO) {
                httpClient.newCall(request).execute().use { resp ->
                    resp.code to (resp.body?.bytes() ?: ByteArray(0))
                }
            }
        } catch (e: IOException) {
            AppLog.network.error("POST $url (external) -> 网络错误: ${e.message}")
            throw ApiError.Network(e)
        }
        AppLog.network.info("POST ${url.toHttpUrl().host} (external) -> $code${if (isRetry) " [retry]" else ""}")
        if (code == 401 && !isRetry) {
            tokenProvider.refreshAccessToken()
            return postExternalJson(url, body, isRetry = true)
        }
        if (code !in 200..299) {
            val cfErrors = runCatching {
                json.decodeFromString(CfEnvelope.serializer(JsonElement.serializer()), bytes.decodeToString()).errors
            }.getOrNull().orEmpty()
            if (cfErrors.isNotEmpty()) throw ApiError.Cloudflare(cfErrors.map { ApiError.CfError(it.code, it.message) })
            if (code == 401) throw ApiError.Unauthorized
            throw ApiError.Http(code)
        }
        return bytes
    }

    @PublishedApi
    internal suspend fun executeRaw(
        method: String,
        path: String,
        query: List<Pair<String, String>>,
        body: ByteArray?,
        contentType: String?,
        isRetry: Boolean = false,
    ): ByteArray {
        val token = tokenProvider.validAccessToken()

        val url = "$BASE_URL/$path".toHttpUrl().newBuilder().apply {
            query.forEach { (k, v) -> addQueryParameter(k, v) }
        }.build()

        val requestBody = if (method == "GET") null
        else (body ?: ByteArray(0)).toRequestBody(contentType?.toMediaTypeOrNull())

        val request = Request.Builder()
            .url(url)
            .header("Authorization", "Bearer $token")
            .method(method, requestBody)
            .build()

        // execute + 读 body 都在 IO 上完成；状态判断与 401 重试留在调用方协程
        // 诊断日志只记 方法/路径/状态/耗时（路径含资源 ID 无妨，绝不含 token / query 值）
        val startMs = System.currentTimeMillis()
        val (code, bytes) = try {
            withContext(Dispatchers.IO) {
                httpClient.newCall(request).execute().use { resp ->
                    resp.code to (resp.body?.bytes() ?: ByteArray(0))
                }
            }
        } catch (e: IOException) {
            AppLog.network.error("$method /$path -> 网络错误: ${e.message}")
            throw ApiError.Network(e)
        }
        AppLog.network.info("$method /$path -> $code (${System.currentTimeMillis() - startMs}ms)${if (isRetry) " [retry]" else ""}")

        // 401：刷新后重试一次
        if (code == 401 && !isRetry) {
            tokenProvider.refreshAccessToken()
            return executeRaw(method, path, query, body, contentType, isRetry = true)
        }

        return when (code) {
            in 200..299 -> bytes
            401 -> throw ApiError.Unauthorized
            else -> {
                // 优先透出 CF 业务错误
                val cfErrors = runCatching {
                    json.decodeFromString(
                        CfEnvelope.serializer(JsonElement.serializer()),
                        bytes.decodeToString(),
                    ).errors
                }.getOrNull().orEmpty()
                if (cfErrors.isNotEmpty()) {
                    throw ApiError.Cloudflare(cfErrors.map { ApiError.CfError(it.code, it.message) })
                }
                throw ApiError.Http(code)
            }
        }
    }

    companion object {
        const val BASE_URL = "https://api.cloudflare.com/client/v4"
        const val JSON_MEDIA_TYPE = "application/json"
    }
}
