package com.personal.habits.notifications

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.personal.habits.data.CheckStatus
import com.personal.habits.data.HabitRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.time.LocalDate

private val receiverScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

/** Срабатывание точного будильника. */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        HabitRepository.init(context)
        ReminderScheduler.onAlarm(context)
    }

    companion object {
        const val ACTION_FIRE = "com.personal.habits.REMINDER_FIRE"
    }
}

/** Кнопки "Готово" и "Пропустить" в уведомлении. */
class ActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        HabitRepository.init(context)
        val habitId = intent.getStringExtra(EXTRA_HABIT_ID) ?: return
        val day = intent.getStringExtra(EXTRA_DAY)?.let { runCatching { LocalDate.parse(it) }.getOrNull() } ?: return
        val status = when (intent.action) {
            ACTION_DONE -> CheckStatus.DONE
            ACTION_SKIP -> CheckStatus.SKIPPED
            else -> return
        }
        val pending = goAsync()
        receiverScope.launch {
            try {
                HabitRepository.setStatus(habitId, day, status)
                HabitRepository.refreshWidgets()
            } finally {
                pending.finish()
            }
        }
    }

    companion object {
        const val ACTION_DONE = "com.personal.habits.ACTION_DONE"
        const val ACTION_SKIP = "com.personal.habits.ACTION_SKIP"
        const val EXTRA_HABIT_ID = "habitId"
        const val EXTRA_DAY = "day"
    }
}

/** После перезагрузки, обновления приложения или смены времени будильники нужно поставить заново. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        HabitRepository.init(context)
        ReminderScheduler.reschedule(context)
        val pending = goAsync()
        receiverScope.launch {
            try {
                HabitRepository.refreshWidgets()
            } finally {
                pending.finish()
            }
        }
    }
}
