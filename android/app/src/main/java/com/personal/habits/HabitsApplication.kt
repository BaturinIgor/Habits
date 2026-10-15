package com.personal.habits

import android.app.Application
import com.personal.habits.data.HabitRepository
import com.personal.habits.notifications.Notifications

class HabitsApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        HabitRepository.init(this)
        Notifications.ensureChannel(this)
    }
}
