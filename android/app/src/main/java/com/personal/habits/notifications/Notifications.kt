package com.personal.habits.notifications

import android.Manifest
import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.personal.habits.R
import com.personal.habits.data.Habit
import com.personal.habits.ui.MainActivity
import com.personal.habits.ui.Palette
import java.time.LocalDate

object Notifications {
    const val CHANNEL_ID = "reminders"

    fun ensureChannel(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            context.getString(R.string.channel_name),
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Напоминания и повторы, пока привычка не отмечена"
            enableVibration(true)
        }
        manager.createNotificationChannel(channel)
    }

    fun hasPermission(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    fun notificationId(habitId: String, day: LocalDate): Int = "$habitId|$day".hashCode()

    @SuppressLint("MissingPermission")
    fun show(context: Context, habit: Habit, day: LocalDate, index: Int) {
        if (!hasPermission(context)) return
        ensureChannel(context)
        val id = notificationId(habit.id, day)

        val title = if (habit.isEmoji) "${habit.iconValue} ${habit.name}" else habit.name
        val text = when {
            index > 0 -> "Напоминаю ещё раз. Отметь, когда сделаешь"
            habit.details.isNotBlank() -> habit.details
            else -> "Пора выполнить привычку"
        }

        val open = PendingIntent.getActivity(
            context,
            id,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setColor(Palette.argb(habit.colorIndex))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setAutoCancel(true)
            .setOnlyAlertOnce(false)
            .setContentIntent(open)
            .addAction(0, "Готово", actionIntent(context, habit.id, day, ActionReceiver.ACTION_DONE, id * 2))
            .addAction(0, "Пропустить", actionIntent(context, habit.id, day, ActionReceiver.ACTION_SKIP, id * 2 + 1))
            .build()

        NotificationManagerCompat.from(context).notify(id, notification)
    }

    private fun actionIntent(context: Context, habitId: String, day: LocalDate, action: String, requestCode: Int): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            requestCode,
            Intent(context, ActionReceiver::class.java)
                .setAction(action)
                .putExtra(ActionReceiver.EXTRA_HABIT_ID, habitId)
                .putExtra(ActionReceiver.EXTRA_DAY, day.toString()),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

    fun cancel(context: Context, habitId: String, day: LocalDate) {
        NotificationManagerCompat.from(context).cancel(notificationId(habitId, day))
    }
}
