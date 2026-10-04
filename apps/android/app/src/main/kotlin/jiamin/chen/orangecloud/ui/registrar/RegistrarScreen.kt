package jiamin.chen.orangecloud.ui.registrar

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.VerifiedUser
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import jiamin.chen.orangecloud.R
import jiamin.chen.orangecloud.core.design.SkyBackground
import jiamin.chen.orangecloud.core.design.SkyEmptyState
import jiamin.chen.orangecloud.core.design.SkyHeader
import jiamin.chen.orangecloud.core.design.onSky
import jiamin.chen.orangecloud.core.design.rememberSkyPhase
import jiamin.chen.orangecloud.data.model.DomainRegistration

/**
 * 在 Cloudflare 注册的域名：到期日、自动续费、转移锁（只读）。
 * 域名注册是花钱操作，移动端不做。
 */
@Composable
fun RegistrarScreen(
    onBack: () -> Unit,
    /** 搜索新域名（只查询，注册引导到控制台）。 */
    onOpenSearch: () -> Unit = {},
    viewModel: RegistrarViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val phase = rememberSkyPhase()
    val onSky = phase.onSky
    val snackbarHostState = remember { SnackbarHostState() }
    val genericErr = stringResource(R.string.error_generic)

    LaunchedEffect(Unit) {
        viewModel.events.collect { event ->
            when (event) {
                is RegistrarEvent.Error -> snackbarHostState.showSnackbar(event.message ?: genericErr)
            }
        }
    }

    SkyBackground(phase = phase) {
        Box(Modifier.fillMaxSize().systemBarsPadding()) {
            Column(Modifier.fillMaxSize()) {
                SkyHeader(
                    title = stringResource(R.string.reg_title),
                    onSky = onSky,
                    isLoading = state.isLoading,
                    onRefresh = { viewModel.load() },
                    onBack = onBack,
                    titleSize = 22,
                    backDescription = stringResource(R.string.common_back),
                    refreshDescription = stringResource(R.string.common_refresh),
                    actions = {
                        if (!state.missingScope) {
                            androidx.compose.material3.IconButton(onClick = onOpenSearch) {
                                androidx.compose.material3.Icon(
                                    androidx.compose.material.icons.Icons.Outlined.Search,
                                    contentDescription = stringResource(R.string.reg_search),
                                    tint = onSky,
                                )
                            }
                        }
                    },
                )
                when {
                    state.missingScope || (state.loaded && state.registrations.isEmpty()) ->
                        Box(Modifier.fillMaxSize()) {
                            SkyEmptyState(
                                Icons.Outlined.VerifiedUser,
                                stringResource(
                                    if (state.missingScope) R.string.scope_missing else R.string.reg_empty,
                                ),
                                onSky,
                                stringResource(R.string.common_refresh),
                            ) { viewModel.load() }
                        }
                    else -> LazyColumn(
                        modifier = Modifier.fillMaxSize().padding(horizontal = 16.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        items(state.registrations, key = { it.domainName }) { registration ->
                            RegistrationCard(
                                registration = registration,
                                canAdmin = state.canAdmin,
                                enabled = !state.isMutating,
                                onAutoRenewChange = { viewModel.setAutoRenew(registration, it) },
                            )
                        }
                        item {
                            Text(
                                stringResource(R.string.reg_footer),
                                fontSize = 12.sp,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.padding(vertical = 12.dp),
                            )
                        }
                    }
                }
            }
            SnackbarHost(snackbarHostState, modifier = Modifier.align(Alignment.BottomCenter))
        }
    }
}

@Composable
private fun RegistrationCard(
    registration: DomainRegistration,
    canAdmin: Boolean,
    enabled: Boolean,
    onAutoRenewChange: (Boolean) -> Unit,
) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        shape = RoundedCornerShape(16.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    registration.domainName,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier.weight(1f),
                )
                Text(
                    stringResource(statusLabel(registration.status)),
                    fontSize = 12.sp,
                    color = if (registration.status == "active") {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    } else {
                        Color(0xFFEF6C00)
                    },
                )
            }
            val days = registration.daysUntilExpiry()
            if (days != null) {
                Text(
                    if (days >= 0) {
                        stringResource(R.string.reg_days_left, days)
                    } else {
                        stringResource(R.string.reg_expired)
                    },
                    fontSize = 13.sp,
                    color = if (registration.needsAttention()) {
                        Color(0xFFEF6C00)
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    },
                )
            }
            Spacer(Modifier.height(8.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    stringResource(R.string.reg_auto_renew),
                    fontSize = 14.sp,
                    color = MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier.weight(1f),
                )
                Switch(
                    checked = registration.autoRenew == true,
                    onCheckedChange = onAutoRenewChange,
                    enabled = canAdmin && enabled,
                )
            }
            // 转移锁在新版 API 里只读，做成开关会误导用户以为能改
            registration.locked?.let {
                Text(
                    stringResource(if (it) R.string.reg_lock_on else R.string.reg_lock_off),
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

private fun statusLabel(status: String?) = when (status) {
    "active" -> R.string.reg_status_active
    "registration_pending" -> R.string.reg_status_pending
    "expired" -> R.string.reg_status_expired
    "suspended" -> R.string.reg_status_suspended
    "redemption_period" -> R.string.reg_status_redemption
    else -> R.string.hc_status_unknown
}
