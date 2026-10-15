package com.personal.habits.ui.screens

import android.Manifest
import android.annotation.SuppressLint
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.Alarm
import androidx.compose.material.icons.rounded.BatteryChargingFull
import androidx.compose.material.icons.rounded.Folder
import androidx.compose.material.icons.rounded.Notifications
import androidx.compose.material.icons.rounded.Remove
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberTopAppBarState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.personal.habits.data.HabitRepository
import com.personal.habits.data.Ru
import com.personal.habits.notifications.Notifications
import com.personal.habits.notifications.ReminderScheduler
import com.personal.habits.ui.components.softGradient

@SuppressLint("BatteryLife")
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(onOpenGroups: () -> Unit) {
    val context = LocalContext.current
    val data by HabitRepository.data.collectAsStateWithLifecycle()
    var refreshTick by remember { mutableIntStateOf(0) }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { refreshTick++ }

    val notificationsOn = remember(refreshTick) { Notifications.hasPermission(context) }
    val exactOn = remember(refreshTick) { ReminderScheduler.canScheduleExact(context) }
    val batteryFree = remember(refreshTick) {
        context.getSystemService(PowerManager::class.java)?.isIgnoringBatteryOptimizations(context.packageName) == true
    }
    val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
        refreshTick++
        ReminderScheduler.reschedule(context)
    }
    val scrollBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior(rememberTopAppBarState())

    val repeatCount = data.settings.repeatCount
    val interval = data.settings.repeatIntervalMinutes
    val repeatText = if (repeatCount == 0) "Без повторов" else {
        val minutes = repeatCount * interval
        val hours = minutes / 60
        val rest = minutes % 60
        val duration = listOfNotNull(
            if (hours > 0) "$hours ч" else null,
            if (rest > 0) "$rest мин" else null
        ).joinToString(" ")
        Ru.times(repeatCount) + ", в течение " + duration
    }

    Scaffold(
        modifier = Modifier.nestedScroll(scrollBehavior.nestedScrollConnection),
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            LargeTopAppBar(
                title = { Text("Настройки") },
                colors = TopAppBarDefaults.largeTopAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                    scrolledContainerColor = MaterialTheme.colorScheme.background,
                ),
                scrollBehavior = scrollBehavior
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(top = padding.calculateTopPadding())
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp)
                .padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp)
        ) {
            SettingsSection("Уведомления", footer = if (!notificationsOn) "Без разрешения напоминания не придут." else null) {
                SettingsRow(
                    icon = Icons.Rounded.Notifications,
                    iconColor = Color(0xFFFF3B30),
                    title = "Уведомления",
                    value = if (notificationsOn) "Включены" else "Выключены",
                    onClick = if (notificationsOn) null else {
                        {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                                permissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                            } else {
                                context.startActivity(
                                    Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                        .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                                )
                            }
                        }
                    }
                )
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                SettingsRow(
                    icon = Icons.Rounded.Alarm,
                    iconColor = Color(0xFFFF9500),
                    title = "Точное время",
                    value = if (exactOn) "Разрешено" else "Выключено",
                    onClick = if (exactOn || Build.VERSION.SDK_INT < Build.VERSION_CODES.S) null else {
                        {
                            context.startActivity(
                                Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:${context.packageName}"))
                            )
                        }
                    }
                )
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                SettingsRow(
                    icon = Icons.Rounded.BatteryChargingFull,
                    iconColor = Color(0xFF26C982),
                    title = "Работа в фоне",
                    value = if (batteryFree) "Без ограничений" else "Ограничена",
                    onClick = if (batteryFree) null else {
                        {
                            runCatching {
                                context.startActivity(
                                    Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:${context.packageName}"))
                                )
                            }
                        }
                    }
                )
            }

            SettingsSection(
                "Если не отметить",
                footer = "Пока привычка не отмечена, напоминание повторяется каждые $interval минут. Кнопки \"Готово\" и \"Пропустить\" в уведомлении останавливают повторы на этот день."
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text("Повторы напоминания", style = MaterialTheme.typography.bodyLarge)
                        Text(repeatText, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    FilledTonalIconButton(
                        onClick = { HabitRepository.setRepeatCount(repeatCount - 1) },
                        enabled = repeatCount > 0,
                        modifier = Modifier.size(38.dp)
                    ) { Icon(Icons.Rounded.Remove, contentDescription = "Меньше") }
                    Spacer(Modifier.width(8.dp))
                    FilledTonalIconButton(
                        onClick = { HabitRepository.setRepeatCount(repeatCount + 1) },
                        enabled = repeatCount < 16,
                        modifier = Modifier.size(38.dp)
                    ) { Icon(Icons.Rounded.Add, contentDescription = "Больше") }
                }
            }

            SettingsSection("Организация") {
                SettingsRow(
                    icon = Icons.Rounded.Folder,
                    iconColor = Color(0xFF45AAF2),
                    title = "Группы",
                    value = data.groups.size.toString(),
                    onClick = onOpenGroups,
                    chevron = true
                )
            }

            val version = runCatching {
                context.packageManager.getPackageInfo(context.packageName, 0).versionName
            }.getOrNull() ?: "1.0"
            SettingsSection("О приложении", footer = "Все данные хранятся только на этом телефоне.") {
                Row {
                    Text("Версия", modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
                    Text(version, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

@Composable
private fun SettingsSection(title: String, footer: String? = null, content: @Composable ColumnScope.() -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(
            title.uppercase(),
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(start = 8.dp)
        )
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(22.dp))
                .background(MaterialTheme.colorScheme.surfaceContainer)
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
            content = content
        )
        if (footer != null) {
            Text(
                footer,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 8.dp)
            )
        }
    }
}

@Composable
private fun SettingsRow(
    icon: ImageVector,
    iconColor: Color,
    title: String,
    value: String,
    onClick: (() -> Unit)?,
    chevron: Boolean = onClick != null,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier.size(30.dp).clip(RoundedCornerShape(9.dp)).background(iconColor.softGradient()),
            contentAlignment = Alignment.Center
        ) {
            Icon(icon, null, tint = Color.White, modifier = Modifier.size(18.dp))
        }
        Spacer(Modifier.width(12.dp))
        Text(title, modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
        Text(
            value,
            style = MaterialTheme.typography.bodyMedium,
            color = if (onClick != null) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant
        )
        if (chevron) {
            Icon(
                Icons.AutoMirrored.Rounded.KeyboardArrowRight,
                null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}
