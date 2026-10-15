package com.personal.habits.ui.screens

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.Archive
import androidx.compose.material.icons.rounded.CalendarMonth
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.ChevronLeft
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.EmojiEvents
import androidx.compose.material.icons.rounded.LocalFireDepartment
import androidx.compose.material.icons.rounded.Notifications
import androidx.compose.material.icons.rounded.PieChart
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.personal.habits.data.AppData
import com.personal.habits.data.CheckStatus
import com.personal.habits.data.Habit
import com.personal.habits.data.HabitRepository
import com.personal.habits.data.Ru
import com.personal.habits.data.ScheduleKind
import com.personal.habits.data.Stats
import com.personal.habits.data.Weekdays
import com.personal.habits.data.habit
import com.personal.habits.data.isScheduledOn
import com.personal.habits.data.note
import com.personal.habits.data.notesFor
import com.personal.habits.data.scheduleSummary
import com.personal.habits.data.status
import com.personal.habits.ui.Palette
import com.personal.habits.ui.components.AppCard
import com.personal.habits.ui.components.HabitIcon
import com.personal.habits.ui.components.StatTile
import java.time.LocalDate
import java.time.YearMonth

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DetailScreen(habitId: String, onBack: () -> Unit, onEdit: (String) -> Unit) {
    val data by HabitRepository.data.collectAsStateWithLifecycle()
    val habit = data.habit(habitId)
    var noteDay by remember { mutableStateOf<LocalDate?>(null) }

    LaunchedEffect(habit == null) {
        if (habit == null) onBack()
    }
    if (habit == null) return

    val color = Palette.color(habit.colorIndex)
    val stats = Stats.habit(habit, data)

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = { Text(habit.name, maxLines = 1) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Rounded.ArrowBack, contentDescription = "Назад")
                    }
                },
                actions = {
                    TextButton(onClick = { onEdit(habit.id) }) { Text("Изменить") }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background)
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp)
                .padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Header(habit, color)

            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                StatTile("Текущая серия", Ru.days(stats.currentStreak), Icons.Rounded.LocalFireDepartment, Color(0xFFFF9500), Modifier.weight(1f))
                StatTile("Лучшая серия", Ru.days(stats.bestStreak), Icons.Rounded.EmojiEvents, Color(0xFFF7B731), Modifier.weight(1f))
            }
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                StatTile("Выполнение", "${(stats.completionRate * 100).toInt()}%", Icons.Rounded.PieChart, color, Modifier.weight(1f))
                StatTile("Всего отметок", stats.totalDone.toString(), Icons.Rounded.CheckCircle, Color(0xFF26C982), Modifier.weight(1f))
            }

            MonthCalendar(habit, data, color, onNote = { noteDay = it })

            if (habit.schedule.kind == ScheduleKind.REPEATING) {
                WeeklyChart(habit, data, color)
            }

            NotesCard(habit, data, onOpen = { noteDay = it })
        }
    }

    noteDay?.let { day ->
        NoteSheet(habit = habit, day = day, onDismiss = { noteDay = null })
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Header(habit: Habit, color: Color) {
    Column(
        modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        HabitIcon(habit, color, 84.dp)
        Text(habit.name, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
        if (habit.details.isNotBlank()) {
            Text(habit.details, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
        }
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Chip(habit.scheduleSummary(), Icons.Rounded.CalendarMonth)
            habit.reminder?.let { Chip(it.text, Icons.Rounded.Notifications) }
            if (habit.archived) Chip("В архиве", Icons.Rounded.Archive)
        }
    }
}

@Composable
private fun Chip(text: String, icon: androidx.compose.ui.graphics.vector.ImageVector) {
    Row(
        modifier = Modifier
            .clip(RoundedCornerShape(50))
            .background(MaterialTheme.colorScheme.surfaceContainer)
            .padding(horizontal = 12.dp, vertical = 7.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(icon, null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(14.dp))
        Spacer(Modifier.width(5.dp))
        Text(text, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun MonthCalendar(habit: Habit, data: AppData, color: Color, onNote: (LocalDate) -> Unit) {
    var monthIndex by rememberSaveable { mutableStateOf(0) }
    val month = YearMonth.now().plusMonths(monthIndex.toLong())
    val haptics = LocalHapticFeedback.current

    AppCard(modifier = Modifier.fillMaxWidth()) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                AnimatedContent(
                    targetState = month,
                    transitionSpec = { fadeIn() togetherWith fadeOut() },
                    label = "monthTitle",
                    modifier = Modifier.weight(1f)
                ) {
                    Text(Ru.monthYear(it.atDay(1)), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                }
                FilledTonalIconButton(onClick = { monthIndex -= 1 }, modifier = Modifier.size(36.dp)) {
                    Icon(Icons.Rounded.ChevronLeft, contentDescription = "Предыдущий месяц")
                }
                Spacer(Modifier.width(8.dp))
                FilledTonalIconButton(onClick = { monthIndex += 1 }, modifier = Modifier.size(36.dp)) {
                    Icon(Icons.Rounded.ChevronRight, contentDescription = "Следующий месяц")
                }
            }
            Row {
                Weekdays.ordered.forEach {
                    Text(
                        Weekdays.short(it),
                        modifier = Modifier.weight(1f),
                        textAlign = TextAlign.Center,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            AnimatedContent(
                targetState = month,
                transitionSpec = {
                    val forward = targetState.isAfter(initialState)
                    (slideInHorizontally { if (forward) it / 3 else -it / 3 } + fadeIn()) togetherWith
                        (slideOutHorizontally { if (forward) -it / 3 else it / 3 } + fadeOut())
                },
                label = "month"
            ) { shown ->
                val leading = shown.atDay(1).dayOfWeek.value - 1
                val cells: List<LocalDate?> = List(leading) { null } + (1..shown.lengthOfMonth()).map { shown.atDay(it) }
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    cells.chunked(7).forEach { week ->
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            for (i in 0 until 7) {
                                val day = week.getOrNull(i)
                                Box(modifier = Modifier.weight(1f).aspectRatio(1f)) {
                                    if (day != null) {
                                        DayCell(
                                            habit = habit,
                                            data = data,
                                            day = day,
                                            color = color,
                                            onTap = {
                                                haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                                                HabitRepository.toggleDone(habit.id, day)
                                            },
                                            onNote = { onNote(day) }
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
                Legend(color, "Выполнено", filled = true)
                Legend(MaterialTheme.colorScheme.onSurfaceVariant, "Пропущено", filled = false)
                Legend(Color(0xFFFF3B30).copy(alpha = 0.4f), "Не сделано", filled = true)
            }
            Text(
                "Нажми на день, чтобы отметить. Удерживай, чтобы пропустить или добавить заметку.",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f)
            )
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun DayCell(
    habit: Habit,
    data: AppData,
    day: LocalDate,
    color: Color,
    onTap: () -> Unit,
    onNote: () -> Unit,
) {
    val today = LocalDate.now()
    val scheduled = habit.isScheduledOn(day)
    val status = data.status(habit.id, day)
    val hasNote = data.note(habit.id, day).isNotEmpty()
    val isToday = day == today
    val canEdit = scheduled && !day.isAfter(today)
    val missed = scheduled && status == null && day.isBefore(today)
    var menu by remember { mutableStateOf(false) }

    val fill by animateColorAsState(
        when {
            status == CheckStatus.DONE -> color
            missed -> Color(0xFFFF3B30).copy(alpha = 0.12f)
            else -> Color.Transparent
        },
        label = "dayFill"
    )
    val outline = MaterialTheme.colorScheme.onSurfaceVariant

    Box(
        modifier = Modifier
            .fillMaxSize()
            .clip(CircleShape)
            .background(fill)
            .then(
                when {
                    status == CheckStatus.SKIPPED -> Modifier
                    isToday && status != CheckStatus.DONE -> Modifier.border(2.dp, color, CircleShape)
                    scheduled && status == null && !missed -> Modifier.border(1.5.dp, color.copy(alpha = 0.35f), CircleShape)
                    else -> Modifier
                }
            )
            .combinedClickable(
                enabled = canEdit,
                onClick = onTap,
                onLongClick = { menu = true }
            ),
        contentAlignment = Alignment.Center
    ) {
        if (status == CheckStatus.SKIPPED) {
            Canvas(Modifier.fillMaxSize()) {
                drawCircle(
                    color = outline.copy(alpha = 0.6f),
                    radius = size.minDimension / 2 - 1.dp.toPx(),
                    style = Stroke(width = 1.5.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(6f, 6f)))
                )
            }
        }
        Text(
            day.dayOfMonth.toString(),
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = if (isToday) FontWeight.Bold else FontWeight.Medium,
            color = when {
                status == CheckStatus.DONE -> Color.White
                scheduled -> MaterialTheme.colorScheme.onSurface
                else -> MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.45f)
            }
        )
        if (hasNote) {
            Box(
                Modifier
                    .align(Alignment.BottomCenter)
                    .padding(bottom = 4.dp)
                    .size(4.dp)
                    .clip(CircleShape)
                    .background(if (status == CheckStatus.DONE) Color.White else color)
            )
        }
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            DropdownMenuItem(text = { Text("Выполнено") }, onClick = { menu = false; HabitRepository.setStatus(habit.id, day, CheckStatus.DONE) })
            DropdownMenuItem(text = { Text("Пропущено") }, onClick = { menu = false; HabitRepository.setStatus(habit.id, day, CheckStatus.SKIPPED) })
            DropdownMenuItem(text = { Text("Сбросить") }, onClick = { menu = false; HabitRepository.setStatus(habit.id, day, null) })
            DropdownMenuItem(text = { Text(if (hasNote) "Изменить заметку" else "Заметка") }, onClick = { menu = false; onNote() })
        }
    }
}

@Composable
private fun Legend(color: Color, title: String, filled: Boolean) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(
            Modifier
                .size(9.dp)
                .clip(CircleShape)
                .then(if (filled) Modifier.background(color) else Modifier.border(1.dp, color, CircleShape))
        )
        Spacer(Modifier.width(5.dp))
        Text(title, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun WeeklyChart(habit: Habit, data: AppData, color: Color) {
    val points = Stats.weeklyRates(habit, data, 12)
    AppCard(modifier = Modifier.fillMaxWidth()) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Последние 12 недель", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            Row(modifier = Modifier.fillMaxWidth().height(150.dp)) {
                Column(
                    modifier = Modifier.height(150.dp).padding(end = 6.dp),
                    verticalArrangement = Arrangement.SpaceBetween
                ) {
                    listOf("100%", "50%", "0%").forEach {
                        Text(it, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                val grid = MaterialTheme.colorScheme.outlineVariant
                val animated = points.map { p ->
                    animateFloatAsState(if (p.hasData) p.rate else 0f, label = "bar").value
                }
                Canvas(modifier = Modifier.weight(1f).height(150.dp)) {
                    val h = size.height
                    listOf(0f, 0.5f, 1f).forEach { level ->
                        val y = h - h * level
                        drawLine(grid, Offset(0f, y), Offset(size.width, y), strokeWidth = 1.dp.toPx())
                    }
                    val slot = size.width / points.size
                    val barW = slot * 0.6f
                    animated.forEachIndexed { i, rate ->
                        val barH = (h * rate).coerceAtLeast(if (points[i].hasData) 3.dp.toPx() else 0f)
                        drawRoundRect(
                            color = color,
                            topLeft = Offset(i * slot + (slot - barW) / 2, h - barH),
                            size = Size(barW, barH),
                            cornerRadius = CornerRadius(6.dp.toPx(), 6.dp.toPx())
                        )
                    }
                }
            }
            Row(modifier = Modifier.fillMaxWidth().padding(start = 34.dp)) {
                points.forEachIndexed { i, p ->
                    Text(
                        if (i % 3 == 0) Ru.shortDate(p.weekStart) else "",
                        modifier = Modifier.weight(1f),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        softWrap = false
                    )
                }
            }
        }
    }
}

@Composable
private fun NotesCard(habit: Habit, data: AppData, onOpen: (LocalDate) -> Unit) {
    val notes = data.notesFor(habit.id)
    AppCard(modifier = Modifier.fillMaxWidth()) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("Заметки", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            if (notes.isEmpty()) {
                Text(
                    "Пока пусто. Заметку можно добавить, удерживая карточку на главном экране или день в календаре.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            } else {
                notes.forEach { entry ->
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(16.dp))
                            .background(MaterialTheme.colorScheme.surfaceContainerHighest)
                            .clickable { onOpen(entry.day) }
                            .padding(12.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp)
                    ) {
                        Text(Ru.relativeDay(entry.day), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(entry.note, style = MaterialTheme.typography.bodyMedium)
                    }
                }
            }
        }
    }
}
