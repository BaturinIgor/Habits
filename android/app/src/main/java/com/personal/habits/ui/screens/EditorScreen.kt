package com.personal.habits.ui.screens

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Archive
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.CreateNewFolder
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.Unarchive
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.TimePicker
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.personal.habits.data.Habit
import com.personal.habits.data.HabitRepository
import com.personal.habits.data.HabitSchedule
import com.personal.habits.data.ReminderTime
import com.personal.habits.data.Ru
import com.personal.habits.data.ScheduleKind
import com.personal.habits.data.Weekdays
import com.personal.habits.data.endDay
import com.personal.habits.data.habit
import com.personal.habits.data.onceDay
import com.personal.habits.data.sortedGroups
import com.personal.habits.data.startDay
import com.personal.habits.notifications.ReminderScheduler
import com.personal.habits.ui.IconCatalog
import com.personal.habits.ui.Palette
import com.personal.habits.ui.components.HabitIcon
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset

private fun LocalDate.toUtcMillis(): Long = atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()
private fun Long.utcMillisToLocalDate(): LocalDate = Instant.ofEpochMilli(this).atZone(ZoneOffset.UTC).toLocalDate()

private enum class DateField { START, END, ONCE }

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun EditorScreen(habitId: String?, onClose: () -> Unit, onDeleted: () -> Unit) {
    val context = LocalContext.current
    val original = remember(habitId) { habitId?.let { HabitRepository.data.value.habit(it) } }
    val groups = HabitRepository.data.value.sortedGroups

    val initial = remember(habitId) {
        original ?: Habit(
            iconValue = IconCatalog.symbols.random().first,
            colorIndex = Palette.colors.indices.random()
        )
    }
    var name by remember { mutableStateOf(initial.name) }
    var details by remember { mutableStateOf(initial.details) }
    var iconType by remember { mutableStateOf(initial.iconType) }
    var iconValue by remember { mutableStateOf(initial.iconValue) }
    var colorIndex by remember { mutableStateOf(initial.colorIndex) }
    var groupId by remember { mutableStateOf(initial.groupId) }
    var kind by remember { mutableStateOf(initial.schedule.kind) }
    var weekdays by remember { mutableStateOf(initial.schedule.weekdays) }
    var startDate by remember { mutableStateOf(initial.startDay()) }
    var hasEnd by remember { mutableStateOf(initial.endDay() != null) }
    var endDate by remember { mutableStateOf(initial.endDay() ?: initial.startDay().plusDays(30)) }
    var onceDate by remember { mutableStateOf(initial.onceDay()) }
    var hasReminder by remember { mutableStateOf(initial.reminder != null) }
    var reminder by remember { mutableStateOf(initial.reminder ?: ReminderTime(9, 0)) }

    var datePickerFor by remember { mutableStateOf<DateField?>(null) }
    var showTimePicker by remember { mutableStateOf(false) }
    var showNewGroup by remember { mutableStateOf(false) }
    var showDelete by remember { mutableStateOf(false) }
    var showIcons by remember { mutableStateOf(false) }

    val color = Palette.color(colorIndex)
    val canSave = name.isNotBlank() && (kind == ScheduleKind.ONCE || weekdays.isNotEmpty())
    val settings = HabitRepository.data.value.settings

    fun save() {
        val safeEnd = if (endDate.isBefore(startDate)) startDate else endDate
        val habit = initial.copy(
            name = name.trim(),
            details = details.trim(),
            iconType = iconType,
            iconValue = iconValue,
            colorIndex = colorIndex,
            groupId = groupId,
            schedule = HabitSchedule(
                kind = kind,
                weekdays = weekdays,
                startDate = startDate.toString(),
                endDate = if (kind == ScheduleKind.REPEATING && hasEnd) safeEnd.toString() else null,
                onceDate = onceDate.toString(),
            ),
            reminder = if (hasReminder) reminder else null,
        )
        HabitRepository.upsertHabit(habit)
        ReminderScheduler.reschedule(context)
        onClose()
    }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = { Text(if (original == null) "Новая привычка" else "Изменить привычку") },
                navigationIcon = {
                    IconButton(onClick = onClose) { Icon(Icons.Rounded.Close, contentDescription = "Отмена") }
                },
                actions = {
                    TextButton(onClick = { save() }, enabled = canSave) {
                        Text("Готово", fontWeight = FontWeight.SemiBold)
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background)
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .imePadding()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp)
                .padding(bottom = 40.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            // Название и иконка
            FormCard {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(modifier = Modifier.clip(RoundedCornerShape(18.dp)).clickable { showIcons = !showIcons }) {
                        HabitIcon(iconType, iconValue, color, 58.dp)
                    }
                    Spacer(Modifier.width(14.dp))
                    PlainField(
                        value = name,
                        onValueChange = { name = it },
                        placeholder = "Название привычки",
                        big = true,
                        modifier = Modifier.weight(1f)
                    )
                }
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                PlainField(
                    value = details,
                    onValueChange = { details = it },
                    placeholder = "Описание или мотивация (необязательно)",
                    modifier = Modifier.fillMaxWidth()
                )
            }

            // Оформление
            FormSection("Оформление") {
                LazyRow(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    itemsIndexed(Palette.colors) { index, c ->
                        val selected = index == colorIndex
                        val scale by animateFloatAsState(if (selected) 1.1f else 1f, label = "colorScale")
                        Box(
                            modifier = Modifier
                                .size(38.dp)
                                .scale(scale)
                                .clip(CircleShape)
                                .background(c)
                                .then(if (selected) Modifier.border(3.dp, Color.White.copy(alpha = 0.85f), CircleShape) else Modifier)
                                .clickable { colorIndex = index },
                            contentAlignment = Alignment.Center
                        ) {
                            if (selected) Icon(Icons.Rounded.Check, null, tint = Color.White, modifier = Modifier.size(18.dp))
                        }
                    }
                }
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                Row(
                    modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).clickable { showIcons = !showIcons }.padding(vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("Иконка", modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
                    HabitIcon(iconType, iconValue, color, 30.dp)
                }
                AnimatedVisibility(visible = showIcons, enter = expandVertically() + fadeIn(), exit = shrinkVertically() + fadeOut()) {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text("Символы", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        IconGrid(
                            count = IconCatalog.symbols.size,
                            isSelected = { iconType == "symbol" && IconCatalog.symbols[it].first == iconValue },
                            color = color,
                            onSelect = { iconType = "symbol"; iconValue = IconCatalog.symbols[it].first }
                        ) { index, selected ->
                            Icon(
                                IconCatalog.symbols[index].second,
                                contentDescription = null,
                                tint = if (selected) Color.White else MaterialTheme.colorScheme.onSurface,
                                modifier = Modifier.size(22.dp)
                            )
                        }
                        Text("Эмодзи", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        IconGrid(
                            count = IconCatalog.emoji.size,
                            isSelected = { iconType == "emoji" && IconCatalog.emoji[it] == iconValue },
                            color = color,
                            onSelect = { iconType = "emoji"; iconValue = IconCatalog.emoji[it] }
                        ) { index, _ ->
                            Text(IconCatalog.emoji[index], fontSize = 22.sp)
                        }
                    }
                }
            }

            // Расписание
            FormSection("Расписание") {
                SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                    SegmentedButton(
                        selected = kind == ScheduleKind.REPEATING,
                        onClick = { kind = ScheduleKind.REPEATING },
                        shape = SegmentedButtonDefaults.itemShape(0, 2)
                    ) { Text("Регулярно") }
                    SegmentedButton(
                        selected = kind == ScheduleKind.ONCE,
                        onClick = { kind = ScheduleKind.ONCE },
                        shape = SegmentedButtonDefaults.itemShape(1, 2)
                    ) { Text("Один раз") }
                }
                if (kind == ScheduleKind.ONCE) {
                    ValueRow("Дата", Ru.dayMonth(onceDate)) { datePickerFor = DateField.ONCE }
                } else {
                    WeekdayPicker(weekdays) { weekdays = it }
                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                    ValueRow("Начало", Ru.dayMonth(startDate)) { datePickerFor = DateField.START }
                    SwitchRow("Дата окончания", hasEnd) { hasEnd = it }
                    AnimatedVisibility(visible = hasEnd) {
                        ValueRow("Окончание", Ru.dayMonth(endDate)) { datePickerFor = DateField.END }
                    }
                }
            }

            // Уведомление
            FormSection("Уведомление") {
                SwitchRow("Напоминание", hasReminder) { hasReminder = it }
                AnimatedVisibility(visible = hasReminder) {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        ValueRow("Время", reminder.text) { showTimePicker = true }
                        Text(
                            if (settings.repeatCount == 0) "Одно уведомление в выбранное время."
                            else "Если не отметить, напомню ещё ${Ru.times(settings.repeatCount)} каждые ${settings.repeatIntervalMinutes} минут. Кнопка \"Готово\" в уведомлении остановит повторы.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }

            // Группа
            FormSection("Группа") {
                var expanded by remember { mutableStateOf(false) }
                Box {
                    ValueRow("Группа", groups.firstOrNull { it.id == groupId }?.name ?: "Без группы") { expanded = true }
                    DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                        DropdownMenuItem(text = { Text("Без группы") }, onClick = { groupId = null; expanded = false })
                        groups.forEach { g ->
                            DropdownMenuItem(text = { Text(g.name) }, onClick = { groupId = g.id; expanded = false })
                        }
                    }
                }
                Row(
                    modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).clickable { showNewGroup = true }.padding(vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(Icons.Rounded.CreateNewFolder, null, tint = MaterialTheme.colorScheme.primary)
                    Spacer(Modifier.width(10.dp))
                    Text("Новая группа", color = MaterialTheme.colorScheme.primary)
                }
            }

            if (original != null) {
                FormCard {
                    Row(
                        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).clickable {
                            HabitRepository.setArchived(original.id, !original.archived)
                            onClose()
                        }.padding(vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(if (original.archived) Icons.Rounded.Unarchive else Icons.Rounded.Archive, null, tint = MaterialTheme.colorScheme.primary)
                        Spacer(Modifier.width(10.dp))
                        Text(if (original.archived) "Вернуть из архива" else "Переместить в архив", color = MaterialTheme.colorScheme.primary)
                    }
                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                    Row(
                        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).clickable { showDelete = true }.padding(vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(Icons.Rounded.Delete, null, tint = MaterialTheme.colorScheme.error)
                        Spacer(Modifier.width(10.dp))
                        Text("Удалить привычку", color = MaterialTheme.colorScheme.error)
                    }
                }
                Text(
                    "Архивная привычка не показывается на главном экране и не присылает уведомления, но её история сохраняется.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 8.dp)
                )
            }
        }
    }

    datePickerFor?.let { field ->
        val current = when (field) {
            DateField.START -> startDate
            DateField.END -> endDate
            DateField.ONCE -> onceDate
        }
        val state = rememberDatePickerState(initialSelectedDateMillis = current.toUtcMillis())
        DatePickerDialog(
            onDismissRequest = { datePickerFor = null },
            confirmButton = {
                TextButton(onClick = {
                    state.selectedDateMillis?.let { millis ->
                        val picked = millis.utcMillisToLocalDate()
                        when (field) {
                            DateField.START -> startDate = picked
                            DateField.END -> endDate = picked
                            DateField.ONCE -> onceDate = picked
                        }
                    }
                    datePickerFor = null
                }) { Text("Готово") }
            },
            dismissButton = { TextButton(onClick = { datePickerFor = null }) { Text("Отмена") } }
        ) {
            DatePicker(state = state, showModeToggle = false)
        }
    }

    if (showTimePicker) {
        val state = rememberTimePickerState(initialHour = reminder.hour, initialMinute = reminder.minute, is24Hour = true)
        AlertDialog(
            onDismissRequest = { showTimePicker = false },
            confirmButton = {
                TextButton(onClick = {
                    reminder = ReminderTime(state.hour, state.minute)
                    showTimePicker = false
                }) { Text("Готово") }
            },
            dismissButton = { TextButton(onClick = { showTimePicker = false }) { Text("Отмена") } },
            text = {
                Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                    TimePicker(state = state)
                }
            }
        )
    }

    if (showNewGroup) {
        var groupName by remember { mutableStateOf("") }
        AlertDialog(
            onDismissRequest = { showNewGroup = false },
            title = { Text("Новая группа") },
            text = {
                OutlinedTextField(
                    value = groupName,
                    onValueChange = { groupName = it },
                    placeholder = { Text("Название") },
                    singleLine = true,
                    shape = RoundedCornerShape(14.dp)
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    groupId = HabitRepository.addGroup(groupName).id
                    showNewGroup = false
                }) { Text("Создать") }
            },
            dismissButton = { TextButton(onClick = { showNewGroup = false }) { Text("Отмена") } }
        )
    }

    if (showDelete && original != null) {
        AlertDialog(
            onDismissRequest = { showDelete = false },
            title = { Text("Удалить привычку?") },
            text = { Text("История отметок тоже будет удалена.") },
            confirmButton = {
                TextButton(onClick = {
                    showDelete = false
                    HabitRepository.deleteHabit(original.id)
                    onDeleted()
                }) { Text("Удалить", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { showDelete = false }) { Text("Отмена") } }
        )
    }
}

// region Элементы формы

@Composable
private fun FormCard(content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(22.dp))
            .background(MaterialTheme.colorScheme.surfaceContainer)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        content = content
    )
}

@Composable
private fun FormSection(title: String, content: @Composable ColumnScope.() -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(
            title.uppercase(),
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(start = 8.dp)
        )
        FormCard(content)
    }
}

@Composable
private fun PlainField(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    modifier: Modifier = Modifier,
    big: Boolean = false,
) {
    TextField(
        value = value,
        onValueChange = onValueChange,
        placeholder = { Text(placeholder) },
        modifier = modifier,
        textStyle = if (big) MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.SemiBold) else MaterialTheme.typography.bodyLarge,
        colors = TextFieldDefaults.colors(
            focusedContainerColor = Color.Transparent,
            unfocusedContainerColor = Color.Transparent,
            focusedIndicatorColor = Color.Transparent,
            unfocusedIndicatorColor = Color.Transparent,
        ),
        maxLines = if (big) 3 else 4,
    )
}

@Composable
private fun ValueRow(title: String, value: String, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .clickable(onClick = onClick)
            .padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(title, modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
        Box(
            modifier = Modifier
                .clip(RoundedCornerShape(10.dp))
                .background(MaterialTheme.colorScheme.surfaceContainerHighest)
                .padding(horizontal = 12.dp, vertical = 6.dp)
        ) {
            Text(value, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
        }
    }
}

@Composable
private fun SwitchRow(title: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(title, modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
        Switch(checked = checked, onCheckedChange = onChange)
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun WeekdayPicker(selection: Set<Int>, onChange: (Set<Int>) -> Unit) {
    val haptics = LocalHapticFeedback.current
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Weekdays.ordered.forEach { day ->
                val on = day in selection
                val bg by animateColorAsState(
                    if (on) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceContainerHighest,
                    label = "weekday"
                )
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .aspectRatio(1f)
                        .clip(CircleShape)
                        .background(bg)
                        .clickable {
                            haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                            onChange(if (on) selection - day else selection + day)
                        },
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        Weekdays.short(day),
                        style = MaterialTheme.typography.labelLarge,
                        fontWeight = FontWeight.SemiBold,
                        color = if (on) Color.White else MaterialTheme.colorScheme.onSurface
                    )
                }
            }
        }
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf("Каждый день" to Weekdays.all, "Будни" to Weekdays.workdays, "Выходные" to Weekdays.weekend).forEach { (title, days) ->
                val active = selection == days
                Text(
                    title,
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = if (active) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier
                        .clip(RoundedCornerShape(50))
                        .background(
                            if (active) MaterialTheme.colorScheme.primary.copy(alpha = 0.15f)
                            else MaterialTheme.colorScheme.surfaceContainerHighest
                        )
                        .clickable { onChange(days) }
                        .padding(horizontal = 12.dp, vertical = 7.dp)
                )
            }
        }
    }
}

@Composable
private fun IconGrid(
    count: Int,
    isSelected: (Int) -> Boolean,
    color: Color,
    onSelect: (Int) -> Unit,
    content: @Composable (index: Int, selected: Boolean) -> Unit,
) {
    val columns = 6
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        (0 until count).chunked(columns).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for (i in 0 until columns) {
                    val index = row.getOrNull(i)
                    Box(modifier = Modifier.weight(1f).aspectRatio(1f)) {
                        if (index != null) {
                            val selected = isSelected(index)
                            val bg by animateColorAsState(
                                if (selected) color else MaterialTheme.colorScheme.surfaceContainerHighest,
                                label = "iconBg"
                            )
                            Box(
                                modifier = Modifier
                                    .fillMaxSize()
                                    .clip(RoundedCornerShape(14.dp))
                                    .background(bg)
                                    .clickable { onSelect(index) },
                                contentAlignment = Alignment.Center
                            ) {
                                content(index, selected)
                            }
                        }
                    }
                }
            }
        }
    }
}

// endregion
