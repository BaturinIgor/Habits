package com.personal.habits.ui.components

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.FastForward
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.personal.habits.data.CheckStatus
import com.personal.habits.data.Habit
import com.personal.habits.ui.IconCatalog

/** Мягкий вертикальный градиент на основе цвета привычки. */
fun Color.softGradient(): Brush = Brush.linearGradient(
    listOf(this.copy(alpha = 1f), lerpLighter(this)),
    start = Offset(0f, 0f),
    end = Offset(Float.POSITIVE_INFINITY, Float.POSITIVE_INFINITY)
)

private fun lerpLighter(c: Color): Color = Color(
    red = c.red + (1f - c.red) * 0.18f,
    green = c.green + (1f - c.green) * 0.18f,
    blue = c.blue + (1f - c.blue) * 0.18f,
    alpha = c.alpha
)

@Composable
fun HabitIcon(habit: Habit, color: Color, size: Dp = 44.dp) {
    HabitIcon(iconType = habit.iconType, iconValue = habit.iconValue, color = color, size = size)
}

@Composable
fun HabitIcon(iconType: String, iconValue: String, color: Color, size: Dp = 44.dp) {
    Box(
        modifier = Modifier
            .size(size)
            .clip(RoundedCornerShape(size * 0.32f))
            .background(color.softGradient()),
        contentAlignment = Alignment.Center
    ) {
        if (iconType == "emoji") {
            Text(text = iconValue, fontSize = (size.value * 0.48f).sp)
        } else {
            Icon(
                imageVector = IconCatalog.icon(iconValue),
                contentDescription = null,
                tint = Color.White,
                modifier = Modifier.size(size * 0.52f)
            )
        }
    }
}

@Composable
fun CheckCircle(
    status: CheckStatus?,
    color: Color,
    size: Dp = 34.dp,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(
        targetValue = when {
            pressed -> 0.82f
            status == CheckStatus.DONE -> 1.06f
            else -> 1f
        },
        animationSpec = spring(dampingRatio = 0.45f, stiffness = Spring.StiffnessMedium),
        label = "checkScale"
    )
    val fill by animateColorAsState(
        targetValue = when (status) {
            CheckStatus.DONE -> color
            CheckStatus.SKIPPED -> MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.18f)
            null -> Color.Transparent
        },
        label = "checkFill"
    )
    Box(
        modifier = Modifier
            .size(size)
            .scale(scale)
            .clip(CircleShape)
            .background(fill)
            .then(
                if (status == null) Modifier.border(size * 0.085f, color.copy(alpha = if (enabled) 0.6f else 0.25f), CircleShape)
                else Modifier
            )
            .clickable(interactionSource = interaction, indication = null, enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        when (status) {
            CheckStatus.DONE -> Icon(Icons.Rounded.Check, contentDescription = "Выполнено", tint = Color.White, modifier = Modifier.size(size * 0.6f))
            CheckStatus.SKIPPED -> Icon(Icons.Rounded.FastForward, contentDescription = "Пропущено", tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(size * 0.5f))
            null -> Unit
        }
    }
}

@Composable
fun ProgressRing(
    progress: Float,
    modifier: Modifier = Modifier,
    strokeWidth: Dp = 10.dp,
    color: Color = MaterialTheme.colorScheme.primary,
    trackAlpha: Float = 0.18f,
) {
    val animated by animateFloatAsState(
        targetValue = progress.coerceIn(0f, 1f),
        animationSpec = spring(dampingRatio = 0.8f, stiffness = Spring.StiffnessLow),
        label = "ring"
    )
    Canvas(modifier = modifier) {
        val stroke = strokeWidth.toPx()
        val inset = stroke / 2
        val arcSize = Size(size.width - stroke, size.height - stroke)
        drawArc(
            color = color.copy(alpha = trackAlpha),
            startAngle = 0f,
            sweepAngle = 360f,
            useCenter = false,
            topLeft = Offset(inset, inset),
            size = arcSize,
            style = Stroke(width = stroke)
        )
        if (animated > 0f) {
            drawArc(
                color = color,
                startAngle = -90f,
                sweepAngle = 360f * animated,
                useCenter = false,
                topLeft = Offset(inset, inset),
                size = arcSize,
                style = Stroke(width = stroke, cap = StrokeCap.Round)
            )
        }
    }
}

@Composable
fun AppCard(
    modifier: Modifier = Modifier,
    padding: Dp = 16.dp,
    content: @Composable () -> Unit,
) {
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(24.dp))
            .background(MaterialTheme.colorScheme.surfaceContainer)
            .padding(padding)
    ) {
        content()
    }
}

@Composable
fun StatTile(title: String, value: String, icon: ImageVector, color: Color, modifier: Modifier = Modifier) {
    AppCard(modifier = modifier, padding = 14.dp) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(
                modifier = Modifier
                    .size(30.dp)
                    .clip(CircleShape)
                    .background(color.softGradient()),
                contentAlignment = Alignment.Center
            ) {
                Icon(icon, contentDescription = null, tint = Color.White, modifier = Modifier.size(17.dp))
            }
            Column {
                Text(
                    text = value,
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1
                )
                Text(
                    text = title,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1
                )
            }
        }
    }
}

@Composable
fun SectionHeader(text: String, modifier: Modifier = Modifier) {
    Text(
        text = text.uppercase(),
        style = MaterialTheme.typography.labelMedium,
        fontWeight = FontWeight.SemiBold,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = modifier.padding(start = 8.dp, top = 6.dp, bottom = 2.dp)
    )
}

@Composable
fun EmptyState(
    icon: ImageVector,
    title: String,
    message: String,
    buttonTitle: String? = null,
    onClick: (() -> Unit)? = null,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 40.dp, horizontal = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(48.dp))
        Text(title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
        Text(
            message,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center
        )
        if (buttonTitle != null && onClick != null) {
            Spacer(Modifier.height(4.dp))
            Button(onClick = onClick, shape = RoundedCornerShape(50)) {
                Text(buttonTitle, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}
