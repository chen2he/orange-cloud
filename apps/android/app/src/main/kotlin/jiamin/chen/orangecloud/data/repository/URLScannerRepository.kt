package jiamin.chen.orangecloud.data.repository

import jiamin.chen.orangecloud.core.network.CfApiClient
import jiamin.chen.orangecloud.data.model.URLScanAccepted
import jiamin.chen.orangecloud.data.model.URLScanResult
import jiamin.chen.orangecloud.data.model.URLScanSubmit
import javax.inject.Inject
import javax.inject.Singleton

/**
 * URL Scanner v2（url-scanner.read / .write）。对应 iOS URLScannerService。
 *
 * ⚠️ v2 全部端点都**不走 CF 标准信封**（无 success/errors/result 包装）：
 * - POST /scan 2xx 直接回 { uuid, api, result(报告网址 String), message, url, visibility }
 * - GET /result/{id} 2xx 直接回报告对象；未就绪回 404；提交撞上近期已扫过的主机名回 409
 * 以前按信封解，提交这一步就必失败（iOS 同款 Sentry APPLE-IOS-A0）。
 */
@Singleton
class URLScannerRepository @Inject constructor(
    private val api: CfApiClient,
) {
    /** 提交扫描。异步任务，返回 uuid 后需轮询结果。 */
    suspend fun submit(accountId: String, url: String): String? {
        val accepted: URLScanAccepted =
            api.postBare("accounts/$accountId/urlscanner/v2/scan", URLScanSubmit(url))
        return accepted.uuid
    }

    /** 取报告。未就绪时接口 404 —— 调用方按「继续轮询」处理。 */
    suspend fun result(accountId: String, scanId: String): URLScanResult =
        api.getBare("accounts/$accountId/urlscanner/v2/result/$scanId")
}
