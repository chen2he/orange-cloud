package jiamin.chen.orangecloud.ui.settings

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.widget.Toast
import androidx.core.content.FileProvider
import jiamin.chen.orangecloud.core.logging.AppLog
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowForward
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material.icons.outlined.Build
import androidx.compose.material.icons.outlined.Code
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Email
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.MonitorHeart
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.PrivacyTip
import androidx.compose.material.icons.outlined.Star
import androidx.compose.material.icons.outlined.Verified
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import jiamin.chen.orangecloud.BuildConfig
import jiamin.chen.orangecloud.R
import jiamin.chen.orangecloud.core.design.SkyBackground
import jiamin.chen.orangecloud.core.design.TintIcon
import jiamin.chen.orangecloud.core.design.ZoneAvatar
import jiamin.chen.orangecloud.core.design.onSky
import jiamin.chen.orangecloud.core.design.rememberSkyPhase
import jiamin.chen.orangecloud.core.design.theme.OcOrange
import jiamin.chen.orangecloud.core.design.theme.OcSuccess
import jiamin.chen.orangecloud.core.system.AppAppearance
import jiamin.chen.orangecloud.core.util.launchCustomTab

@Composable
fun SettingsScreen(
    onOpenStatus: () -> Unit = {},
    onOpenIdentity: (String) -> Unit = {},
    onAddAccount: () -> Unit = {},
    onOpenPaywall: () -> Unit = {},
    onOpenAudit: () -> Unit = {},
    onOpenToolbox: () -> Unit = {},
    onOpenAlerting: () -> Unit = {},
    viewModel: SettingsViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val phase = rememberSkyPhase()
    val onSky = phase.onSky
    val cs = MaterialTheme.colorScheme
    val context = LocalContext.current

    val notifPermLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        viewModel.setNotificationsEnabled(granted)
    }
    fun toggleNotifications(on: Boolean) {
        if (on && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            notifPermLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            viewModel.setNotificationsEnabled(on)
        }
    }
    fun openUrl(url: String) = context.launchCustomTab(Uri.parse(url))

    // 帮助与反馈：邮件 intent，正文预填诊断头（版本/系统/设备/账号数）+ 附带诊断日志文件，
    // 全程不含任何令牌或密钥（日志由 AppLog 脱敏写入，附件经 FileProvider 授权给邮件应用）。
    val feedbackSubject = stringResource(R.string.feedback_subject)
    val noMailMsg = stringResource(R.string.feedback_no_mail)
    val feedbackLogNote = stringResource(R.string.feedback_log_note)
    fun sendFeedback() {
        val logUri = AppLog.exportedFile()?.let { file ->
            runCatching {
                FileProvider.getUriForFile(context, "${BuildConfig.APPLICATION_ID}.fileprovider", file)
            }.getOrNull()
        }
        val diag = buildString {
            append("\n\n---\n")
            append("App ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})\n")
            append("Android ${Build.VERSION.RELEASE} (SDK ${Build.VERSION.SDK_INT})\n")
            append("${Build.MANUFACTURER} ${Build.MODEL}\n")
            append("Accounts: ${state.sessions.size}")
            if (logUri != null) append("\n$feedbackLogNote")
        }
        val intent = if (logUri != null) {
            // 带附件：ACTION_SEND（mailto 不支持 EXTRA_STREAM），偏向邮件应用
            Intent(Intent.ACTION_SEND).apply {
                type = "message/rfc822"
                putExtra(Intent.EXTRA_EMAIL, arrayOf("support@zhe.ltd"))
                putExtra(Intent.EXTRA_SUBJECT, feedbackSubject)
                putExtra(Intent.EXTRA_TEXT, diag)
                putExtra(Intent.EXTRA_STREAM, logUri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
        } else {
            Intent(Intent.ACTION_SENDTO).apply {
                data = Uri.parse("mailto:")
                putExtra(Intent.EXTRA_EMAIL, arrayOf("support@zhe.ltd"))
                putExtra(Intent.EXTRA_SUBJECT, feedbackSubject)
                putExtra(Intent.EXTRA_TEXT, diag)
            }
        }
        val launch = if (logUri != null) Intent.createChooser(intent, null) else intent
        runCatching { context.startActivity(launch) }
            .onFailure { Toast.makeText(context, noMailMsg, Toast.LENGTH_SHORT).show() }
    }

    SkyBackground(phase = phase) {
        Column(
            modifier = Modifier.fillMaxSize().systemBarsPadding().verticalScroll(rememberScrollState()),
        ) {
            Text(
                text = stringResource(R.string.settings_title),
                color = onSky,
                fontSize = 32.sp,
                fontWeight = FontWeight.Medium,
                modifier = Modifier.padding(start = 24.dp, end = 24.dp, top = 16.dp, bottom = 8.dp),
            )

            // ── Cloudflare 账号 ──
            SettingsSection(stringResource(R.string.settings_accounts), stringResource(R.string.settings_accounts_footer)) {
                state.sessions.forEach { session ->
                    Row(
                        Modifier.fillMaxWidth().clickable { onOpenIdentity(session.id) }.padding(horizontal = 16.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        ZoneAvatar(session.label, size = 38.dp)
                        Spacer(Modifier.width(14.dp))
                        Column(Modifier.weight(1f)) {
                            Text(session.label, fontSize = 16.sp, color = cs.onSurface, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(stringResource(R.string.settings_scopes, session.scopes.size), fontSize = 13.sp, color = cs.onSurfaceVariant)
                        }
                        if (session.id == state.currentSessionId) {
                            Text(
                                stringResource(R.string.settings_current),
                                color = cs.primary,
                                fontSize = 12.sp,
                                fontWeight = FontWeight.SemiBold,
                                modifier = Modifier
                                    .background(OcOrange.copy(alpha = 0.14f), RoundedCornerShape(999.dp))
                                    .padding(horizontal = 8.dp, vertical = 3.dp),
                            )
                        }
                        Spacer(Modifier.width(6.dp))
                        Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, contentDescription = null, tint = cs.onSurfaceVariant)
                    }
                    RowDivider(indent = true)
                }
                Row(
                    Modifier.fillMaxWidth().clickable(onClick = onAddAccount).padding(horizontal = 16.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    TintIcon(Icons.Outlined.Person, OcOrange, size = 38.dp)
                    Spacer(Modifier.width(14.dp))
                    Text(stringResource(R.string.dash_add_account), fontSize = 16.sp, color = cs.primary, modifier = Modifier.weight(1f))
                    if (!state.isPro && state.sessions.isNotEmpty()) ProBadge()
                }
            }

            // ── Orange Cloud Pro（oss 风味无此入口）──
            if (!viewModel.isOss) {
                SettingsSection(null, null) {
                    Row(
                        Modifier.fillMaxWidth().clickable(onClick = onOpenPaywall).padding(horizontal = 16.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        TintIcon(Icons.Outlined.AutoAwesome, OcOrange, size = 38.dp)
                        Spacer(Modifier.width(14.dp))
                        Column(Modifier.weight(1f)) {
                            Text(stringResource(R.string.settings_pro), fontSize = 16.sp, color = cs.onSurface)
                            Text(
                                stringResource(if (state.isPro) R.string.settings_pro_unlocked else R.string.settings_pro_sub),
                                fontSize = 13.sp, color = cs.onSurfaceVariant,
                            )
                        }
                        if (state.isPro) {
                            Icon(Icons.Outlined.Verified, contentDescription = null, tint = cs.primary)
                        } else {
                            Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, contentDescription = null, tint = cs.onSurfaceVariant)
                        }
                    }
                }
            }

            // ── 外观 ──
            SettingsSection(stringResource(R.string.settings_appearance), null) {
                AppearancePicker(state.appearance) { viewModel.setAppearance(it) }
            }

            // ── 通知 ──
            SettingsSection(
                stringResource(R.string.settings_notif),
                stringResource(if (state.notificationsEnabled) R.string.settings_notif_footer_on else R.string.settings_notif_footer_off),
            ) {
                ToggleRow(Icons.Outlined.Notifications, OcOrange, stringResource(R.string.settings_notif_master), state.notificationsEnabled) { toggleNotifications(it) }
                if (state.notificationsEnabled) {
                    RowDivider(indent = true)
                    ToggleRow(Icons.Outlined.MonitorHeart, OcOrange, stringResource(R.string.settings_notif_zone), state.notifyZoneStatus, viewModel::setNotifyZoneStatus)
                    RowDivider(indent = true)
                    ToggleRow(Icons.Outlined.Notifications, cs.error, stringResource(R.string.settings_notif_worker), state.notifyWorkerErrors, viewModel::setNotifyWorkerErrors)
                }
            }

            // ── 开发者工具箱（免登录，与登录页同一入口）──
            SettingsSection(null, null) {
                NavRow(Icons.Outlined.Build, OcOrange, stringResource(R.string.toolbox_title), onOpenToolbox)
            }

            // ── 服务状态 ──
            SettingsSection(stringResource(R.string.settings_service), stringResource(R.string.settings_service_footer)) {
                NavRow(Icons.Outlined.MonitorHeart, OcSuccess, stringResource(R.string.status_title), onOpenStatus)
                RowDivider(indent = true)
                NavRow(Icons.Outlined.History, Color(0xFF8B6CC7), stringResource(R.string.audit_title), onOpenAudit)
                RowDivider(indent = true)
                NavRow(Icons.Outlined.Notifications, OcOrange, stringResource(R.string.alerting_title), onOpenAlerting)
            }

            // ── 帮助与反馈 ──
            SettingsSection(stringResource(R.string.settings_help), stringResource(R.string.settings_help_footer)) {
                NavRow(Icons.Outlined.Email, Color(0xFF3D86E0), stringResource(R.string.settings_feedback)) { sendFeedback() }
            }

            // ── 关于 ──
            SettingsSection(stringResource(R.string.settings_about), null) {
                Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                    TintIcon(Icons.Outlined.Info, Color(0xFF3D86E0), size = 38.dp)
                    Spacer(Modifier.width(14.dp))
                    Text(stringResource(R.string.settings_version), fontSize = 16.sp, color = cs.onSurface, modifier = Modifier.weight(1f))
                    Text("${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})", fontSize = 14.sp, color = cs.onSurfaceVariant)
                }
                RowDivider(indent = true)
                LinkRow(Icons.Outlined.Star, Color(0xFFE0A800), stringResource(R.string.settings_rate)) {
                    runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=jiamin.chen.orangecloud"))) }
                        .onFailure { openUrl("https://play.google.com/store/apps/details?id=jiamin.chen.orangecloud") }
                }
                RowDivider(indent = true)
                LinkRow(Icons.Outlined.Code, cs.onSurfaceVariant, stringResource(R.string.settings_github)) { openUrl("https://github.com/chen2he/orange-cloud") }
                RowDivider(indent = true)
                LinkRow(Icons.Outlined.PrivacyTip, cs.onSurfaceVariant, stringResource(R.string.settings_privacy)) { openUrl("https://o-c.do/privacy") }
                RowDivider(indent = true)
                LinkRow(Icons.Outlined.Description, cs.onSurfaceVariant, stringResource(R.string.settings_terms)) { openUrl("https://o-c.do/terms") }
            }

            Text(
                stringResource(R.string.settings_about_footer),
                color = cs.onSurfaceVariant,
                fontSize = 12.sp,
                modifier = Modifier.fillMaxWidth().padding(top = 16.dp),
                textAlign = TextAlign.Center,
            )
            Text(
                stringResource(R.string.settings_about_copyright),
                color = cs.onSurfaceVariant,
                fontSize = 12.sp,
                modifier = Modifier.fillMaxWidth().padding(top = 4.dp, bottom = 24.dp),
                textAlign = TextAlign.Center,
            )
        }
    }
}

@Composable
private fun SettingsSection(header: String?, footer: String?, content: @Composable () -> Unit) {
    val cs = MaterialTheme.colorScheme
    if (header != null) {
        Text(header, color = cs.primary, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(start = 24.dp, top = 18.dp, bottom = 8.dp))
    } else {
        Spacer(Modifier.height(12.dp))
    }
    Surface(color = cs.surfaceContainerLow, shape = RoundedCornerShape(20.dp), modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
        Column { content() }
    }
    if (footer != null) {
        Text(footer, color = cs.onSurfaceVariant, fontSize = 12.sp, modifier = Modifier.padding(start = 28.dp, end = 28.dp, top = 8.dp))
    }
}

@Composable
private fun NavRow(icon: ImageVector, iconColor: Color, title: String, onClick: () -> Unit) {
    val cs = MaterialTheme.colorScheme
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        TintIcon(icon, iconColor, size = 38.dp)
        Spacer(Modifier.width(14.dp))
        Text(title, fontSize = 16.sp, color = cs.onSurface, modifier = Modifier.weight(1f))
        Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, contentDescription = null, tint = cs.onSurfaceVariant)
    }
}

@Composable
private fun LinkRow(icon: ImageVector, iconColor: Color, title: String, onClick: () -> Unit) {
    val cs = MaterialTheme.colorScheme
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        TintIcon(icon, iconColor, size = 38.dp)
        Spacer(Modifier.width(14.dp))
        Text(title, fontSize = 16.sp, color = cs.onSurface, modifier = Modifier.weight(1f))
        Icon(Icons.AutoMirrored.Outlined.ArrowForward, contentDescription = null, tint = cs.onSurfaceVariant, modifier = Modifier.size(16.dp))
    }
}

@Composable
private fun ToggleRow(icon: ImageVector, iconColor: Color, title: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    val cs = MaterialTheme.colorScheme
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        TintIcon(icon, iconColor, size = 38.dp)
        Spacer(Modifier.width(14.dp))
        Text(title, fontSize = 16.sp, color = cs.onSurface, modifier = Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = onChange)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AppearancePicker(current: AppAppearance, onSelect: (AppAppearance) -> Unit) {
    val options = listOf(
        AppAppearance.SYSTEM to R.string.settings_appearance_system,
        AppAppearance.LIGHT to R.string.settings_appearance_light,
        AppAppearance.DARK to R.string.settings_appearance_dark,
    )
    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(16.dp)) {
        options.forEachIndexed { index, (mode, labelRes) ->
            SegmentedButton(
                selected = current == mode,
                onClick = { onSelect(mode) },
                shape = SegmentedButtonDefaults.itemShape(index, options.size),
            ) { Text(stringResource(labelRes)) }
        }
    }
}

@Composable
private fun ProBadge() {
    val cs = MaterialTheme.colorScheme
    Text(
        "PRO",
        color = cs.onPrimaryContainer,
        fontSize = 11.sp,
        fontWeight = FontWeight.Bold,
        modifier = Modifier.background(cs.primaryContainer, RoundedCornerShape(6.dp)).padding(horizontal = 8.dp, vertical = 3.dp),
    )
}

@Composable
private fun RowDivider(indent: Boolean) {
    Box(
        Modifier.fillMaxWidth().padding(start = if (indent) 68.dp else 0.dp).height(1.dp)
            .background(MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f)),
    )
}
