package jiamin.chen.orangecloud.core.design

import android.content.Context
import android.net.Uri
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import jiamin.chen.orangecloud.R
import jiamin.chen.orangecloud.core.util.launchCustomTab

/**
 * 弹出 API 错误。CF 给了 documentation_url（2026-08-21 起 403 等错误会带：该端点所需的角色 / 权限文档）时，
 * 附一个「查看所需权限」动作，点了用 Custom Tab 打开文档；没有就是普通 snackbar。
 */
suspend fun SnackbarHostState.showApiError(
    context: Context,
    message: String,
    documentationUrl: String?,
) {
    val url = documentationUrl?.takeIf { it.startsWith("https://") || it.startsWith("http://") }
    if (url == null) {
        showSnackbar(message)
        return
    }
    val result = showSnackbar(
        message = message,
        actionLabel = context.getString(R.string.error_view_permissions),
        withDismissAction = true,
        duration = SnackbarDuration.Long,
    )
    if (result == SnackbarResult.ActionPerformed) {
        runCatching { context.launchCustomTab(Uri.parse(url)) }
    }
}
