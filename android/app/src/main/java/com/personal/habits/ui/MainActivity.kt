package com.personal.habits.ui

import android.Manifest
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContentTransitionScope
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.BarChart
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Layers
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.personal.habits.data.HabitRepository
import com.personal.habits.notifications.Notifications
import com.personal.habits.notifications.ReminderScheduler
import com.personal.habits.ui.screens.DetailScreen
import com.personal.habits.ui.screens.EditorScreen
import com.personal.habits.ui.screens.GroupsScreen
import com.personal.habits.ui.screens.HabitsScreen
import com.personal.habits.ui.screens.OrderScreen
import com.personal.habits.ui.screens.SettingsScreen
import com.personal.habits.ui.screens.StatsScreen
import com.personal.habits.ui.screens.TodayScreen
import com.personal.habits.ui.theme.HabitsTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        HabitRepository.init(this)
        setContent {
            HabitsTheme {
                HabitsAppUi()
            }
        }
    }
}

private enum class TopTab(val route: String, val title: String, val icon: ImageVector) {
    Today("today", "Сегодня", Icons.Rounded.CheckCircle),
    Habits("habits", "Привычки", Icons.Rounded.Layers),
    Stats("stats", "Статистика", Icons.Rounded.BarChart),
    Settings("settings", "Настройки", Icons.Rounded.Settings),
}

object Routes {
    const val DETAIL = "habit/{id}"
    const val EDITOR = "edit?id={id}"
    const val GROUPS = "groups"
    const val ORDER = "order"

    fun detail(id: String) = "habit/$id"
    fun editor(id: String? = null) = if (id == null) "edit" else "edit?id=$id"
}

@Composable
fun HabitsAppUi() {
    val context = androidx.compose.ui.platform.LocalContext.current
    val navController = rememberNavController()
    val backStack by navController.currentBackStackEntryAsState()
    val route = backStack?.destination?.route
    val showBar = TopTab.entries.any { it.route == route }

    val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
        ReminderScheduler.reschedule(context)
    }
    LaunchedEffect(Unit) {
        Notifications.ensureChannel(context)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && !Notifications.hasPermission(context)) {
            permissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
        ReminderScheduler.reschedule(context)
    }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) {
        ReminderScheduler.reschedule(context)
    }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        contentWindowInsets = WindowInsets(0, 0, 0, 0),
        bottomBar = {
            if (showBar) {
                NavigationBar(containerColor = MaterialTheme.colorScheme.surfaceContainer) {
                    TopTab.entries.forEach { tab ->
                        NavigationBarItem(
                            selected = route == tab.route,
                            onClick = { navController.switchTab(tab.route) },
                            icon = { Icon(tab.icon, contentDescription = null) },
                            label = { Text(tab.title) },
                            colors = NavigationBarItemDefaults.colors(
                                indicatorColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.16f),
                                selectedIconColor = MaterialTheme.colorScheme.primary,
                                selectedTextColor = MaterialTheme.colorScheme.primary,
                            )
                        )
                    }
                }
            }
        }
    ) { padding ->
        NavHost(
            navController = navController,
            startDestination = TopTab.Today.route,
            modifier = Modifier
                .padding(bottom = padding.calculateBottomPadding())
                .consumeWindowInsets(PaddingValues(bottom = padding.calculateBottomPadding())),
            enterTransition = {
                if (isTabSwitch()) fadeIn(tween(220))
                else slideIntoContainer(AnimatedContentTransitionScope.SlideDirection.Start, tween(320)) + fadeIn(tween(320))
            },
            exitTransition = {
                if (isTabSwitch()) fadeOut(tween(180))
                else slideOutOfContainer(AnimatedContentTransitionScope.SlideDirection.Start, tween(320), targetOffset = { it / 4 }) + fadeOut(tween(240))
            },
            popEnterTransition = {
                if (isTabSwitch()) fadeIn(tween(220))
                else slideIntoContainer(AnimatedContentTransitionScope.SlideDirection.End, tween(320), initialOffset = { it / 4 }) + fadeIn(tween(320))
            },
            popExitTransition = {
                if (isTabSwitch()) fadeOut(tween(180))
                else slideOutOfContainer(AnimatedContentTransitionScope.SlideDirection.End, tween(320)) + fadeOut(tween(240))
            },
        ) {
            composable(TopTab.Today.route) {
                TodayScreen(
                    onOpenHabit = { navController.navigate(Routes.detail(it)) },
                    onNewHabit = { navController.navigate(Routes.editor()) },
                    onEditHabit = { navController.navigate(Routes.editor(it)) },
                    onOpenOrder = { navController.navigate(Routes.ORDER) },
                )
            }
            composable(TopTab.Habits.route) {
                HabitsScreen(
                    onOpenHabit = { navController.navigate(Routes.detail(it)) },
                    onNewHabit = { navController.navigate(Routes.editor()) },
                    onOpenOrder = { navController.navigate(Routes.ORDER) },
                )
            }
            composable(TopTab.Stats.route) {
                StatsScreen(onOpenHabit = { navController.navigate(Routes.detail(it)) })
            }
            composable(TopTab.Settings.route) {
                SettingsScreen(onOpenGroups = { navController.navigate(Routes.GROUPS) })
            }
            composable(
                Routes.DETAIL,
                arguments = listOf(navArgument("id") { type = NavType.StringType }),
            ) { entry ->
                DetailScreen(
                    habitId = entry.arguments?.getString("id").orEmpty(),
                    onBack = { navController.popBackStack() },
                    onEdit = { navController.navigate(Routes.editor(it)) },
                )
            }
            composable(
                Routes.EDITOR,
                arguments = listOf(navArgument("id") {
                    type = NavType.StringType
                    nullable = true
                    defaultValue = null
                }),
                enterTransition = { slideInVertically(tween(340)) { it / 3 } + fadeIn(tween(300)) + scaleIn(tween(340), initialScale = 0.98f) },
                exitTransition = { fadeOut(tween(200)) },
                popEnterTransition = { fadeIn(tween(200)) },
                popExitTransition = { slideOutVertically(tween(300)) { it / 3 } + fadeOut(tween(260)) + scaleOut(tween(300), targetScale = 0.98f) },
            ) { entry ->
                EditorScreen(
                    habitId = entry.arguments?.getString("id"),
                    onClose = { navController.popBackStack() },
                    onDeleted = { navController.popBackStack() },
                )
            }
            composable(Routes.GROUPS) {
                GroupsScreen(onBack = { navController.popBackStack() })
            }
            composable(Routes.ORDER) {
                OrderScreen(onBack = { navController.popBackStack() })
            }
        }
    }
}

private fun AnimatedContentTransitionScope<androidx.navigation.NavBackStackEntry>.isTabSwitch(): Boolean {
    val tabs = TopTab.entries.map { it.route }
    return initialState.destination.route in tabs && targetState.destination.route in tabs
}

private fun NavHostController.switchTab(route: String) {
    navigate(route) {
        popUpTo(graph.findStartDestination().id) { saveState = true }
        launchSingleTop = true
        restoreState = true
    }
}
