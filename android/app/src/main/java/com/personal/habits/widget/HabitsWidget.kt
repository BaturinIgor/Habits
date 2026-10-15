package com.personal.habits.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.LocalSize
import androidx.glance.action.ActionParameters
import androidx.glance.action.actionParametersOf
import androidx.glance.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.LinearProgressIndicator
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.personal.habits.data.AppData
import com.personal.habits.data.CheckStatus
import com.personal.habits.data.Habit
import com.personal.habits.data.HabitRepository
import com.personal.habits.data.habitsOn
import com.personal.habits.data.status
import com.personal.habits.ui.MainActivity
import com.personal.habits.ui.Palette
import java.time.LocalDate

private val AccentLight = Color(0xFF6C5CE7)

class HabitsWidget : GlanceAppWidget() {

    override val sizeMode: SizeMode = SizeMode.Responsive(
        setOf(
            DpSize(110.dp, 60.dp),
            DpSize(110.dp, 110.dp),
            DpSize(250.dp, 110.dp),
            DpSize(250.dp, 200.dp),
            DpSize(250.dp, 300.dp),
        )
    )

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        HabitRepository.init(context)
        provideContent {
            // Подписка на данные: виджет перерисуется сразу после отметки.
            val data by HabitRepository.data.collectAsState()
            GlanceTheme {
                WidgetContent(data)
            }
        }
    }
}

class HabitsWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = HabitsWidget()
}

private val KeyHabit = ActionParameters.Key<String>("habitId")
private val KeyDay = ActionParameters.Key<String>("day")

class ToggleHabitAction : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        HabitRepository.init(context)
        val habitId = parameters[KeyHabit] ?: return
        val day = parameters[KeyDay]?.let { runCatching { LocalDate.parse(it) }.getOrNull() } ?: return
        HabitRepository.toggleDone(habitId, day)
        HabitRepository.refreshWidgets()
    }
}

@Composable
private fun WidgetContent(data: AppData) {
    val today = LocalDate.now()
    val items: List<Pair<Habit, CheckStatus?>> = data.habitsOn(today)
        .map { it to data.status(it.id, today) }
        .sortedWith(compareBy({ if (it.second == null) 0 else 1 }, { it.first.reminder?.minutesOfDay ?: 9999 }))
    val done = items.count { it.second == CheckStatus.DONE }
    val total = items.count { it.second != CheckStatus.SKIPPED }
    val fraction = if (total == 0) 0f else done.toFloat() / total
    val size = LocalSize.current

    val onSurface = GlanceTheme.colors.onSurface
    val secondary = GlanceTheme.colors.onSurfaceVariant
    val accent = GlanceTheme.colors.primary

    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .background(GlanceTheme.colors.widgetBackground)
            .cornerRadius(24.dp)
            .padding(14.dp)
            .clickable(actionStartActivity<MainActivity>())
    ) {
        Row(
            modifier = GlanceModifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "Сегодня",
                style = TextStyle(color = onSurface, fontSize = 15.sp, fontWeight = FontWeight.Bold),
                modifier = GlanceModifier.defaultWeight()
            )
            Text(
                text = if (total == 0) "-" else "$done из $total",
                style = TextStyle(color = secondary, fontSize = 13.sp, fontWeight = FontWeight.Medium)
            )
        }
        Spacer(GlanceModifier.height(8.dp))
        LinearProgressIndicator(
            progress = fraction,
            modifier = GlanceModifier.fillMaxWidth().height(6.dp),
            color = accent,
            backgroundColor = ColorProvider(AccentLight.copy(alpha = 0.2f))
        )

        if (size.height < 100.dp) return@Column

        Spacer(GlanceModifier.height(10.dp))
        if (items.isEmpty()) {
            Text(
                text = "На сегодня привычек нет",
                style = TextStyle(color = secondary, fontSize = 13.sp)
            )
            return@Column
        }

        if (size.width < 200.dp) {
            val next = items.firstOrNull { it.second == null }?.first
            Text(
                text = if (next == null) "Всё выполнено" else "Дальше",
                style = TextStyle(color = secondary, fontSize = 11.sp, fontWeight = FontWeight.Medium)
            )
            if (next != null) {
                Text(
                    text = next.name,
                    maxLines = 2,
                    style = TextStyle(color = onSurface, fontSize = 14.sp, fontWeight = FontWeight.Bold)
                )
            }
            return@Column
        }

        val limit = ((size.height.value - 70f) / 36f).toInt().coerceIn(1, 8)
        items.take(limit).forEach { (habit, status) ->
            WidgetRow(habit, status, today)
        }
        if (items.size > limit) {
            Text(
                text = "И ещё ${items.size - limit}",
                style = TextStyle(color = secondary, fontSize = 11.sp, fontWeight = FontWeight.Medium)
            )
        }
    }
}

@Composable
private fun WidgetRow(habit: Habit, status: CheckStatus?, day: LocalDate) {
    val color = Palette.color(habit.colorIndex)
    val onSurface = GlanceTheme.colors.onSurface
    val secondary = GlanceTheme.colors.onSurfaceVariant
    Row(
        modifier = GlanceModifier.fillMaxWidth().padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = GlanceModifier.size(26.dp).cornerRadius(8.dp).background(ColorProvider(color)),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = if (habit.isEmoji) habit.iconValue else habit.name.take(1).uppercase(),
                style = TextStyle(color = ColorProvider(Color.White), fontSize = 13.sp, fontWeight = FontWeight.Bold)
            )
        }
        Spacer(GlanceModifier.width(10.dp))
        Text(
            text = habit.name,
            maxLines = 1,
            style = TextStyle(
                color = if (status == null) onSurface else secondary,
                fontSize = 14.sp,
                fontWeight = FontWeight.Medium
            ),
            modifier = GlanceModifier.defaultWeight()
        )
        Box(
            modifier = GlanceModifier
                .size(28.dp)
                .cornerRadius(14.dp)
                .background(
                    when (status) {
                        CheckStatus.DONE -> ColorProvider(color)
                        CheckStatus.SKIPPED -> ColorProvider(Color.Gray.copy(alpha = 0.3f))
                        null -> ColorProvider(color.copy(alpha = 0.18f))
                    }
                )
                .clickable(
                    actionRunCallback<ToggleHabitAction>(
                        actionParametersOf(KeyHabit to habit.id, KeyDay to day.toString())
                    )
                ),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = when (status) {
                    CheckStatus.DONE -> "✓"
                    CheckStatus.SKIPPED -> "»"
                    null -> ""
                },
                style = TextStyle(color = ColorProvider(Color.White), fontSize = 14.sp, fontWeight = FontWeight.Bold)
            )
        }
    }
}
