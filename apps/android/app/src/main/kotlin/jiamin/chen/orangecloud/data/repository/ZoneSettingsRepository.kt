package jiamin.chen.orangecloud.data.repository

import jiamin.chen.orangecloud.core.network.CfApiClient
import jiamin.chen.orangecloud.data.model.BotManagementConfig
import jiamin.chen.orangecloud.data.model.BotManagementUpdate
import jiamin.chen.orangecloud.data.model.PrecursorConfig
import jiamin.chen.orangecloud.data.model.PrecursorUpdate
import jiamin.chen.orangecloud.data.model.PurgeFilesRequest
import jiamin.chen.orangecloud.data.model.PurgeRequest
import jiamin.chen.orangecloud.data.model.PurgeResult
import jiamin.chen.orangecloud.data.model.ZoneSetting
import jiamin.chen.orangecloud.data.model.ZoneSettingUpdate
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Zone 设置读写（development_mode / security_level）+ 缓存清理 / 标记过期（对应 iOS ZoneSettingsService）。
 */
@Singleton
class ZoneSettingsRepository @Inject constructor(
    private val api: CfApiClient,
) {
    suspend fun getSetting(zoneId: String, setting: String): String =
        api.get<ZoneSetting>("zones/$zoneId/settings/$setting").value

    /** 读值；当前套餐不允许修改这项（editable=false）时返回 null，调用方据此隐藏开关。 */
    suspend fun getSettingIfEditable(zoneId: String, setting: String): String? =
        api.get<ZoneSetting>("zones/$zoneId/settings/$setting").takeIf { it.editable != false }?.value

    suspend fun setSetting(zoneId: String, setting: String, value: String): String =
        api.patch<ZoneSetting, ZoneSettingUpdate>("zones/$zoneId/settings/$setting", ZoneSettingUpdate(value)).value

    // MARK: - 机器人管控（bot-management.read/.write，全套餐可用）

    suspend fun getBotManagement(zoneId: String): BotManagementConfig =
        api.get("zones/$zoneId/bot_management")

    /**
     * 写机器人管控。PUT 是合并语义，[update] 只带一个非 null 项即可，
     * 其余 null 项在 explicitNulls=false 下不会被序列化，因此不会误清其它设置。
     */
    suspend fun setBotManagement(zoneId: String, update: BotManagementUpdate): BotManagementConfig =
        api.put("zones/$zoneId/bot_management", update)

    // MARK: - Precursor 会话级机器人检测（precursor.read/.write）

    suspend fun getPrecursor(zoneId: String): PrecursorConfig =
        api.get("zones/$zoneId/precursor")

    /** 只改 default_mode（局部更新）。回包形态未写死，只校验 success。 */
    suspend fun setPrecursorMode(zoneId: String, mode: String) {
        api.putChecked("zones/$zoneId/precursor", PrecursorUpdate(mode))
    }

    suspend fun purgeAllCache(zoneId: String) {
        api.post<PurgeResult, PurgeRequest>("zones/$zoneId/purge_cache", PurgeRequest(purgeEverything = true))
    }

    /** 按 URL 清理缓存（单文件 purge，单次最多 30 个 URL）。 */
    suspend fun purgeFiles(zoneId: String, urls: List<String>) {
        api.post<PurgeResult, PurgeFilesRequest>("zones/$zoneId/purge_cache", PurgeFilesRequest(files = urls))
    }

    // MARK: - 缓存失效（Invalidate，2026-09-28 GA）
    // 请求体与 purge_cache 完全相同、同一权限（cache.purge）与限流；区别是只把缓存标记为过期，
    // 下次请求向源站校验（304 则继续用缓存），而不是直接删掉。

    suspend fun invalidateAllCache(zoneId: String) {
        api.postChecked("zones/$zoneId/invalidate_cache", PurgeRequest(purgeEverything = true))
    }

    /** 按 URL 标记过期（与按 URL 清缓存同一上限）。 */
    suspend fun invalidateFiles(zoneId: String, urls: List<String>) {
        api.postChecked("zones/$zoneId/invalidate_cache", PurgeFilesRequest(files = urls))
    }
}
