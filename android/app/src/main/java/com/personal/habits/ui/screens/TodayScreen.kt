package com.personal.habits.ui.screens

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material.icons.rounded.FastForward
import androidx.compose.material.icons.rounded.LocalFireDepartment
import androidx.compose.material.icons.rounded.Notifications
import androidx.compose.material.icons.automirrored.rounded.StickyNote2
import androidx.compose.material.icons.automirrored.rounded.Undo
import androidx.compose.material.icons.rounded.WbSunny
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberTopAppBarState
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
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.personal.habits.data.AppData
import com.personal.habits.data.CheckStatus
import com.personal.habits.data.DayProgress
import com.personal.habits.data.Habit
import com.personal.habits.data.HabitRepository
import com.personal.habits.data.Ru
import com.personal.habits.data.Stats
import com.personal.habits.data.activeHabits
import com.personal.habits.data.habitsOn
import com.personal.habits.data.note
import com.personal.habits.data.sortedGroups
import com.personal.habits.data.status
import com.personal.habits.ui.Palette
import com.personal.habits.ui.components.AppCard
import com.personal.habits.ui.components.CheckCircle
import com.personal.habits.ui.components.EmptyState
import com.personal.habits.ui.components.HabitIcon
import com.personal.habits.ui.components.ProgressRing
import com.personal.habits.ui.components.SectionHeader
import java.time.LocalDate

data class HabitSection(val key: String, val title: String, val habits: List<Habit>)

private data class DetailItem(
    val icon: androidx.compose.ui.graphics.vector.ImageVector?,
    val text: String,
    val accent: Color?,
)

/** Разбивает привычки по группам в порядке групп, без группы в конце. */
fun makeSections(habits: List<Habit>, data: AppData): List<HabitSection> {
    val result = mutableListOf<HabitSection>()
    val used = mutableSetOf<String>()
    for (group in data.sortedGroups) {
        val items = habits.filter { it.groupId == group.id }
        if (items.isEmpty()) continue
        used += items.map { it.id }
        result += HabitSection(group.id, group.name, items)
    }
    val rest = habits.filter { it.id !in used }
    if (rest.isNotEmpty()) result += HabitSection("ungrouped", "Без группы", rest)
    return result
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TodayScreen(
    onOpenHabit: (String) -> Unit,
    onNewHabit: () -> Unit,
    onEditHabit: (String) -> Unit,
) {
    val data by HabitRepository.data.collectAsStateWithLifecycle()
    var selectedEpochDay by rememberSaveable { mutableStateOf(LocalDate.now().toEpochDay()) }
    val selectedDay = LocalDate.ofEpochDay(selectedEpochDay)
    val today = LocalDate.now()
    val isToday = selectedDay == today
    val isFuture = selectedDay.isAfter(today)
    var noteFor by remember { mutableStateOf<Habit?>(null) }
    var deleteFor by remember { mutableStateOf<Habit?>(null) }
    val haptics = LocalHapticFeedback.current

    val scrollBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior(rememberTopAppBarState())

    Scaffold(
        modifier = Modifier.nestedScroll(scrollBehavior.nestedScrollConnection),
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            LargeTopAppBar(
                title = {
                    AnimatedContent(
                        targetState = if (isToday) "Сегодня" else Ru.relativeDay(selectedDay),
                        transitionSpec = { fadeIn() togetherWith fadeOut() },
                        label = "title"
                    ) { Text(it, maxLines = 1, overflow = TextOverflow.Ellipsis) }
                },
                actions = {
                    if (!isToday) {
                        TextButton(onClick = { selectedEpochDay = today.toEpochDay() }) { Text("Сегодня") }
                    }
                },
                colors = TopAppBarDefaults.largeTopAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                    scrolledContainerColor = MaterialTheme.colorScheme.background,
                ),
                scrollBehavior = scrollBehavior,
            )
        },
        floatingActionButton = {
            FloatingActionButton(
                onClick = onNewHabit,
                containerColor = MaterialTheme.colorScheme.primary,
                contentColor = Color.White,
                shape = RoundedCornerShape(20.dp)
            ) {
                Icon(Icons.Rounded.Add, contentDescription = "Новая привычка")
            }
        }
    ) { padding ->
        val habits = data.habitsOn(selectedDay)
        val sections = makeSections(habits, data)
        val showHeaders = sections.size > 1 || sections.firstOrNull()?.key != "ungrouped"

        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(top = padding.calculateTopPadding()),
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 96.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            item(key = "strip") {
                WeekStrip(
                    data = data,
                    selected = selectedDay,
                    onSelect = {
                        haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                        selectedEpochDay = it.toEpochDay()
                    }
                )
            }
            item(key = "progress") {
                DayProgressCard(Stats.day(selectedDay, data), isFuture)
            }
            if (habits.isEmpty()) {
                item(key = "empty") {
                    if (data.activeHabits.isEmpty()) {
                        EmptyState(
                            icon = Icons.Rounded.AutoAwesome,
                            title = "Начнём с первой привычки",
                            message = "Добавь привычку, выбери дни и время, и я напомню о ней.",
                            buttonTitle = "Добавить привычку",
                            onClick = onNewHabit
                        )
                    } else {
                        EmptyState(
                            icon = Icons.Rounded.WbSunny,
                            title = "Свободный день",
                            message = "На этот день привычек не запланировано."
                        )
                    }
                }
            }
            sections.forEach { section ->
                if (showHeaders) {
                    item(key = "header-${section.key}") {
                        SectionHeader(section.title, Modifier.animateItem())
                    }
                }
                items(section.habits, key = { it.id }) { habit ->
                    val status = data.status(habit.id, selectedDay)
                    HabitCard(
                        habit = habit,
                        status = status,
                        hasNote = data.note(habit.id, selectedDay).isNotEmpty(),
                        streak = Stats.habit(habit, data).currentStreak,
                        canToggle = !isFuture,
                        modifier = Modifier.animateItem(),
                        onOpen = { onOpenHabit(habit.id) },
                        onToggle = {
                            haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                            HabitRepository.toggleDone(habit.id, selectedDay)
                        },
                        onSkip = {
                            HabitRepository.setStatus(
                                habit.id,
                                selectedDay,
                                if (status == CheckStatus.SKIPPED) null else CheckStatus.SKIPPED
                            )
                        },
                        onNote = { noteFor = habit },
                        onEdit = { onEditHabit(habit.id) },
                        onDelete = { deleteFor = habit },
                    )
                }
            }
        }
    }

    noteFor?.let { habit ->
        NoteSheet(habit = habit, day = selectedDay, onDismiss = { noteFor = null })
    }

    deleteFor?.let { habit ->
        AlertDialog(
            onDismissRequest = { deleteFor = null },
            title = { Text("Удалить привычку?") },
            text = { Text("История отметок тоже будет удалена.") },
            confirmButton = {
                TextButton(onClick = {
                    HabitRepository.deleteHabit(habit.id)
                    deleteFor = null
                }) { Text("Удалить", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { deleteFor = null }) { Text("Отмена") } }
        )
    }
}

@Composable
private fun WeekStrip(data: AppData, selected: LocalDate, onSelect: (LocalDate) -> Unit) {
    val today = LocalDate.now()
    val days = remember(today) { (-60L..14L).map { today.plusDays(it) } }
    val state = rememberLazyListState()
    LaunchedEffect(Unit) {
        val index = days.indexOf(selected).coerceAtLeast(0)
        state.scrollToItem((index - 3).coerceAtLeast(0))
    }
    LazyRow(
        state = state,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        contentPadding = PaddingValues(vertical = 4.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        items(days, key = { it.toEpochDay() }) { day ->
            DayChip(
                day = day,
                isSelected = day == selected,
                isToday = day == today,
                progress = Stats.day(day, data),
                onClick = { onSelect(day) }
            )
        }
    }
}

@Composable
private fun DayChip(day: LocalDate, isSelected: Boolean, isToday: Boolean, progress: DayProgress, onClick: () -> Unit) {
    val primary = MaterialTheme.colorScheme.primary
    val background by animateColorAsState(
        if (isSelected) primary else MaterialTheme.colorScheme.surfaceContainer,
        label = "chipBg"
    )
    val scale by animateFloatAsState(
        if (isSelected) 1.05f else 1f,
        spring(dampingRatio = 0.6f, stiffness = Spring.StiffnessMedium),
        label = "chipScale"
    )
    val contentColor = if (isSelected) Color.White else MaterialTheme.colorScheme.onSurface
    Column(
        modifier = Modifier
            .scale(scale)
            .width(50.dp)
            .height(76.dp)
            .clip(RoundedCornerShape(18.dp))
            .background(background)
            .clickable(onClick = onClick),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Text(
            Ru.weekdayShort(day),
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.SemiBold,
            color = if (isSelected) Color.White.copy(alpha = 0.85f) else MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(Modifier.height(6.dp))
        Box(contentAlignment = Alignment.Center, modifier = Modifier.size(36.dp)) {
            ProgressRing(
                progress = progress.fraction,
                modifier = Modifier.size(36.dp),
                strokeWidth = 3.dp,
                color = if (isSelected) Color.White else primary,
                trackAlpha = when {
                    progress.total == 0 -> 0f
                    isSelected -> 0.3f
                    else -> 0.15f
                }
            )
            Text(
                day.dayOfMonth.toString(),
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Bold,
                color = if (!isSelected && isToday) primary else contentColor
            )
        }
    }
}

@Composable
private fun DayProgressCard(progress: DayProgress, isFuture: Boolean) {
    val allDone = progress.total > 0 && progress.done == progress.total
    val headline = when {
        progress.total == 0 -> "Свободный день"
        allDone -> "Всё выполнено!"
        else -> "${progress.done} из ${progress.total}"
    }
    val subtitle = when {
        progress.total == 0 -> "Можно отдохнуть"
        allDone -> "Отличная работа, так держать"
        isFuture -> "Запланировано " + Ru.habits(progress.total)
        else -> "Осталось " + Ru.habits(progress.total - progress.done)
    }
    AppCard(modifier = Modifier.fillMaxWidth(), padding = 18.dp) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(contentAlignment = Alignment.Center, modifier = Modifier.size(72.dp)) {
                ProgressRing(progress = progress.fraction, modifier = Modifier.size(72.dp), strokeWidth = 10.dp)
                AnimatedContent(
                    targetState = allDone,
                    transitionSpec = { (scaleIn() + fadeIn()) togetherWith (scaleOut() + fadeOut()) },
                    label = "ringCenter"
                ) { done ->
                    if (done) {
                        Icon(Icons.Rounded.Check, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(30.dp))
                    } else {
                        Text(
                            "${(progress.fraction * 100).toInt()}%",
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.Bold
                        )
                    }
                }
            }
            Spacer(Modifier.width(18.dp))
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                AnimatedContent(targetState = headline, label = "headline") {
                    Text(it, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                }
                Text(subtitle, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun HabitCard(
    habit: Habit,
    status: CheckStatus?,
    hasNote: Boolean,
    streak: Int,
    canToggle: Boolean,
    modifier: Modifier = Modifier,
    onOpen: () -> Unit,
    onToggle: () -> Unit,
    onSkip: () -> Unit,
    onNote: () -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
) {
    val color = Palette.color(habit.colorIndex)
    val isDone = status == CheckStatus.DONE
    var menuOpen by remember { mutableStateOf(false) }
    val haptics = LocalHapticFeedback.current
    val tint by animateColorAsState(
        if (isDone) color.copy(alpha = 0.14f) else Color.Transparent,
        label = "cardTint"
    )

    Box(modifier = modifier) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(24.dp))
                .background(MaterialTheme.colorScheme.surfaceContainer)
                .background(tint)
                .combinedClickable(
                    onClick = onOpen,
                    onLongClick = {
                        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                        menuOpen = true
                    }
                )
                .padding(14.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            HabitIcon(habit, if (status == CheckStatus.SKIPPED) color.copy(alpha = 0.45f) else color, 46.dp)
            Spacer(Modifier.width(14.dp))
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    habit.name,
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
                val details = mutableListOf<DetailItem>()
                if (status == CheckStatus.SKIPPED) details += DetailItem(null, "Пропущено", null)
                habit.reminder?.let { details += DetailItem(Icons.Rounded.Notifications, it.text, null) }
                if (streak > 0) details += DetailItem(Icons.Rounded.LocalFireDepartment, streak.toString(), Color(0xFFFF9500))
                if (hasNote) details += DetailItem(Icons.AutoMirrored.Rounded.StickyNote2, "", null)
                if (details.isNotEmpty()) {
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                        details.forEach { (icon, text, accent) ->
                            val c = accent ?: MaterialTheme.colorScheme.onSurfaceVariant
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                if (icon != null) {
                                    Icon(icon, contentDescription = null, tint = c, modifier = Modifier.size(13.dp))
                                    if (text.isNotEmpty()) Spacer(Modifier.width(3.dp))
                                }
                                if (text.isNotEmpty()) {
                                    Text(text, style = MaterialTheme.typography.labelMedium, color = c)
                                }
                            }
                        }
                    }
                }
            }
            Spacer(Modifier.width(10.dp))
            CheckCircle(
                status = status,
                color = color,
                size = 34.dp,
                enabled = canToggle,
                onClick = onToggle
            )
        }

        DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
            if (canToggle) {
                DropdownMenuItem(
                    text = { Text(if (isDone) "Снять отметку" else "Выполнено") },
                    leadingIcon = { Icon(if (isDone) Icons.AutoMirrored.Rounded.Undo else Icons.Rounded.Check, null) },
                    onClick = { menuOpen = false; onToggle() }
                )
                DropdownMenuItem(
                    text = { Text(if (status == CheckStatus.SKIPPED) "Отменить пропуск" else "Пропустить") },
                    leadingIcon = { Icon(Icons.Rounded.FastForward, null) },
                    onClick = { menuOpen = false; onSkip() }
                )
                DropdownMenuItem(
                    text = { Text(if (hasNote) "Изменить заметку" else "Добавить заметку") },
                    leadingIcon = { Icon(Icons.AutoMirrored.Rounded.StickyNote2, null) },
                    onClick = { menuOpen = false; onNote() }
                )
                HorizontalDivider()
            }
            DropdownMenuItem(
                text = { Text("Изменить привычку") },
                leadingIcon = { Icon(Icons.Rounded.Edit, null) },
                onClick = { menuOpen = false; onEdit() }
            )
            DropdownMenuItem(
                text = { Text("Удалить", color = MaterialTheme.colorScheme.error) },
                leadingIcon = { Icon(Icons.Rounded.Delete, null, tint = MaterialTheme.colorScheme.error) },
                onClick = { menuOpen = false; onDelete() }
            )
        }
    }
}
