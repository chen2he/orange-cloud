package jiamin.chen.orangecloud.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Workers 脚本管理（源码 / 变量 / 密钥 / 触发器）相关模型（对应 iOS WorkerConfigModels.swift）。
 *
 * GET  /accounts/{a}/workers/scripts/{n}/content/v2  源码（v1 /content 被 OAuth 10405 挡，必须 v2；真机实测 issue #55）
 * PUT  /accounts/{a}/workers/scripts/{n}             上传（multipart：metadata + 模块 part），保留绑定用 inherit
 * GET  /accounts/{a}/workers/scripts/{n}/settings    绑定 + 兼容性日期/标志
 * PATCH .../settings (multipart settings part)        改绑定（变量），其余绑定回传 inherit
 * GET/PUT/DELETE .../secrets                           密钥（仅名+类型，无值）
 * GET/PUT .../schedules                                Cron 触发器（整组替换）
 */

// MARK: - 部署历史

/** 一次部署（GET .../deployments 的 result.deployments 元素）。列表首项为当前活跃部署，不可删。 */
@Serializable
data class WorkerDeployment(
    val id: String,
    @SerialName("created_on") val createdOn: String? = null,
    val source: String? = null,
    @SerialName("author_email") val authorEmail: String? = null,
    val annotations: Map<String, String>? = null,
) {
    /** annotations["workers/message"]（部署备注）。 */
    val message: String? get() = annotations?.get("workers/message")
}

@Serializable
data class WorkerDeploymentsResult(val deployments: List<WorkerDeployment> = emptyList())

// MARK: - 脚本源码（原地编辑）

/** 单个脚本模块（multipart 的一个 part；service worker 视为单条）。 */
data class WorkerModule(val name: String, val contentType: String, val body: String)

/** 解析后的脚本源码。单模块 / service worker 可原地编辑；多模块（打包产物）只读。 */
data class WorkerContent(val modules: List<WorkerModule>, val isModule: Boolean) {
    /** 单模块 / service worker 才可安全往返编辑；多模块整体替换会丢失其它模块。 */
    val isEditable: Boolean get() = modules.size <= 1
    val mainModule: WorkerModule? get() = modules.firstOrNull()

    companion object {
        /**
         * 从 /content/v2 原始响应解析。响应体以 `--boundary` 开头且含 Content-Disposition = multipart（module worker）；
         * 否则为经典 service worker 裸 JS。边界从首行推导，无需读响应头。
         */
        fun parse(bytes: ByteArray): WorkerContent {
            val raw = bytes.toString(Charsets.UTF_8)
            val lead = raw.trimStart('\r', '\n', ' ')
            if (!lead.startsWith("--") || !raw.contains("Content-Disposition")) {
                return WorkerContent(listOf(WorkerModule("worker.js", "application/javascript", raw)), isModule = false)
            }
            val boundary = lead.substringBefore('\n').trim().trimEnd('\r').removePrefix("--")
            val modules = parseParts(raw, boundary)
            return if (modules.isEmpty())
                WorkerContent(listOf(WorkerModule("worker.js", "application/javascript", raw)), isModule = false)
            else WorkerContent(modules, isModule = true)
        }

        private fun parseParts(raw: String, boundary: String): List<WorkerModule> {
            val out = mutableListOf<WorkerModule>()
            for (chunk in raw.split("--$boundary")) {
                val part = chunk.trim('\r', '\n')
                if (part.isEmpty() || part == "--") continue
                var sep = part.indexOf("\r\n\r\n"); var sepLen = 4
                if (sep < 0) { sep = part.indexOf("\n\n"); sepLen = 2 }
                if (sep < 0) continue
                val headers = part.substring(0, sep)
                val body = part.substring(sep + sepLen)
                val name = headerValue(headers, "name") ?: headerValue(headers, "filename") ?: "module"
                val type = contentTypeHeader(headers) ?: "application/javascript+module"
                out.add(WorkerModule(name, type, body))
            }
            return out
        }

        private fun headerValue(headers: String, key: String): String? {
            val marker = "$key=\""
            val i = headers.indexOf(marker)
            if (i < 0) return null
            val rest = headers.substring(i + marker.length)
            val end = rest.indexOf('"')
            return if (end < 0) null else rest.substring(0, end)
        }

        private fun contentTypeHeader(headers: String): String? =
            headers.lineSequence()
                .firstOrNull { it.lowercase().startsWith("content-type:") }
                ?.substringAfter(':')?.trim()
    }
}

/** PUT 脚本上传的 metadata part（新建 / 原地编辑整体替换共用）。 */
@Serializable
data class WorkerDeployMetadata(
    @SerialName("main_module") val mainModule: String? = null,
    @SerialName("body_part") val bodyPart: String? = null,
    @SerialName("compatibility_date") val compatibilityDate: String? = null,
    @SerialName("compatibility_flags") val compatibilityFlags: List<String>? = null,
    val bindings: List<WorkerBindingInput> = emptyList(),
)

// MARK: - 绑定与设置

/**
 * 脚本绑定（KV / D1 / R2 / 密钥 / 变量 等）。读展示与 inherit 回传只需 type/name；变量另读 text。
 * 未建模的新绑定类型不致整页失败（缺字段降级为空串，调用方过滤空名）。
 */
@Serializable
data class WorkerBinding(
    val type: String = "",
    val name: String = "",
    val text: String? = null, // plain_text 变量的值；其余类型为 nil
) {
    val isSecret: Boolean get() = type == "secret_text" || type == "secrets_store_secret"
    val isPlainText: Boolean get() = type == "plain_text"

    /** 本客户端可原地增删的资源绑定（D1 / KV / R2）——其余类型仍只读。 */
    val isQuickManaged: Boolean get() = type == "kv_namespace" || type == "d1" || type == "r2_bucket"

    /** 回传时转为 inherit（按名保留旧绑定，密钥值我们读不到也能保住）。 */
    fun asInherit(): WorkerBindingInput = WorkerBindingInput(type = "inherit", name = name)
}

/** 脚本设置（GET .../settings）。 */
@Serializable
data class WorkerSettings(
    val bindings: List<WorkerBinding> = emptyList(),
    @SerialName("compatibility_date") val compatibilityDate: String? = null,
    @SerialName("compatibility_flags") val compatibilityFlags: List<String>? = null,
    @SerialName("usage_model") val usageModel: String? = null,
    val logpush: Boolean? = null,
) {
    /** 过滤掉空名（容错解码降级）的有效绑定。 */
    val validBindings: List<WorkerBinding> get() = bindings.filter { it.name.isNotEmpty() }

    /** 把现有绑定整组转为 inherit，供「只改某个变量、其余保持」的安全回传。 */
    fun inheritedBindings(excludingName: String? = null): List<WorkerBindingInput> =
        validBindings.filter { it.name != excludingName }.map { it.asInherit() }
}

// MARK: - 上传 / 写入请求体

/**
 * PATCH settings 的单条绑定。inherit 只发 {type,name}；plain_text 发 {type,name,text}；
 * kv_namespace 发 {type,name,namespace_id}；d1 发 {type,name,id}；
 * r2_bucket 发 {type,name,bucket_name}（R2 按**桶名**引用，不是 ID）。
 * Json explicitNulls=false，null 字段不编码（omitted）。
 */
@Serializable
data class WorkerBindingInput(
    val type: String,
    val name: String,
    val text: String? = null,
    @SerialName("namespace_id") val namespaceId: String? = null, // kv_namespace
    val id: String? = null, // d1 数据库 UUID
    @SerialName("bucket_name") val bucketName: String? = null, // r2_bucket 桶名
) {
    companion object {
        /** 绑定既有 KV 命名空间。 */
        fun kv(name: String, namespaceId: String) = WorkerBindingInput(type = "kv_namespace", name = name, namespaceId = namespaceId)

        /** 绑定既有 D1 数据库。 */
        fun d1(name: String, databaseId: String) = WorkerBindingInput(type = "d1", name = name, id = databaseId)

        /** 绑定既有 R2 存储桶（按桶名）。 */
        fun r2(name: String, bucketName: String) = WorkerBindingInput(type = "r2_bucket", name = name, bucketName = bucketName)
    }
}

/** PATCH settings 的 settings part（改变量时回传：变更项 + 其余 inherit）。 */
@Serializable
data class WorkerSettingsPatch(
    val bindings: List<WorkerBindingInput>,
    @SerialName("compatibility_date") val compatibilityDate: String? = null,
    @SerialName("compatibility_flags") val compatibilityFlags: List<String>? = null,
)

// MARK: - 密钥

/** 密钥（GET .../secrets，仅名 + 类型，永不含值）。 */
@Serializable
data class WorkerSecret(
    val name: String = "",
    val type: String? = null,
)

/** 新建 / 更新密钥（PUT .../secrets）。 */
@Serializable
data class WorkerSecretInput(
    val name: String,
    val text: String,
    val type: String = "secret_text",
)

/**
 * 批量写密钥（PATCH .../secrets-bulk，2026-06 新端点，单次 ≤100 项，原子生效）。
 * JSON Merge Patch 语义里 null=删除，但全局 Json 配了 explicitNulls=false 会把 null 吞掉，
 * 故本模型只承载新建/覆盖（删除仍走单条 DELETE 端点）。
 */
@Serializable
data class WorkerSecretsBulkPatch(
    val secrets: Map<String, WorkerSecretInput>,
)

// MARK: - Cron 触发器

/** 单条 Cron 触发器（GET .../schedules）。 */
@Serializable
data class WorkerSchedule(
    val cron: String = "",
    @SerialName("created_on") val createdOn: String? = null,
    @SerialName("modified_on") val modifiedOn: String? = null,
)

/** schedules 端点 result 形态 { schedules: [...] }。 */
@Serializable
data class WorkerSchedulesResult(
    val schedules: List<WorkerSchedule> = emptyList(),
)

/** PUT .../schedules 的单条（整组替换，请求体是裸数组 [{cron}]）。 */
@Serializable
data class WorkerScheduleInput(val cron: String)

// MARK: - Worker 预览（Previews，beta，只读）

/**
 * GET /accounts/{id}/workers/workers/{worker}/previews 的列表项（worker_id 接受 Worker 名）。
 * 时间为 ISO 8601 字符串；urls 为该预览可访问的地址。
 */
@Serializable
data class WorkerPreview(
    val id: String,
    val name: String? = null,
    val slug: String? = null,
    val urls: List<String>? = null,
    @SerialName("created_on") val createdOn: String? = null,
    @SerialName("updated_on") val updatedOn: String? = null,
    @SerialName("deployed_on") val deployedOn: String? = null,
)
