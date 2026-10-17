package com.personal.habits.data

import android.content.Context
import android.util.Log
import androidx.glance.appwidget.updateAll
import com.personal.habits.notifications.Notifications
import com.personal.habits.notifications.ReminderScheduler
import com.personal.habits.widget.HabitsWidget
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import java.io.File
import java.time.LocalDate

/** Единственный источник данных: один JSON-файл в памяти приложения. */
object HabitRepository {
    private const val FILE_NAME = "habits-data.json"
    private const val TAG = "HabitRepository"

    private val json = Json {
        encodeDefaults = true
        ignoreUnknownKeys = true
        prettyPrint = false
    }

    private val lock = Any()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val _data = MutableStateFlow(AppData())
    val data: StateFlow<AppData> = _data.asStateFlow()

    @Volatile
    private var initialized = false
    private lateinit var appContext: Context

    fun init(context: Context) {
        if (initialized) return
        synchronized(lock) {
            if (initialized) return
            appContext = context.applicationContext
            _data.value = load()
            initialized = true
        }
    }

    private fun file(): File = File(appContext.filesDir, FILE_NAME)

    private fun load(): AppData {
        val f = file()
        if (!f.exists()) return AppData()
        return try {
            json.decodeFromString(AppData.serializer(), f.readText())
        } catch (e: Exception) {
            Log.e(TAG, "Не удалось прочитать данные", e)
            runCatching { f.copyTo(File(appContext.filesDir, "habits-data-broken-${System.currentTimeMillis()}.json")) }
            AppData()
        }
    }

    private fun save(value: AppData) {
        try {
            val target = file()
            val tmp = File(appContext.filesDir, "$FILE_NAME.tmp")
            tmp.writeText(json.encodeToString(AppData.serializer(), value))
            if (!tmp.renameTo(target)) {
                target.writeText(tmp.readText())
                tmp.delete()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Не удалось сохранить данные", e)
        }
    }

    /** Изменяет данные, сохраняет их, пересчитывает уведомления и обновляет виджет. */
    fun update(reschedule: Boolean = true, transform: (AppData) -> AppData) {
        synchronized(lock) {
            val newValue = transform(_data.value)
            _data.value = newValue
            save(newValue)
        }
        if (reschedule) ReminderScheduler.reschedule(appContext)
        scope.launch { refreshWidgets() }
    }

    suspend fun refreshWidgets() {
        runCatching { HabitsWidget().updateAll(appContext) }
            .onFailure { Log.w(TAG, "Не удалось обновить виджет", it) }
    }

    // region Привычки

    fun upsertHabit(habit: Habit) = update { d ->
        val index = d.habits.indexOfFirst { it.id == habit.id }
        if (index >= 0) {
            d.copy(habits = d.habits.toMutableList().also { it[index] = habit })
        } else {
            val order = (d.habits.maxOfOrNull { it.sortOrder } ?: -1) + 1
            d.copy(habits = d.habits + habit.copy(sortOrder = order))
        }
    }

    fun deleteHabit(id: String) = update { d ->
        d.copy(habits = d.habits.filterNot { it.id == id }).withoutCheckIns(id)
    }

    fun setArchived(id: String, archived: Boolean) = update { d ->
        d.copy(habits = d.habits.map { if (it.id == id) it.copy(archived = archived) else it })
    }

    /** Задаёт новый ручной порядок: переданные привычки обмениваются своими местами. */
    fun applyManualOrder(ids: List<String>) = update(reschedule = false) { d ->
        val orders = ids.mapNotNull { hid -> d.habits.firstOrNull { it.id == hid }?.sortOrder }.sorted()
        if (orders.size != ids.size) return@update d
        val position = ids.withIndex().associate { it.value to orders[it.index] }
        d.copy(habits = d.habits.map { h -> position[h.id]?.let { h.copy(sortOrder = it) } ?: h })
    }

    // endregion

    // region Группы

    fun addGroup(name: String): HabitGroup {
        val trimmed = name.trim()
        val group = HabitGroup(
            name = trimmed.ifEmpty { "Новая группа" },
            sortOrder = (data.value.groups.maxOfOrNull { it.sortOrder } ?: -1) + 1
        )
        update { d -> d.copy(groups = d.groups + group) }
        return group
    }

    fun renameGroup(id: String, name: String) {
        val trimmed = name.trim()
        if (trimmed.isEmpty()) return
        update { d -> d.copy(groups = d.groups.map { if (it.id == id) it.copy(name = trimmed) else it }) }
    }

    fun deleteGroup(id: String) = update { d ->
        d.copy(
            groups = d.groups.filterNot { it.id == id },
            habits = d.habits.map { if (it.groupId == id) it.copy(groupId = null) else it }
        )
    }

    fun moveGroup(id: String, delta: Int) = update { d ->
        val list = d.sortedGroups.toMutableList()
        val from = list.indexOfFirst { it.id == id }
        val to = from + delta
        if (from < 0 || to !in list.indices) return@update d
        list.add(to, list.removeAt(from))
        val orders = list.withIndex().associate { it.value.id to it.index }
        d.copy(groups = d.groups.map { it.copy(sortOrder = orders[it.id] ?: it.sortOrder) })
    }

    // endregion

    // region Отметки

    fun toggleDone(habitId: String, day: LocalDate) {
        val wasDone = data.value.status(habitId, day) == CheckStatus.DONE
        setStatus(habitId, day, if (wasDone) null else CheckStatus.DONE)
    }

    fun setStatus(habitId: String, day: LocalDate, status: CheckStatus?) {
        update { it.withStatus(habitId, day, status) }
        if (status != null) Notifications.cancel(appContext, habitId, day)
    }

    fun setNote(habitId: String, day: LocalDate, note: String) {
        synchronized(lock) {
            val newValue = _data.value.withNote(habitId, day, note)
            _data.value = newValue
            save(newValue)
        }
    }

    // endregion

    fun setRepeatCount(count: Int) = update { d ->
        d.copy(settings = d.settings.copy(repeatCount = count.coerceIn(0, 16)))
    }
}
