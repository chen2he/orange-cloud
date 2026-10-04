package jiamin.chen.orangecloud.ui.registrar

import android.net.Uri
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
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
import jiamin.chen.orangecloud.core.design.showApiError
import jiamin.chen.orangecloud.core.design.theme.OcOrange
import jiamin.chen.orangecloud.core.util.launchCustomTab
import jiamin.chen.orangecloud.data.model.DomainAvailability

/** 控制台注册入口（不在 App 内购买）。:account 由控制台按当前登录账户替换。 */
private const val DASH_REGISTER_URL = "https://dash.cloudflare.com/?to=/:account/registrar/register"

/**
 * 搜索新域名：结果行显示可注册性、价格、溢价标记；点开实时确认（domain-check），
 * 可注册时给「在 Cloudflare 控制台注册」。移动端不做购买。
 */
@Composable
fun RegistrarSearchScreen(
    onBack: () -> Unit,
    viewModel: RegistrarSearchViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val phase = rememberSkyPhase()
    val onSky = phase.onSky
    val context = LocalContext.current
    val focusManager = LocalFocusManager.current
    val snackbarHostState = remember { SnackbarHostState() }
    val genericErr = stringResource(R.string.error_generic)
    var query by rememberSaveable { mutableStateOf("") }

    LaunchedEffect(Unit) {
        viewModel.events.collect { event ->
            when (event) {
                is RegistrarSearchEvent.Error ->
                    snackbarHostState.showApiError(context, event.message ?: genericErr, event.documentationUrl)
            }
        }
    }

    fun submit() {
        focusManager.clearFocus()
        viewModel.search(query)
    }

    SkyBackground(phase = phase) {
        Box(Modifier.fillMaxSize().systemBarsPadding()) {
            Column(Modifier.fillMaxSize()) {
                SkyHeader(
                    title = stringResource(R.string.reg_search),
                    onSky = onSky,
                    isLoading = state.isSearching,
                    onRefresh = { submit() },
                    onBack = onBack,
                    titleSize = 22,
                    backDescription = stringResource(R.string.common_back),
                    refreshDescription = stringResource(R.string.common_refresh),
                )
                if (state.missingScope) {
                    SkyEmptyState(Icons.Outlined.Lock, stringResource(R.string.scope_missing), onSky, stringResource(R.string.common_refresh)) {}
                } else {
                    Surface(
                        color = MaterialTheme.colorScheme.surfaceContainerLow,
                        shape = RoundedCornerShape(16.dp),
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                    ) {
                        OutlinedTextField(
                            value = query,
                            onValueChange = { query = it },
                            placeholder = { Text(stringResource(R.string.reg_search_hint)) },
                            singleLine = true,
                            trailingIcon = {
                                IconButton(onClick = { submit() }, enabled = query.isNotBlank() && !state.isSearching) {
                                    Icon(Icons.Outlined.Search, contentDescription = stringResource(R.string.reg_search))
                                }
                            },
                            keyboardOptions = KeyboardOptions(
                                keyboardType = KeyboardType.Uri,
                                imeAction = ImeAction.Search,
                                autoCorrectEnabled = false,
                                capitalization = KeyboardCapitalization.None,
                            ),
                            keyboardActions = KeyboardActions(onSearch = { submit() }),
                            modifier = Modifier.fillMaxWidth().padding(8.dp),
                        )
                    }
                    Text(
                        stringResource(R.string.reg_search_note),
                        fontSize = 12.sp,
                        color = onSky.copy(alpha = 0.7f),
                        modifier = Modifier.padding(horizontal = 24.dp, vertical = 8.dp),
                    )
                    when {
                        state.results.isEmpty() && state.isSearching ->
                            Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator(color = onSky) }

                        state.results.isEmpty() && state.searched ->
                            SkyEmptyState(Icons.Outlined.Search, stringResource(R.string.reg_search_empty), onSky, stringResource(R.string.common_refresh)) { submit() }

                        else -> LazyColumn(
                            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 4.dp),
                            verticalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            items(state.results, key = { it.name }) { domain ->
                                DomainResultRow(domain, onClick = { viewModel.check(domain.name) })
                            }
                        }
                    }
                }
            }
            SnackbarHost(snackbarHostState, modifier = Modifier.align(Alignment.BottomCenter))
        }
    }

    state.checking?.let { name ->
        DomainCheckDialog(
            name = name,
            result = state.checked,
            onRegister = { runCatching { context.launchCustomTab(Uri.parse(DASH_REGISTER_URL)) } },
            onDismiss = viewModel::dismissCheck,
        )
    }
}

@Composable
private fun DomainResultRow(domain: DomainAvailability, onClick: () -> Unit) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        shape = RoundedCornerShape(16.dp),
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick),
    ) {
        Column(Modifier.padding(14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    domain.name,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier.weight(1f, fill = false),
                )
                if (domain.isPremium) {
                    Spacer(Modifier.width(6.dp))
                    PremiumBadge()
                }
            }
            AvailabilityLine(domain)
            priceText(domain)?.let {
                Text(it, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

/** 实时确认对话框：确认中转圈；可注册时给控制台注册入口（不在 App 内购买）。 */
@Composable
private fun DomainCheckDialog(
    name: String,
    result: DomainAvailability?,
    onRegister: () -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(name) },
        text = {
            if (result == null) {
                Box(Modifier.fillMaxWidth().padding(vertical = 12.dp), Alignment.Center) {
                    CircularProgressIndicator(Modifier.size(24.dp), strokeWidth = 2.dp)
                }
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    if (result.isPremium) PremiumBadge()
                    AvailabilityLine(result)
                    priceText(result)?.let { Text(it, fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                }
            }
        },
        confirmButton = {
            if (result?.registrable == true) {
                TextButton(onClick = onRegister) { Text(stringResource(R.string.reg_register_in_dash)) }
            } else {
                TextButton(onClick = onDismiss) { Text(stringResource(R.string.common_done)) }
            }
        },
        dismissButton = {
            if (result?.registrable == true) {
                TextButton(onClick = onDismiss) { Text(stringResource(R.string.common_cancel)) }
            }
        },
    )
}

@Composable
private fun AvailabilityLine(domain: DomainAvailability) {
    val registrable = domain.registrable == true
    val label = if (registrable) {
        stringResource(R.string.reg_registrable)
    } else {
        val reason = reasonLabel(domain.reason)
        stringResource(R.string.reg_not_registrable) + (reason?.let { " · $it" } ?: "")
    }
    Text(
        label,
        fontSize = 13.sp,
        fontWeight = FontWeight.Medium,
        color = if (registrable) Color(0xFF2FBF71) else MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

@Composable
private fun PremiumBadge() {
    Surface(color = OcOrange.copy(alpha = 0.14f), shape = RoundedCornerShape(6.dp)) {
        Text(
            stringResource(R.string.reg_premium),
            fontSize = 11.sp,
            fontWeight = FontWeight.SemiBold,
            color = OcOrange,
            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
        )
    }
}

/** 「首年 {注册价} {币种} · 续费 {续费价}/年」；缺注册价则不显示。 */
@Composable
private fun priceText(domain: DomainAvailability): String? {
    val pricing = domain.pricing ?: return null
    val registration = pricing.registration ?: return null
    return stringResource(
        R.string.reg_price,
        registration,
        pricing.currency.orEmpty(),
        pricing.renewal ?: "—",
    )
}

/** 不可注册原因 → 文案；未知原因原样显示。 */
@Composable
private fun reasonLabel(reason: String?): String? = when (reason) {
    null, "" -> null
    "extension_not_supported_via_api" -> stringResource(R.string.reg_reason_not_supported_via_api)
    "extension_not_supported" -> stringResource(R.string.reg_reason_not_supported)
    "extension_disallows_registration" -> stringResource(R.string.reg_reason_disallows)
    "domain_premium" -> stringResource(R.string.reg_reason_premium)
    "domain_unavailable" -> stringResource(R.string.reg_reason_unavailable)
    else -> reason
}
