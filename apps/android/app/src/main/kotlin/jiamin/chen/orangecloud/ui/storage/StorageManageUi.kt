package jiamin.chen.orangecloud.ui.storage

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.SheetState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import jiamin.chen.orangecloud.R
import jiamin.chen.orangecloud.core.design.theme.OcOrange
import jiamin.chen.orangecloud.data.model.KVNamespace
import jiamin.chen.orangecloud.data.model.R2Bucket

// MARK: - R2 桶

/** 创建 R2 桶底部表单：仅名称（小写字母/数字/连字符，3–63 位，服务端校验）。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun R2CreateSheet(
    isCreating: Boolean,
    sheetState: SheetState,
    onCreate: (name: String) -> Unit,
    onDismiss: () -> Unit,
) {
    var name by remember { mutableStateOf("") }
    val canCreate = name.trim().isNotEmpty() && !isCreating

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .imePadding()
                .padding(horizontal = 24.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Text(stringResource(R.string.r2_create_title), fontSize = 20.sp, fontWeight = FontWeight.Bold)
            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                label = { Text(stringResource(R.string.r2_name)) },
                singleLine = true,
                textStyle = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace),
                modifier = Modifier.fillMaxWidth(),
            )
            Text(
                stringResource(R.string.r2_name_hint),
                fontSize = 12.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Button(
                onClick = { onCreate(name.trim()) },
                enabled = canCreate,
                colors = ButtonDefaults.buttonColors(containerColor = OcOrange, contentColor = Color.White),
                modifier = Modifier.fillMaxWidth(),
            ) {
                if (isCreating) {
                    CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp, color = Color.White)
                    Spacer(Modifier.width(8.dp))
                }
                Text(stringResource(R.string.r2_create))
            }
        }
    }
}

/** 删除 R2 桶二次确认：必须原样输入桶名才启用删除。 */
@Composable
fun R2DeleteDialog(
    bucket: R2Bucket,
    isDeleting: Boolean,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
) {
    var typed by remember { mutableStateOf("") }
    val matches = typed.trim() == bucket.name

    AlertDialog(
        onDismissRequest = { if (!isDeleting) onDismiss() },
        title = { Text(stringResource(R.string.r2_delete_title)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(stringResource(R.string.r2_delete_warn, bucket.name), fontSize = 14.sp)
                OutlinedTextField(
                    value = typed,
                    onValueChange = { typed = it },
                    label = { Text(stringResource(R.string.r2_delete_confirm_label)) },
                    placeholder = { Text(bucket.name) },
                    singleLine = true,
                    textStyle = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace),
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        },
        confirmButton = {
            TextButton(onClick = onConfirm, enabled = matches && !isDeleting) {
                Text(stringResource(R.string.r2_delete_button), color = if (matches && !isDeleting) Color(0xFFE5484D) else MaterialTheme.colorScheme.onSurfaceVariant)
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss, enabled = !isDeleting) { Text(stringResource(R.string.common_cancel)) }
        },
    )
}

// MARK: - KV 命名空间

/** 创建 KV 命名空间底部表单：标题 + 数据驻留（不限 / 欧盟 / 美国）。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun KVCreateSheet(
    isCreating: Boolean,
    sheetState: SheetState,
    /** jurisdiction 为 null = 不限区域（请求体省略该字段）。 */
    onCreate: (title: String, jurisdiction: String?) -> Unit,
    onDismiss: () -> Unit,
) {
    var title by remember { mutableStateOf("") }
    var jurisdiction by remember { mutableStateOf<String?>(null) }
    val canCreate = title.trim().isNotEmpty() && !isCreating

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .imePadding()
                .padding(horizontal = 24.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Text(stringResource(R.string.kv_create_title), fontSize = 20.sp, fontWeight = FontWeight.Bold)
            OutlinedTextField(
                value = title,
                onValueChange = { title = it },
                label = { Text(stringResource(R.string.kv_title_label)) },
                singleLine = true,
                textStyle = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace),
                modifier = Modifier.fillMaxWidth(),
            )
            // 数据驻留：创建后不可更改；fedramp 不在移动端提供
            Text(stringResource(R.string.kv_jurisdiction), fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            val options = listOf(
                null to stringResource(R.string.kv_jurisdiction_any),
                "eu" to stringResource(R.string.r2_jurisdiction_eu),
                "us" to stringResource(R.string.r2_jurisdiction_us),
            )
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                options.forEachIndexed { index, (value, label) ->
                    SegmentedButton(
                        selected = jurisdiction == value,
                        onClick = { jurisdiction = value },
                        shape = SegmentedButtonDefaults.itemShape(index, options.size),
                    ) { Text(label, fontSize = 13.sp, maxLines = 1) }
                }
            }
            Button(
                onClick = { onCreate(title.trim(), jurisdiction) },
                enabled = canCreate,
                colors = ButtonDefaults.buttonColors(containerColor = OcOrange, contentColor = Color.White),
                modifier = Modifier.fillMaxWidth(),
            ) {
                if (isCreating) {
                    CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp, color = Color.White)
                    Spacer(Modifier.width(8.dp))
                }
                Text(stringResource(R.string.kv_create))
            }
        }
    }
}

/** 删除 KV 命名空间二次确认：必须原样输入标题才启用删除。 */
@Composable
fun KVDeleteDialog(
    namespace: KVNamespace,
    isDeleting: Boolean,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
) {
    var typed by remember { mutableStateOf("") }
    val matches = typed.trim() == namespace.title

    AlertDialog(
        onDismissRequest = { if (!isDeleting) onDismiss() },
        title = { Text(stringResource(R.string.kv_delete_title)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(stringResource(R.string.kv_delete_warn, namespace.title), fontSize = 14.sp)
                OutlinedTextField(
                    value = typed,
                    onValueChange = { typed = it },
                    label = { Text(stringResource(R.string.kv_delete_confirm_label)) },
                    placeholder = { Text(namespace.title) },
                    singleLine = true,
                    textStyle = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace),
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        },
        confirmButton = {
            TextButton(onClick = onConfirm, enabled = matches && !isDeleting) {
                Text(stringResource(R.string.kv_delete_button), color = if (matches && !isDeleting) Color(0xFFE5484D) else MaterialTheme.colorScheme.onSurfaceVariant)
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss, enabled = !isDeleting) { Text(stringResource(R.string.common_cancel)) }
        },
    )
}
