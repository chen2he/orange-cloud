package jiamin.chen.orangecloud.ui.storage

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import jiamin.chen.orangecloud.R
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive

/**
 * D1 免费套餐每日行读 / 行写上限的报错（2026-09-01 起 REST /query 也强制执行）。
 * CF 报错文案未固定，按「daily + limit」或「free tier」不区分大小写识别。
 */
fun isD1DailyLimitError(message: String?): Boolean {
    val m = message?.lowercase() ?: return false
    return ("daily" in m && "limit" in m) || "free tier" in m
}

/** 用户可见的 D1 报错：命中每日额度上限时先给中文解释，再附原文；否则原文照出。 */
@Composable
fun d1ErrorText(raw: String): String =
    if (isD1DailyLimitError(raw)) stringResource(R.string.d1_daily_limit) + "\n\n" + raw else raw

/** PRAGMA index_list 的一行：索引名 / 是否唯一 / 来源。 */
data class D1IndexInfo(
    val name: String,
    val unique: Boolean,
    /** SQLite 口径："c" = CREATE INDEX，"u" = UNIQUE 约束，"pk" = 主键。 */
    val origin: String,
    val partial: Boolean = false,
)

/** 单元格取值：缺失 / NULL → 空串；基础值 → 原文；其余 → JSON 文本。 */
private fun cellText(value: JsonElement?): String = when {
    value == null || value is JsonNull -> ""
    value is JsonPrimitive -> value.content
    else -> value.toString()
}

/**
 * RFC 4180 转义：含逗号 / 双引号 / 换行的字段用双引号包裹，内部 `"` 写成 `""`。
 * 前后空白也一并包裹，避免被表格软件吃掉。
 */
fun csvEscape(value: String): String {
    val needsQuote = value.any { it == ',' || it == '"' || it == '\n' || it == '\r' } ||
        value != value.trim()
    return if (needsQuote) "\"" + value.replace("\"", "\"\"") + "\"" else value
}

/**
 * 把**当前已加载**的结果集转成 CSV（CRLF 行尾 + UTF-8 BOM，方便 Excel 正确识别中文）。
 * 不重新发查询，也不做任何补取。
 */
fun buildCsv(columns: List<String>, rows: List<Map<String, JsonElement>>): String = buildString {
    append('\uFEFF')
    append(columns.joinToString(",") { csvEscape(it) })
    append("\r\n")
    rows.forEach { row ->
        append(columns.joinToString(",") { csvEscape(cellText(row[it])) })
        append("\r\n")
    }
}

/** 导出文件名安全化（只留字母数字与 . _ -）。 */
fun sanitizeFileName(name: String, fallback: String): String {
    val cleaned = name.trim().replace(Regex("[^A-Za-z0-9._-]"), "_").trim('_')
    return cleaned.ifEmpty { fallback }.take(48)
}
