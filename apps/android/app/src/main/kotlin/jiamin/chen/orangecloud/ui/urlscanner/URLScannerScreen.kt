package jiamin.chen.orangecloud.ui.urlscanner

import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.outlined.TravelExplore
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
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

/** URL 安全扫描：提交链接，看归属、状态与风险判定。需账号，故不在免登录工具箱里。 */
@Composable
fun URLScannerScreen(
    onBack: () -> Unit,
    viewModel: URLScannerViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val phase = rememberSkyPhase()
    val onSky = phase.onSky
    val snackbarHostState = remember { SnackbarHostState() }
    val stillScanning = stringResource(R.string.urls_still_scanning)
    val recentlyScanned = stringResource(R.string.urls_recently_scanned)

    LaunchedEffect(Unit) {
        viewModel.events.collect { event ->
            when (event) {
                is URLScannerEvent.Error -> snackbarHostState.showSnackbar(event.message ?: stillScanning)
                URLScannerEvent.RecentlyScanned -> snackbarHostState.showSnackbar(recentlyScanned)
            }
        }
    }

    SkyBackground(phase = phase) {
        Box(Modifier.fillMaxSize().systemBarsPadding()) {
            Column(Modifier.fillMaxSize()) {
                SkyHeader(
                    title = stringResource(R.string.urls_title),
                    onSky = onSky,
                    isLoading = state.isScanning,
                    onRefresh = { viewModel.scan() },
                    onBack = onBack,
                    titleSize = 22,
                    backDescription = stringResource(R.string.common_back),
                    refreshDescription = stringResource(R.string.common_refresh),
                )
                if (state.missingScope) {
                    Box(Modifier.fillMaxSize()) {
                        SkyEmptyState(
                            Icons.Outlined.TravelExplore,
                            stringResource(R.string.scope_missing), onSky, stringResource(R.string.common_refresh),
                        ) { }
                    }
                } else {
                    Column(
                        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Card {
                            OutlinedTextField(
                                value = state.url,
                                onValueChange = viewModel::setUrl,
                                label = { Text(stringResource(R.string.urls_input_label)) },
                                placeholder = { Text("example.com") },
                                singleLine = true,
                                modifier = Modifier.fillMaxWidth(),
                            )
                            Spacer(Modifier.height(10.dp))
                            Button(
                                onClick = { viewModel.scan() },
                                enabled = state.canScan,
                                modifier = Modifier.fillMaxWidth(),
                            ) {
                                if (state.isScanning) {
                                    CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                                    Spacer(Modifier.width(8.dp))
                                }
                                Text(
                                    stringResource(
                                        if (state.isScanning) R.string.urls_scanning else R.string.urls_start,
                                    ),
                                )
                            }
                            Spacer(Modifier.height(8.dp))
                            // 扫描是异步的，且记录会进 Cloudflare 公共扫描库，得说清楚
                            Text(
                                stringResource(R.string.urls_hint),
                                fontSize = 12.sp,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }

                        state.result?.let { result ->
                            val malicious = result.verdicts?.overall?.malicious == true
                            Card {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Icon(
                                        if (malicious) Icons.Filled.Warning else Icons.Filled.CheckCircle,
                                        contentDescription = null,
                                        tint = if (malicious) Color(0xFFC62828) else Color(0xFF2E7D32),
                                        modifier = Modifier.size(20.dp),
                                    )
                                    Spacer(Modifier.width(8.dp))
                                    Text(
                                        stringResource(
                                            if (malicious) R.string.urls_malicious else R.string.urls_clean,
                                        ),
                                        fontSize = 15.sp,
                                        fontWeight = FontWeight.SemiBold,
                                        color = MaterialTheme.colorScheme.onSurface,
                                    )
                                }
                                result.verdicts?.overall?.categories
                                    ?.mapNotNull { it.name }
                                    ?.takeIf { it.isNotEmpty() }
                                    ?.let {
                                        Text(
                                            it.joinToString("、"),
                                            fontSize = 12.sp,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        )
                                    }
                            }
                            Card {
                                InfoLine(stringResource(R.string.urls_final), result.page?.url ?: result.task?.effectiveUrl)
                                InfoLine("IP", result.page?.ip)
                                InfoLine("ASN", listOfNotNull(result.page?.asn, result.page?.asnname).joinToString(" ").ifBlank { null })
                                InfoLine(stringResource(R.string.urls_country), result.page?.country)
                                InfoLine(stringResource(R.string.urls_server), result.page?.server)
                                InfoLine(stringResource(R.string.urls_status_code), result.page?.statusCode?.toString())
                            }
                        }
                    }
                }
            }
            SnackbarHost(snackbarHostState, modifier = Modifier.align(Alignment.BottomCenter))
        }
    }
}

@Composable
private fun Card(content: @Composable () -> Unit) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        shape = RoundedCornerShape(16.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.padding(16.dp)) { content() }
    }
}

@Composable
private fun InfoLine(label: String, value: String?) {
    if (value.isNullOrBlank()) return
    Row(Modifier.padding(vertical = 2.dp)) {
        Text(label, fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.width(10.dp))
        Text(
            value,
            fontSize = 13.sp,
            fontFamily = FontFamily.Monospace,
            color = MaterialTheme.colorScheme.onSurface,
        )
    }
}
