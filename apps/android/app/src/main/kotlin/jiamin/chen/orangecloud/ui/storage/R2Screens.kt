package jiamin.chen.orangecloud.ui.storage

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.InsertDriveFile
import androidx.compose.material.icons.automirrored.outlined.OpenInNew
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Cloud
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Upload
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import jiamin.chen.orangecloud.R
import jiamin.chen.orangecloud.core.design.SkyBackground
import jiamin.chen.orangecloud.core.design.SkyEmptyState
import jiamin.chen.orangecloud.core.design.SkyHeader
import jiamin.chen.orangecloud.core.design.onSky
import jiamin.chen.orangecloud.core.design.rememberSkyPhase
import jiamin.chen.orangecloud.core.design.theme.OcOrange
import jiamin.chen.orangecloud.data.model.R2Object
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun R2BucketListScreen(
    onBack: () -> Unit,
    /** (桶名, jurisdiction)；默认区域的 jurisdiction 为 null。 */
    onOpenBucket: (String, String?) -> Unit,
    viewModel: R2BucketListViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val opState by viewModel.opState.collectAsStateWithLifecycle()
    val bandwidth by viewModel.bandwidth.collectAsStateWithLifecycle()
    val phase = rememberSkyPhase()
    val onSky = phase.onSky
    val snackbarHostState = remember { SnackbarHostState() }
    var showCreate by remember { mutableStateOf(false) }
    var toDelete by remember { mutableStateOf<jiamin.chen.orangecloud.data.model.R2Bucket?>(null) }
    val createSheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val createdMsg = stringResource(R.string.r2_created)
    val deletedMsg = stringResource(R.string.r2_deleted)
    val errMsg = stringResource(R.string.error_generic)

    LaunchedEffect(Unit) {
        viewModel.events.collect { event ->
            when (event) {
                StorageOpEvent.Created -> { showCreate = false; snackbarHostState.showSnackbar(createdMsg) }
                StorageOpEvent.Deleted -> { toDelete = null; snackbarHostState.showSnackbar(deletedMsg) }
                is StorageOpEvent.Error -> snackbarHostState.showSnackbar(event.message ?: errMsg)
            }
        }
    }

    SkyBackground(phase = phase) {
        Box(Modifier.fillMaxSize().systemBarsPadding()) {
            Column(Modifier.fillMaxSize()) {
                SkyHeader(
                    title = stringResource(R.string.storage_r2),
                    onSky = onSky,
                    isLoading = state.isLoading,
                    onRefresh = { viewModel.load() },
                    onBack = onBack,
                    titleSize = 22,
                    backDescription = stringResource(R.string.common_back),
                    refreshDescription = stringResource(R.string.common_refresh),
                )
                // 账户级近 30 天带宽（best-effort，拿不到就不显示）
                if (!state.missingScope) {
                    bandwidth?.let { R2BandwidthCard(it, Modifier.padding(horizontal = 16.dp, vertical = 4.dp)) }
                }
                StorageListBody(state, onSky, Icons.Outlined.Cloud, stringResource(R.string.r2_empty), { viewModel.load() }) { bucket ->
                    StorageRow(
                        Icons.Outlined.Cloud,
                        bucket.name,
                        bucket.location,
                        onClick = { onOpenBucket(bucket.name, bucket.jurisdictionOrNull) },
                        onLongClick = if (viewModel.canWrite) ({ toDelete = bucket }) else null,
                        badge = jurisdictionLabel(bucket.jurisdiction),
                    )
                }
            }
            if (viewModel.canWrite) {
                FloatingActionButton(
                    onClick = { showCreate = true },
                    containerColor = OcOrange,
                    contentColor = Color.White,
                    modifier = Modifier.align(Alignment.BottomEnd).padding(20.dp),
                ) {
                    Icon(Icons.Outlined.Add, contentDescription = stringResource(R.string.r2_create_title))
                }
            }
            SnackbarHost(snackbarHostState, modifier = Modifier.align(Alignment.BottomCenter))
        }
    }

    if (showCreate) {
        R2CreateSheet(
            isCreating = opState.isCreating,
            sheetState = createSheetState,
            onCreate = { name -> viewModel.create(name) },
            onDismiss = { showCreate = false },
        )
    }
    toDelete?.let { bucket ->
        R2DeleteDialog(
            bucket = bucket,
            isDeleting = opState.isDeleting,
            onConfirm = { viewModel.delete(bucket) },
            onDismiss = { toDelete = null },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun R2ObjectListScreen(
    onBack: () -> Unit,
    onOpenSettings: () -> Unit,
    viewModel: R2ObjectListViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val previewState by viewModel.previewState.collectAsStateWithLifecycle()
    val phase = rememberSkyPhase()
    val onSky = phase.onSky
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val snackbarHostState = remember { SnackbarHostState() }
    var detailObject by remember { mutableStateOf<R2Object?>(null) }

    var copyMoveTarget by remember { mutableStateOf<R2Object?>(null) }

    val uploadedMsg = stringResource(R.string.r2_uploaded)
    val deletedMsg = stringResource(R.string.r2_deleted)
    val noAppMsg = stringResource(R.string.r2_no_app)
    val copiedMsg = stringResource(R.string.r2_copied)
    val movedMsg = stringResource(R.string.r2_moved)
    val verifyFailMsg = stringResource(R.string.r2_move_verify_fail)
    val previewFailMsg = stringResource(R.string.r2_preview_unsupported)

    LaunchedEffect(Unit) {
        viewModel.events.collect { event ->
            when (event) {
                R2Event.Uploaded -> snackbarHostState.showSnackbar(uploadedMsg)
                R2Event.Deleted -> {
                    detailObject = null
                    viewModel.clearPreview()
                    snackbarHostState.showSnackbar(deletedMsg)
                }
                R2Event.PreviewUnsupported -> snackbarHostState.showSnackbar(previewFailMsg)
                R2Event.Copied -> { copyMoveTarget = null; snackbarHostState.showSnackbar(copiedMsg) }
                R2Event.Moved -> { copyMoveTarget = null; snackbarHostState.showSnackbar(movedMsg) }
                R2Event.MoveVerifyFailed -> snackbarHostState.showSnackbar(verifyFailMsg)
                is R2Event.Error -> snackbarHostState.showSnackbar(event.message ?: noAppMsg)
            }
        }
    }

    // SAF 选取任意文件上传
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            val doc = withContext(Dispatchers.IO) {
                runCatching {
                    val name = queryDisplayName(context, uri) ?: "upload"
                    val mime = context.contentResolver.getType(uri) ?: "application/octet-stream"
                    val bytes = context.contentResolver.openInputStream(uri)!!.use { it.readBytes() }
                    Triple(name, mime, bytes)
                }.getOrNull()
            }
            if (doc != null) viewModel.upload(doc.first, doc.second, doc.third)
            else snackbarHostState.showSnackbar(noAppMsg)
        }
    }

    fun openObject(obj: R2Object) {
        scope.launch {
            val bytes = viewModel.objectBytes(obj.key) ?: return@launch
            val uri = withContext(Dispatchers.IO) {
                runCatching {
                    val dir = File(context.cacheDir, "r2").apply { mkdirs() }
                    val file = File(dir, obj.key.substringAfterLast('/').ifBlank { "file" })
                    file.writeBytes(bytes)
                    FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
                }.getOrNull()
            }
            if (uri == null) {
                snackbarHostState.showSnackbar(noAppMsg)
                return@launch
            }
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, obj.httpMetadata?.contentType ?: "*/*")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            runCatching { context.startActivity(intent) }.onFailure {
                snackbarHostState.showSnackbar(noAppMsg)
            }
        }
    }

    SkyBackground(phase = phase) {
        Box(Modifier.fillMaxSize()) {
            Column(Modifier.fillMaxSize().systemBarsPadding()) {
                SkyHeader(
                    title = viewModel.bucket,
                    onSky = onSky,
                    isLoading = state.isLoading,
                    onRefresh = { viewModel.loadFirst() },
                    onBack = onBack,
                    titleSize = 22,
                    backDescription = stringResource(R.string.common_back),
                    refreshDescription = stringResource(R.string.common_refresh),
                )
                val isEmptyRoot = state.objects.isEmpty() && state.folders.isEmpty() && state.prefix.isEmpty()
                when {
                    state.missingScope ->
                        SkyEmptyState(Icons.Outlined.Lock, stringResource(R.string.scope_missing), onSky, stringResource(R.string.common_refresh)) { viewModel.loadFirst() }

                    isEmptyRoot && state.isLoading ->
                        Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator(color = onSky) }

                    isEmptyRoot && state.hasError ->
                        SkyEmptyState(Icons.AutoMirrored.Outlined.InsertDriveFile, stringResource(R.string.error_generic), onSky, stringResource(R.string.common_refresh)) { viewModel.loadFirst() }

                    isEmptyRoot ->
                        SkyEmptyState(Icons.AutoMirrored.Outlined.InsertDriveFile, stringResource(R.string.r2_objects_empty), onSky, stringResource(R.string.common_refresh)) { viewModel.loadFirst() }

                    else -> LazyColumn(
                        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 96.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        if (state.prefix.isEmpty()) {
                            item {
                                StorageRow(Icons.Outlined.Settings, stringResource(R.string.r2_bucket_settings), null, onClick = onOpenSettings)
                            }
                        }
                        if (state.prefix.isNotEmpty()) {
                            item {
                                StorageRow(Icons.Outlined.Folder, "..", stringResource(R.string.r2_folder_up), onClick = { viewModel.navigateUp() })
                            }
                        }
                        items(state.folders, key = { "dir:" + it.prefix }) { folder ->
                            StorageRow(Icons.Outlined.Folder, folder.name, stringResource(R.string.r2_folder), onClick = { viewModel.navigateInto(folder) })
                        }
                        items(state.objects, key = { it.key }) { obj ->
                            StorageRow(
                                Icons.AutoMirrored.Outlined.InsertDriveFile,
                                obj.key.removePrefix(state.prefix),
                                obj.size?.let { formatBytes(it) },
                                onClick = { detailObject = obj },
                            )
                        }
                        if (state.hasMore) {
                            item {
                                OutlinedButton(
                                    onClick = { viewModel.loadMore() },
                                    enabled = !state.isLoadingMore,
                                    modifier = Modifier.fillMaxWidth(),
                                ) {
                                    Text(stringResource(if (state.isLoadingMore) R.string.common_loading else R.string.common_load_more))
                                }
                            }
                        }
                    }
                }
            }

            if (state.canWrite) {
                FloatingActionButton(
                    onClick = { if (!state.isUploading) picker.launch(arrayOf("*/*")) },
                    containerColor = OcOrange,
                    contentColor = Color.White,
                    modifier = Modifier.align(Alignment.BottomEnd).padding(20.dp).systemBarsPadding(),
                ) {
                    if (state.isUploading) {
                        CircularProgressIndicator(Modifier.height(22.dp).width(22.dp), strokeWidth = 2.dp, color = Color.White)
                    } else {
                        Icon(Icons.Outlined.Upload, contentDescription = stringResource(R.string.r2_upload))
                    }
                }
            }
            SnackbarHost(snackbarHostState, Modifier.align(Alignment.BottomCenter).systemBarsPadding())
        }
    }

    detailObject?.let { obj ->
        // 打开详情即尝试内联预览（VM 内部按类型 + 大小上限决定是否真的下载）
        LaunchedEffect(obj.key) { viewModel.preview(obj) }
        ModalBottomSheet(
            onDismissRequest = { detailObject = null; viewModel.clearPreview() },
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        ) {
            ObjectDetail(
                obj = obj,
                canWrite = state.canWrite,
                isDownloading = state.isDownloading,
                preview = if (previewState.key == obj.key) previewState else R2PreviewState(),
                onOpen = { openObject(obj) },
                onCopyMove = { detailObject = null; viewModel.clearPreview(); copyMoveTarget = obj },
                onDelete = { viewModel.delete(obj.key) },
            )
        }
    }

    copyMoveTarget?.let { obj ->
        CopyMoveDialog(
            obj = obj,
            isCopying = state.isCopying,
            progress = state.copyProgress,
            onDismiss = { if (!state.isCopying) copyMoveTarget = null },
            onConfirm = { destKey, isMove ->
                viewModel.copyOrMove(obj.key, destKey, obj.httpMetadata?.contentType ?: "application/octet-stream", isMove)
            },
        )
    }
}

@Composable
private fun CopyMoveDialog(
    obj: R2Object,
    isCopying: Boolean,
    progress: Float,
    onDismiss: () -> Unit,
    onConfirm: (destKey: String, isMove: Boolean) -> Unit,
) {
    var dest by remember { mutableStateOf(obj.key) }
    val valid = dest.isNotBlank() && dest != obj.key
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.r2_copy_move)) },
        text = {
            Column {
                OutlinedTextField(
                    value = dest,
                    onValueChange = { dest = it },
                    label = { Text(stringResource(R.string.r2_dest_key)) },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    enabled = !isCopying,
                )
                if (isCopying) {
                    Spacer(Modifier.height(12.dp))
                    LinearProgressIndicator(progress = { progress }, modifier = Modifier.fillMaxWidth())
                }
            }
        },
        confirmButton = {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                TextButton(onClick = { onConfirm(dest.trim(), false) }, enabled = valid && !isCopying) {
                    Text(stringResource(R.string.r2_copy))
                }
                TextButton(onClick = { onConfirm(dest.trim(), true) }, enabled = valid && !isCopying) {
                    Text(stringResource(R.string.r2_move))
                }
            }
        },
        dismissButton = { TextButton(onClick = onDismiss, enabled = !isCopying) { Text(stringResource(R.string.common_cancel)) } },
    )
}

@Composable
private fun ObjectDetail(
    obj: R2Object,
    canWrite: Boolean,
    isDownloading: Boolean,
    preview: R2PreviewState,
    onOpen: () -> Unit,
    onCopyMove: () -> Unit,
    onDelete: () -> Unit,
) {
    var confirmDelete by remember { mutableStateOf(false) }
    Column(
        Modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp)
            .padding(bottom = 32.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(
            obj.key,
            fontSize = 16.sp,
            fontWeight = FontWeight.Bold,
            fontFamily = FontFamily.Monospace,
            color = MaterialTheme.colorScheme.onSurface,
        )
        obj.size?.let { MetaRow(stringResource(R.string.r2_meta_size), formatBytes(it)) }
        obj.httpMetadata?.contentType?.let { MetaRow(stringResource(R.string.r2_meta_type), it) }
        obj.storageClass?.let { MetaRow(stringResource(R.string.r2_meta_class), it) }
        obj.etag?.let { MetaRow(stringResource(R.string.r2_meta_etag), it, mono = true) }
        obj.lastModified?.let { MetaRow(stringResource(R.string.r2_meta_modified), it, mono = true) }

        Spacer(Modifier.height(4.dp))

        R2PreviewPane(preview)

        Spacer(Modifier.height(4.dp))

        Button(
            onClick = onOpen,
            enabled = !isDownloading,
            colors = ButtonDefaults.buttonColors(containerColor = OcOrange, contentColor = Color.White),
            modifier = Modifier.fillMaxWidth(),
        ) {
            if (isDownloading) {
                CircularProgressIndicator(Modifier.height(18.dp).width(18.dp), strokeWidth = 2.dp, color = Color.White)
            } else {
                Icon(Icons.AutoMirrored.Outlined.OpenInNew, contentDescription = null, modifier = Modifier.height(18.dp).width(18.dp))
            }
            Spacer(Modifier.width(8.dp))
            Text(stringResource(R.string.r2_download_open))
        }

        if (canWrite) {
            OutlinedButton(onClick = onCopyMove, modifier = Modifier.fillMaxWidth()) {
                Icon(Icons.Outlined.ContentCopy, contentDescription = null, modifier = Modifier.height(18.dp).width(18.dp))
                Spacer(Modifier.width(6.dp))
                Text(stringResource(R.string.r2_copy_move))
            }
        }

        if (canWrite) {
            if (confirmDelete) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(onClick = { confirmDelete = false }, modifier = Modifier.weight(1f)) {
                        Text(stringResource(R.string.common_cancel))
                    }
                    Button(
                        onClick = onDelete,
                        colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFE5484D), contentColor = Color.White),
                        modifier = Modifier.weight(1f),
                    ) {
                        Text(stringResource(R.string.r2_delete))
                    }
                }
            } else {
                TextButton(onClick = { confirmDelete = true }, modifier = Modifier.fillMaxWidth()) {
                    Icon(Icons.Outlined.Delete, contentDescription = null, tint = Color(0xFFE5484D), modifier = Modifier.height(18.dp).width(18.dp))
                    Spacer(Modifier.width(6.dp))
                    Text(stringResource(R.string.r2_delete), color = Color(0xFFE5484D))
                }
            }
        }
    }
}

@Composable
private fun MetaRow(label: String, value: String, mono: Boolean = false) {
    Row(Modifier.fillMaxWidth()) {
        Text(label, fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.width(12.dp))
        Spacer(Modifier.weight(1f))
        Text(
            value,
            fontSize = if (mono) 12.sp else 13.sp,
            fontFamily = if (mono) FontFamily.Monospace else FontFamily.Default,
            color = MaterialTheme.colorScheme.onSurface,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(2f),
            textAlign = androidx.compose.ui.text.style.TextAlign.End,
        )
    }
}

/** content:// 文档显示名（上传时保留原文件名）。 */
private fun queryDisplayName(context: Context, uri: Uri): String? =
    context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
        if (c.moveToFirst()) c.getString(0) else null
    }
