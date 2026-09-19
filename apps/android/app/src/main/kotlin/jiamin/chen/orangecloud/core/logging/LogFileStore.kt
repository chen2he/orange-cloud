package jiamin.chen.orangecloud.core.logging

import java.io.File
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * AppLog 的文件落地（对应 iOS LogFileStore）：日志写进 cacheDir/logs/app.log，
 * 超上限滚动一代（app.1.log）。导出时合并上一代 + 当前（旧在前），约束体积便于作邮件附件。
 * 写入排进单线程队列（调用方多在主线程：每个 API 请求都记一行，Dashboard 首屏十几个并发请求
 * 就是十几次主线程文件 IO + 滚动时的锁等待）；导出 / 清空前先排空队列，对外线程安全。
 *
 * 脱敏铁律（调用方负责）：绝不把 token / Cookie / Authorization / KV·密钥的值写进消息。
 */
class LogFileStore(cacheDir: File) {

    private val dir = File(cacheDir, "logs").apply { runCatching { mkdirs() } }
    private val current = File(dir, "app.log")
    private val previous = File(dir, "app.1.log")
    private val exported = File(dir, "OrangeCloud-logs.txt")
    private val maxBytes = 256L * 1024   // 单文件上限，两代约 512KB
    private val fmt = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss.SSS")
    private val writer = Executors.newSingleThreadExecutor { r -> Thread(r, "oc-log").apply { isDaemon = true } }

    fun append(level: String, category: String, message: String) {
        // 时间戳在调用线程取，队列排队不影响记录时刻
        val line = "${LocalDateTime.now().format(fmt)} [$level] [$category] $message\n"
        runCatching { writer.execute { write(line) } }
    }

    @Synchronized
    private fun write(line: String) {
        try {
            if (current.exists() && current.length() > maxBytes) rotate()
            current.appendText(line)
        } catch (_: Exception) {
            // 日志写入失败绝不影响主流程
        }
    }

    /** 等队列里已提交的写入全部落盘（导出 / 清空前调用） */
    private fun drain() {
        runCatching { writer.submit {}.get(2, TimeUnit.SECONDS) }
    }

    private fun rotate() {
        runCatching {
            if (previous.exists()) previous.delete()
            current.renameTo(previous)
        }
    }

    /** 合并上一代 + 当前写到导出文件返回；无内容时返回 null。供反馈附件用。 */
    fun exportedFile(): File? {
        drain()
        return exportSynchronized()
    }

    @Synchronized
    private fun exportSynchronized(): File? {
        val text = buildString {
            if (previous.exists()) runCatching { append(previous.readText()) }
            if (current.exists()) runCatching { append(current.readText()) }
        }
        if (text.isBlank()) return null
        return runCatching { exported.writeText(text); exported }.getOrNull()
    }

    fun clear() {
        drain()
        synchronized(this) { runCatching { current.delete(); previous.delete(); exported.delete() } }
    }
}
