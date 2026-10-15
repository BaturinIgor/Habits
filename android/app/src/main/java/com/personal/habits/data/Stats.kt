package com.personal.habits.data

import java.time.DayOfWeek
import java.time.LocalDate
import java.time.temporal.TemporalAdjusters

data class HabitStats(
    val currentStreak: Int = 0,
    val bestStreak: Int = 0,
    val completionRate: Double = 0.0,
    val totalDone: Int = 0,
)

data class DayProgress(val date: LocalDate, val done: Int, val total: Int) {
    val fraction: Float get() = if (total == 0) 0f else done.toFloat() / total
}

data class WeekRate(val weekStart: LocalDate, val rate: Float, val hasData: Boolean)

object Stats {
    private const val MAX_LOOKBACK = 1100L

    fun habit(habit: Habit, data: AppData, today: LocalDate = LocalDate.now()): HabitStats {
        var day = habit.firstDay()
        val earliest = today.minusDays(MAX_LOOKBACK)
        if (day.isBefore(earliest)) day = earliest
        var last = today
        habit.lastDay()?.let { if (it.isBefore(last)) last = it }

        var run = 0
        var best = 0
        var done = 0
        var counted = 0
        while (!day.isAfter(last)) {
            if (habit.isScheduledOn(day)) {
                when (data.status(habit.id, day)) {
                    CheckStatus.DONE -> {
                        run += 1
                        done += 1
                        counted += 1
                        if (run > best) best = run
                    }
                    CheckStatus.SKIPPED -> Unit
                    null -> if (day.isBefore(today)) {
                        run = 0
                        counted += 1
                    }
                }
            }
            day = day.plusDays(1)
        }
        return HabitStats(
            currentStreak = run,
            bestStreak = best,
            completionRate = if (counted > 0) done.toDouble() / counted else 0.0,
            totalDone = done,
        )
    }

    /** Выполнено и всего на день; пропущенные в "всего" не входят. */
    fun day(date: LocalDate, data: AppData): DayProgress {
        var done = 0
        var total = 0
        for (habit in data.habitsOn(date)) {
            when (data.status(habit.id, date)) {
                CheckStatus.DONE -> { done += 1; total += 1 }
                CheckStatus.SKIPPED -> Unit
                null -> total += 1
            }
        }
        return DayProgress(date, done, total)
    }

    fun lastDays(count: Int, data: AppData, today: LocalDate = LocalDate.now()): List<DayProgress> =
        (count - 1 downTo 0).map { day(today.minusDays(it.toLong()), data) }

    fun overallRate(days: Int, data: AppData, today: LocalDate = LocalDate.now()): Double {
        var done = 0
        var total = 0
        for (offset in 0 until days) {
            val p = day(today.minusDays(offset.toLong()), data)
            done += p.done
            total += if (offset == 0) p.done else p.total
        }
        return if (total == 0) 0.0 else done.toDouble() / total
    }

    fun startOfWeek(date: LocalDate): LocalDate = date.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))

    fun weeklyRates(habit: Habit, data: AppData, weeks: Int, today: LocalDate = LocalDate.now()): List<WeekRate> {
        val thisWeek = startOfWeek(today)
        return (weeks - 1 downTo 0).map { w ->
            val weekStart = thisWeek.minusWeeks(w.toLong())
            var done = 0
            var total = 0
            for (d in 0L until 7L) {
                val day = weekStart.plusDays(d)
                if (day.isAfter(today) || !habit.isScheduledOn(day)) continue
                when (data.status(habit.id, day)) {
                    CheckStatus.DONE -> { done += 1; total += 1 }
                    CheckStatus.SKIPPED -> Unit
                    null -> if (day.isBefore(today)) total += 1
                }
            }
            WeekRate(weekStart, if (total == 0) 0f else done.toFloat() / total, total > 0)
        }
    }
}
