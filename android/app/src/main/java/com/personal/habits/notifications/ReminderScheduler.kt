package com.personal.habits.notifications

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import com.personal.habits.data.AppData
import com.personal.habits.data.Habit
import com.personal.habits.data.HabitRepository
import com.personal.habits.data.isScheduledOn
import com.personal.habits.data.status
import java.time.LocalDate
import java.time.ZoneId

/**
 * Планирует напоминания одним точным будильником на ближайшее событие.
 *
 * Событие - это основное напоминание или один из повторов каждые N минут,
 * пока привычка за этот день не отмечена. Когда будильник срабатывает,
 * показываются все наступившие события и ставится следующий будильник.
 */
object ReminderScheduler {
    private const val PREFS = "reminders"
    private const val KEY_LAST_FIRED = "lastFiredAt"
    private const val HORIZON_DAYS = 30L
    private const val WINDOW_MS = 30_000L

    data class Occurrence(val habit: Habit, val day: LocalDate, val events: List<Long>)

    /** Неотмеченные появления привычек с напоминаниями в диапазоне дней. */
    private fun occurrences(data: AppData, from: LocalDate, to: LocalDate): List<Occurrence> {
        val zone = ZoneId.systemDefault()
        val repeatCount = data.settings.repeatCount.coerceIn(0, 40)
        val intervalMs = data.settings.repeatIntervalMinutes.coerceAtLeast(1) * 60_000L
        val result = mutableListOf<Occurrence>()
        for (habit in data.habits) {
            if (habit.archived) continue
            val reminder = habit.reminder ?: continue
            var day = from
            while (!day.isAfter(to)) {
                if (habit.isScheduledOn(day) && data.status(habit.id, day) == null) {
                    val first = day.atTime(reminder.hour, reminder.minute).atZone(zone).toInstant().toEpochMilli()
                    result += Occurrence(habit, day, (0..repeatCount).map { first + it * intervalMs })
                }
                day = day.plusDays(1)
            }
        }
        return result
    }

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun alarmIntent(context: Context): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            1,
            Intent(context, ReminderReceiver::class.java).setAction(ReminderReceiver.ACTION_FIRE),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

    fun canScheduleExact(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        val am = context.getSystemService(AlarmManager::class.java) ?: return false
        return am.canScheduleExactAlarms()
    }

    fun reschedule(context: Context) {
        val data = HabitRepository.data.value
        val now = System.currentTimeMillis()
        val prefs = prefs(context)
        if (!prefs.contains(KEY_LAST_FIRED)) {
            prefs.edit().putLong(KEY_LAST_FIRED, now).apply()
        }
        val after = maxOf(now, prefs.getLong(KEY_LAST_FIRED, now))
        val today = LocalDate.now()
        val next = occurrences(data, today.minusDays(1), today.plusDays(HORIZON_DAYS))
            .mapNotNull { occ -> occ.events.firstOrNull { it > after } }
            .minOrNull()

        val am = context.getSystemService(AlarmManager::class.java) ?: return
        val pi = alarmIntent(context)
        if (next == null) {
            am.cancel(pi)
            return
        }
        try {
            if (canScheduleExact(context)) {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next, pi)
            } else {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next, pi)
            }
        } catch (e: SecurityException) {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next, pi)
        }
    }

    /** Срабатывание будильника: показываем наступившие напоминания и ставим следующее. */
    fun onAlarm(context: Context) {
        val now = System.currentTimeMillis()
        val windowEnd = now + WINDOW_MS
        val prefs = prefs(context)
        val last = prefs.getLong(KEY_LAST_FIRED, now - 60_000L)
        val data = HabitRepository.data.value
        val today = LocalDate.now()

        for (occ in occurrences(data, today.minusDays(1), today)) {
            val dueIndex = occ.events.indexOfLast { it in (last + 1)..windowEnd }
            if (dueIndex >= 0) {
                Notifications.show(context, occ.habit, occ.day, dueIndex)
            }
        }
        prefs.edit().putLong(KEY_LAST_FIRED, windowEnd).apply()
        reschedule(context)
    }
}
