package jiamin.chen.orangecloud.core.design

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import jiamin.chen.orangecloud.R

/**
 * Rulesets 写端点 ?dry_run=true 的校验结果（WAF 自定义规则 / 缓存规则编辑器共用）。
 * 编辑器在底部表单里，snackbar 会被表单挡住，故结果就地显示在表单内。
 */
sealed interface RuleValidation {
    data object Running : RuleValidation
    data object Passed : RuleValidation
    data class Failed(val message: String?) : RuleValidation
}

/** 表单内的校验结果行：进行中 / 「规则校验通过」/ CF 报错原文。 */
@Composable
fun RuleValidationResult(validation: RuleValidation?, modifier: Modifier = Modifier) {
    when (validation) {
        null -> Unit
        RuleValidation.Running -> Row(modifier, verticalAlignment = Alignment.CenterVertically) {
            CircularProgressIndicator(Modifier.size(14.dp), strokeWidth = 2.dp)
            Spacer(Modifier.width(8.dp))
            Text(stringResource(R.string.rule_validate), fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        RuleValidation.Passed -> Row(modifier, verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Outlined.CheckCircle, contentDescription = null, tint = Color(0xFF2FBF71), modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(6.dp))
            Text(stringResource(R.string.rule_validate_passed), fontSize = 13.sp, color = Color(0xFF2FBF71))
        }
        is RuleValidation.Failed -> Row(modifier, verticalAlignment = Alignment.Top) {
            Icon(Icons.Outlined.ErrorOutline, contentDescription = null, tint = Color(0xFFE5484D), modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(6.dp))
            Text(
                validation.message?.takeIf { it.isNotBlank() } ?: stringResource(R.string.error_generic),
                fontSize = 13.sp,
                color = Color(0xFFE5484D),
            )
        }
    }
}
