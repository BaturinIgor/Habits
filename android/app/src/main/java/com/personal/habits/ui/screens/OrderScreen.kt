package com.personal.habits.ui.screens

import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.DragHandle
import androidx.compose.material.icons.rounded.Notifications
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.personal.habits.data.Habit
import com.personal.habits.data.HabitRepository
import com.personal.habits.data.activeHabits
import com.personal.habits.ui.Palette
import com.personal.habits.ui.components.HabitIcon
import com.personal.habits.ui.components.SectionHeader

private val RowHeight = 64.dp
private val RowSpacing = 8.dp

/**
 * Экран порядка привычек. Привычки с напоминанием стоят по времени и не двигаются,
 * остальные перетаскиваются за ручку справа.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun OrderScreen(onBack: () -> Unit) {
    val data by HabitRepository.data.collectAsStateWithLifecycle()
    val sections = makeSections(data.activeHabits, data)
    val showHeaders = sections.size > 1 || sections.firstOrNull()?.key != "ungrouped"

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = { Text("Порядок") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Rounded.ArrowBack, contentDescription = "Назад")
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
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp)
                .padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(RowSpacing)
        ) {
            Text(
                "Привычки с напоминанием идут по времени. Остальные стоят после них, их можно перетащить за ручку.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp)
            )
            sections.forEach { section ->
                if (showHeaders) SectionHeader(section.title)
                section.habits.filter { it.reminder != null }.forEach { habit ->
                    OrderRow(habit = habit, handle = null)
                }
                val movable = section.habits.filter { it.reminder == null }
                if (movable.isNotEmpty()) {
                    MovableBlock(movable) { ids -> HabitRepository.applyManualOrder(ids) }
                }
            }
        }
    }
}

/** Блок привычек без напоминания, которые можно перетаскивать. */
@Composable
private fun MovableBlock(habits: List<Habit>, onOrderChanged: (List<String>) -> Unit) {
    val haptics = LocalHapticFeedback.current
    val stepPx = with(LocalDensity.current) { (RowHeight + RowSpacing).toPx() }
    var order by remember(habits.map { it.id }) { mutableStateOf(habits.map { it.id }) }
    var draggingId by remember { mutableStateOf<String?>(null) }
    var dragOffset by remember { mutableFloatStateOf(0f) }
    val currentOnOrderChanged by rememberUpdatedState(onOrderChanged)

    Column(verticalArrangement = Arrangement.spacedBy(RowSpacing)) {
        order.forEach { id ->
            val habit = habits.firstOrNull { it.id == id } ?: return@forEach
            key(id) {
                val isDragging = id == draggingId
                val elevation by animateDpAsState(if (isDragging) 10.dp else 0.dp, label = "elevation")
                val scale by animateFloatAsState(if (isDragging) 1.03f else 1f, label = "scale")
                OrderRow(
                    habit = habit,
                    modifier = Modifier
                        .zIndex(if (isDragging) 1f else 0f)
                        .graphicsLayer {
                            translationY = if (isDragging) dragOffset else 0f
                            scaleX = scale
                            scaleY = scale
                        }
                        .shadow(elevation, RoundedCornerShape(20.dp)),
                    handle = Modifier.pointerInput(id) {
                        detectDragGestures(
                            onDragStart = {
                                draggingId = id
                                dragOffset = 0f
                                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                            },
                            onDrag = { change, amount ->
                                change.consume()
                                dragOffset += amount.y
                                val index = order.indexOf(id)
                                if (dragOffset > stepPx / 2 && index < order.lastIndex) {
                                    order = order.toMutableList().apply { add(index + 1, removeAt(index)) }
                                    dragOffset -= stepPx
                                    haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                                } else if (dragOffset < -stepPx / 2 && index > 0) {
                                    order = order.toMutableList().apply { add(index - 1, removeAt(index)) }
                                    dragOffset += stepPx
                                    haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                                }
                            },
                            onDragEnd = {
                                draggingId = null
                                dragOffset = 0f
                                currentOnOrderChanged(order)
                            },
                            onDragCancel = {
                                draggingId = null
                                dragOffset = 0f
                                currentOnOrderChanged(order)
                            }
                        )
                    }
                )
            }
        }
    }
}

@Composable
private fun OrderRow(habit: Habit, handle: Modifier?, modifier: Modifier = Modifier) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .height(RowHeight)
            .clip(RoundedCornerShape(20.dp))
            .background(MaterialTheme.colorScheme.surfaceContainer)
            .padding(start = 12.dp, end = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        HabitIcon(habit, Palette.color(habit.colorIndex), 38.dp)
        Spacer(Modifier.width(12.dp))
        Text(
            habit.name,
            modifier = Modifier.weight(1f),
            style = MaterialTheme.typography.bodyLarge,
            fontWeight = FontWeight.Medium,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
        val reminder = habit.reminder
        if (reminder != null) {
            Icon(
                Icons.Rounded.Notifications,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(14.dp)
            )
            Spacer(Modifier.width(3.dp))
            Text(
                reminder.text,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(Modifier.width(12.dp))
        }
        if (handle != null) {
            Box(
                modifier = Modifier
                    .size(48.dp)
                    .then(handle),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    Icons.Rounded.DragHandle,
                    contentDescription = "Перетащить",
                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}
