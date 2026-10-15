package com.personal.habits.ui.screens

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.BarChart
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.LocalFireDepartment
import androidx.compose.material.icons.rounded.PieChart
import androidx.compose.material.icons.rounded.Star
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberTopAppBarState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.personal.habits.data.AppData
import com.personal.habits.data.HabitRepository
import com.personal.habits.data.Ru
import com.personal.habits.data.Stats
import com.personal.habits.data.Weekdays
import com.personal.habits.data.activeHabits
import com.personal.habits.ui.Palette
import com.personal.habits.ui.components.AppCard
import com.personal.habits.ui.components.EmptyState
import com.personal.habits.ui.components.HabitIcon
import com.personal.habits.ui.components.StatTile
import java.time.LocalDate

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StatsScreen(onOpenHabit: (String) -> Unit) {
    val data by HabitRepository.data.collectAsStateWithLifecycle()
    val scrollBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior(rememberTopAppBarState())

    Scaffold(
        modifier = Modifier.nestedScroll(scrollBehavior.nestedScrollConnection),
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            LargeTopAppBar(
                title = { Text("Статистика") },
                colors = TopAppBarDefaults.largeTopAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                    scrolledContainerColor = MaterialTheme.colorScheme.background,
                ),
                scrollBehavior = scrollBehavior
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(top = padding.calculateTopPadding())
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp)
                .padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            if (data.activeHabits.isEmpty()) {
                EmptyState(
                    icon = Icons.Rounded.BarChart,
                    title = "Пока нечего считать",
                    message = "Статистика появится, когда ты начнёшь отмечать привычки."
                )
            } else {
                StatsContent(data, onOpenHabit)
            }
        }
    }
}

@Composable
private fun StatsContent(data: AppData, onOpenHabit: (String) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            val allStats = data.activeHabits.map { Stats.habit(it, data) }
            val today = Stats.day(LocalDate.now(), data)
            val rate30 = Stats.overallRate(30, data)
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                StatTile("Сегодня", "${today.done} из ${today.total}", Icons.Rounded.CheckCircle, MaterialTheme.colorScheme.primary, Modifier.weight(1f))
                StatTile("За 30 дней", "${(rate30 * 100).toInt()}%", Icons.Rounded.PieChart, Color(0xFF26C982), Modifier.weight(1f))
            }
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                StatTile("Лучшая серия сейчас", Ru.days(allStats.maxOfOrNull { it.currentStreak } ?: 0), Icons.Rounded.LocalFireDepartment, Color(0xFFFF9500), Modifier.weight(1f))
                StatTile("Всего отметок", allStats.sumOf { it.totalDone }.toString(), Icons.Rounded.Star, Color(0xFFF7B731), Modifier.weight(1f))
            }

            WeekBars(data)
            Heatmap(data)

            AppCard(modifier = Modifier.fillMaxWidth()) {
                Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    Text("По привычкам", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    data.activeHabits.zip(allStats).forEach { (habit, stats) ->
                        val color = Palette.color(habit.colorIndex)
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(14.dp))
                                .clickable { onOpenHabit(habit.id) }
                                .padding(vertical = 2.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            HabitIcon(habit, color, 38.dp)
                            Spacer(Modifier.width(12.dp))
                            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Text(
                                        habit.name,
                                        style = MaterialTheme.typography.bodyMedium,
                                        fontWeight = FontWeight.SemiBold,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis,
                                        modifier = Modifier.weight(1f)
                                    )
                                    if (stats.currentStreak > 0) {
                                        Icon(Icons.Rounded.LocalFireDepartment, null, tint = Color(0xFFFF9500), modifier = Modifier.size(14.dp))
                                        Text("${stats.currentStreak}", style = MaterialTheme.typography.labelMedium, color = Color(0xFFFF9500))
                                        Spacer(Modifier.width(8.dp))
                                    }
                                    Text(
                                        "${(stats.completionRate * 100).toInt()}%",
                                        style = MaterialTheme.typography.labelMedium,
                                        fontWeight = FontWeight.Bold,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                                val animated by animateFloatAsState(stats.completionRate.toFloat(), label = "rate")
                                LinearProgressIndicator(
                                    progress = { animated },
                                    modifier = Modifier.fillMaxWidth().height(6.dp).clip(RoundedCornerShape(3.dp)),
                                    color = color,
                                    trackColor = color.copy(alpha = 0.18f),
                                    strokeCap = StrokeCap.Round,
                                    gapSize = 0.dp,
                                    drawStopIndicator = {}
                                )
                            }
                        }
                    }
                }
            }
    }
}

@Composable
private fun WeekBars(data: AppData) {
    val days = Stats.lastDays(7, data)
    val primary = MaterialTheme.colorScheme.primary
    val track = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.18f)
    val maxTotal = (days.maxOfOrNull { it.total } ?: 0).coerceAtLeast(1)
    AppCard(modifier = Modifier.fillMaxWidth()) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Последние 7 дней", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            val animated = days.map { animateFloatAsState(it.done.toFloat() / maxTotal, label = "done").value }
            Canvas(modifier = Modifier.fillMaxWidth().height(140.dp)) {
                val slot = size.width / days.size
                val barW = slot * 0.55f
                val radius = CornerRadius(8.dp.toPx(), 8.dp.toPx())
                days.forEachIndexed { i, d ->
                    val x = i * slot + (slot - barW) / 2
                    val totalH = size.height * d.total / maxTotal
                    if (totalH > 0f) {
                        drawRoundRect(track, Offset(x, size.height - totalH), Size(barW, totalH), radius)
                    }
                    val doneH = size.height * animated[i]
                    if (doneH > 0f) {
                        drawRoundRect(primary, Offset(x, size.height - doneH), Size(barW, doneH), radius)
                    }
                }
            }
            Row(modifier = Modifier.fillMaxWidth()) {
                days.forEach {
                    Text(
                        Ru.weekdayShort(it.date),
                        modifier = Modifier.weight(1f),
                        textAlign = TextAlign.Center,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
                LegendDot(primary, "Выполнено")
                LegendDot(track, "Осталось")
            }
        }
    }
}

@Composable
private fun LegendDot(color: Color, title: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(9.dp).clip(RoundedCornerShape(3.dp)).background(color))
        Spacer(Modifier.width(5.dp))
        Text(title, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun Heatmap(data: AppData) {
    val weeks = 16
    val today = LocalDate.now()
    val start = Stats.startOfWeek(today).minusWeeks((weeks - 1).toLong())
    val primary = MaterialTheme.colorScheme.primary
    val empty = MaterialTheme.colorScheme.surfaceContainerHighest
    val outline = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f)

    AppCard(modifier = Modifier.fillMaxWidth()) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Активность за $weeks недель", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                Column(modifier = Modifier.width(18.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Weekdays.ordered.forEach {
                        Box(modifier = Modifier.fillMaxWidth().aspectRatio(1f, matchHeightConstraintsFirst = false), contentAlignment = Alignment.Center) {
                            Text(
                                if (it % 2 == 1) Weekdays.short(it) else "",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                maxLines = 1
                            )
                        }
                    }
                }
                for (w in 0 until weeks) {
                    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        for (d in 0 until 7) {
                            val date = start.plusDays((w * 7 + d).toLong())
                            val cellModifier = Modifier.fillMaxWidth().aspectRatio(1f).clip(RoundedCornerShape(3.dp))
                            if (date.isAfter(today)) {
                                Box(cellModifier)
                            } else {
                                val p = Stats.day(date, data)
                                val color = if (p.total == 0 || p.done == 0) empty else primary.copy(alpha = 0.2f + 0.8f * p.fraction)
                                Box(
                                    cellModifier
                                        .background(color)
                                        .then(if (date == today) Modifier.border(1.dp, outline, RoundedCornerShape(3.dp)) else Modifier)
                                )
                            }
                        }
                    }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Меньше", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                listOf(0f, 0.25f, 0.5f, 0.75f, 1f).forEach { level ->
                    Box(
                        Modifier
                            .size(11.dp)
                            .clip(RoundedCornerShape(3.dp))
                            .background(if (level == 0f) empty else primary.copy(alpha = 0.2f + 0.8f * level))
                    )
                }
                Text("Больше", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}
