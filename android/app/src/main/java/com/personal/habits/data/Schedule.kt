package com.personal.habits.data

import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale

object Weekdays {
    /** ISO: 1 = понедельник ... 7 = воскресенье. */
    val ordered: List<Int> = (1..7).toList()
    val all: Set<Int> = (1..7).toSet()
    val workdays: Set<Int> = (1..5).toSet()
    val weekend: Set<Int> = setOf(6, 7)

    fun short(day: Int): String = when (day) {
        1 -> "Пн"
        2 -> "Вт"
        3 -> "Ср"
        4 -> "Чт"
        5 -> "Пт"
        6 -> "Сб"
        7 -> "Вс"
        else -> ""
    }
}

object Ru {
    val locale: Locale = Locale("ru", "RU")
    private val dayMonth = DateTimeFormatter.ofPattern("d MMMM", locale)
    private val dayMonthYear = DateTimeFormatter.ofPattern("d MMMM yyyy", locale)
    private val weekdayDayMonth = DateTimeFormatter.ofPattern("EEEE, d MMMM", locale)
    private val monthYear = DateTimeFormatter.ofPattern("LLLL yyyy", locale)
    private val shortDate = DateTimeFormatter.ofPattern("d MMM", locale)

    fun dayMonth(date: LocalDate): String =
        if (date.year != LocalDate.now().year) dayMonthYear.format(date) else dayMonth.format(date)

    fun weekdayDayMonth(date: LocalDate): String = weekdayDayMonth.format(date).capitalizeFirst()

    fun monthYear(date: LocalDate): String = monthYear.format(date).capitalizeFirst()

    fun shortDate(date: LocalDate): String = shortDate.format(date).replace(".", "")

    fun weekdayShort(date: LocalDate): String = Weekdays.short(date.dayOfWeek.value)

    fun relativeDay(date: LocalDate): String {
        val today = LocalDate.now()
        return when (date) {
            today -> "Сегодня"
            today.minusDays(1) -> "Вчера"
            today.plusDays(1) -> "Завтра"
            else -> weekdayDayMonth(date)
        }
    }

    fun plural(n: Int, one: String, few: String, many: String): String {
        val n10 = kotlin.math.abs(n) % 10
        val n100 = kotlin.math.abs(n) % 100
        return when {
            n10 == 1 && n100 != 11 -> one
            n10 in 2..4 && n100 !in 12..14 -> few
            else -> many
        }
    }

    fun days(n: Int) = "$n " + plural(n, "день", "дня", "дней")
    fun habits(n: Int) = "$n " + plural(n, "привычка", "привычки", "привычек")
    fun times(n: Int) = "$n " + plural(n, "раз", "раза", "раз")
}

fun String.capitalizeFirst(): String = replaceFirstChar { if (it.isLowerCase()) it.titlecase(Ru.locale) else it.toString() }

private fun String.toLocalDateOrNull(): LocalDate? = runCatching { LocalDate.parse(this) }.getOrNull()

fun Habit.startDay(): LocalDate = schedule.startDate.toLocalDateOrNull() ?: LocalDate.now()
fun Habit.onceDay(): LocalDate = schedule.onceDate.toLocalDateOrNull() ?: LocalDate.now()
fun Habit.endDay(): LocalDate? = schedule.endDate?.toLocalDateOrNull()

fun Habit.isScheduledOn(day: LocalDate): Boolean = when (schedule.kind) {
    ScheduleKind.ONCE -> day == onceDay()
    ScheduleKind.REPEATING -> {
        val end = endDay()
        !day.isBefore(startDay()) &&
            (end == null || !day.isAfter(end)) &&
            schedule.weekdays.contains(day.dayOfWeek.value)
    }
}

fun Habit.firstDay(): LocalDate = if (schedule.kind == ScheduleKind.ONCE) onceDay() else startDay()

fun Habit.lastDay(): LocalDate? = if (schedule.kind == ScheduleKind.ONCE) onceDay() else endDay()

fun Habit.hasEnded(today: LocalDate = LocalDate.now()): Boolean = lastDay()?.isBefore(today) == true

fun Habit.scheduleSummary(): String = when (schedule.kind) {
    ScheduleKind.ONCE -> "Один раз, " + Ru.dayMonth(onceDay())
    ScheduleKind.REPEATING -> {
        val days = schedule.weekdays
        var text = when (days) {
            Weekdays.all -> "Каждый день"
            Weekdays.workdays -> "По будням"
            Weekdays.weekend -> "По выходным"
            else -> Weekdays.ordered.filter { it in days }.joinToString(", ") { Weekdays.short(it) }
        }
        if (startDay().isAfter(LocalDate.now())) text += ", с " + Ru.dayMonth(startDay())
        endDay()?.let { text += ", до " + Ru.dayMonth(it) }
        text
    }
}
