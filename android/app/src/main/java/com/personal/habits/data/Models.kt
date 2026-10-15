package com.personal.habits.data

import kotlinx.serialization.Serializable
import java.time.LocalDate
import java.util.UUID

@Serializable
enum class ScheduleKind { REPEATING, ONCE }

@Serializable
enum class CheckStatus { DONE, SKIPPED }

@Serializable
data class HabitSchedule(
    val kind: ScheduleKind = ScheduleKind.REPEATING,
    /** Дни недели по ISO: 1 = понедельник ... 7 = воскресенье. */
    val weekdays: Set<Int> = (1..7).toSet(),
    val startDate: String = LocalDate.now().toString(),
    val endDate: String? = null,
    val onceDate: String = LocalDate.now().toString(),
)

@Serializable
data class ReminderTime(val hour: Int = 9, val minute: Int = 0) {
    val text: String get() = "%02d:%02d".format(hour, minute)
    val minutesOfDay: Int get() = hour * 60 + minute
}

@Serializable
data class Habit(
    val id: String = UUID.randomUUID().toString(),
    val name: String = "",
    val details: String = "",
    /** "symbol" или "emoji". */
    val iconType: String = "symbol",
    val iconValue: String = "star",
    val colorIndex: Int = 0,
    val groupId: String? = null,
    val schedule: HabitSchedule = HabitSchedule(),
    val reminder: ReminderTime? = ReminderTime(9, 0),
    val createdAt: Long = System.currentTimeMillis(),
    val archived: Boolean = false,
    val sortOrder: Int = 0,
) {
    val isEmoji: Boolean get() = iconType == "emoji"
}

@Serializable
data class HabitGroup(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val sortOrder: Int = 0,
)

@Serializable
data class CheckIn(
    val status: CheckStatus? = null,
    val note: String? = null,
    val updatedAt: Long = System.currentTimeMillis(),
)

@Serializable
data class AppSettings(
    /** Сколько раз повторить напоминание, если привычка не отмечена. */
    val repeatCount: Int = 8,
    val repeatIntervalMinutes: Int = 15,
)

@Serializable
data class AppData(
    val version: Int = 1,
    val habits: List<Habit> = emptyList(),
    val groups: List<HabitGroup> = emptyList(),
    /** Ключ: "<habitId>|yyyy-MM-dd". */
    val checkIns: Map<String, CheckIn> = emptyMap(),
    val settings: AppSettings = AppSettings(),
)

data class NoteEntry(val day: LocalDate, val note: String)

// region Отметки

fun checkKey(habitId: String, day: LocalDate): String = "$habitId|$day"

fun AppData.checkIn(habitId: String, day: LocalDate): CheckIn? = checkIns[checkKey(habitId, day)]

fun AppData.status(habitId: String, day: LocalDate): CheckStatus? = checkIn(habitId, day)?.status

fun AppData.note(habitId: String, day: LocalDate): String = checkIn(habitId, day)?.note.orEmpty()

private fun AppData.storeCheckIn(key: String, entry: CheckIn): AppData {
    val map = checkIns.toMutableMap()
    if (entry.status == null && entry.note.isNullOrBlank()) map.remove(key) else map[key] = entry
    return copy(checkIns = map)
}

fun AppData.withStatus(habitId: String, day: LocalDate, status: CheckStatus?): AppData {
    val key = checkKey(habitId, day)
    val entry = (checkIns[key] ?: CheckIn()).copy(status = status, updatedAt = System.currentTimeMillis())
    return storeCheckIn(key, entry)
}

fun AppData.withNote(habitId: String, day: LocalDate, note: String): AppData {
    val key = checkKey(habitId, day)
    val trimmed = note.trim()
    val entry = (checkIns[key] ?: CheckIn()).copy(
        note = trimmed.ifEmpty { null },
        updatedAt = System.currentTimeMillis()
    )
    return storeCheckIn(key, entry)
}

fun AppData.withoutCheckIns(habitId: String): AppData =
    copy(checkIns = checkIns.filterKeys { !it.startsWith("$habitId|") })

fun AppData.notesFor(habitId: String): List<NoteEntry> {
    val prefix = "$habitId|"
    return checkIns
        .filter { it.key.startsWith(prefix) && !it.value.note.isNullOrBlank() }
        .mapNotNull { (key, value) ->
            runCatching { LocalDate.parse(key.removePrefix(prefix)) }.getOrNull()
                ?.let { NoteEntry(it, value.note.orEmpty()) }
        }
        .sortedByDescending { it.day }
}

// endregion

// region Выборки

val AppData.activeHabits: List<Habit>
    get() = habits.filter { !it.archived }.sortedBy { it.sortOrder }

val AppData.archivedHabits: List<Habit>
    get() = habits.filter { it.archived }.sortedBy { it.sortOrder }

val AppData.sortedGroups: List<HabitGroup>
    get() = groups.sortedBy { it.sortOrder }

fun AppData.habitsOn(day: LocalDate): List<Habit> = activeHabits.filter { it.isScheduledOn(day) }

fun AppData.habit(id: String): Habit? = habits.firstOrNull { it.id == id }

fun AppData.group(id: String?): HabitGroup? = id?.let { gid -> groups.firstOrNull { it.id == gid } }

// endregion
