package com.personal.habits.ui

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.DirectionsRun
import androidx.compose.material.icons.automirrored.rounded.DirectionsWalk
import androidx.compose.material.icons.automirrored.rounded.MenuBook
import androidx.compose.material.icons.rounded.Alarm
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Bedtime
import androidx.compose.material.icons.rounded.Bolt
import androidx.compose.material.icons.rounded.Brush
import androidx.compose.material.icons.rounded.CalendarMonth
import androidx.compose.material.icons.rounded.Checklist
import androidx.compose.material.icons.rounded.Code
import androidx.compose.material.icons.rounded.Eco
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material.icons.rounded.EmojiEvents
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.FitnessCenter
import androidx.compose.material.icons.rounded.Hiking
import androidx.compose.material.icons.rounded.Home
import androidx.compose.material.icons.rounded.Laptop
import androidx.compose.material.icons.rounded.LocalCafe
import androidx.compose.material.icons.rounded.LocalFireDepartment
import androidx.compose.material.icons.rounded.MedicalServices
import androidx.compose.material.icons.rounded.Medication
import androidx.compose.material.icons.rounded.MusicNote
import androidx.compose.material.icons.rounded.Park
import androidx.compose.material.icons.rounded.PedalBike
import androidx.compose.material.icons.rounded.People
import androidx.compose.material.icons.rounded.Pets
import androidx.compose.material.icons.rounded.PhotoCamera
import androidx.compose.material.icons.rounded.Pool
import androidx.compose.material.icons.rounded.Psychology
import androidx.compose.material.icons.rounded.Public
import androidx.compose.material.icons.rounded.Restaurant
import androidx.compose.material.icons.rounded.Savings
import androidx.compose.material.icons.rounded.School
import androidx.compose.material.icons.rounded.SelfImprovement
import androidx.compose.material.icons.rounded.ShoppingCart
import androidx.compose.material.icons.rounded.Shower
import androidx.compose.material.icons.rounded.SmokeFree
import androidx.compose.material.icons.rounded.Spa
import androidx.compose.material.icons.rounded.SportsEsports
import androidx.compose.material.icons.rounded.Star
import androidx.compose.material.icons.rounded.Timer
import androidx.compose.material.icons.rounded.Translate
import androidx.compose.material.icons.rounded.WaterDrop
import androidx.compose.material.icons.rounded.WbSunny
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.vector.ImageVector

object Palette {
    val colors: List<Color> = listOf(
        Color(0xFFFF6B6B), // коралловый
        Color(0xFFFF9F43), // мандариновый
        Color(0xFFF7B731), // подсолнух
        Color(0xFF26C982), // мятный
        Color(0xFF2BBDB3), // бирюзовый
        Color(0xFF45AAF2), // небесный
        Color(0xFF4B7BEC), // синий
        Color(0xFF6C5CE7), // индиго
        Color(0xFFA55EEA), // фиолетовый
        Color(0xFFFD79A8), // розовый
        Color(0xFFEB3B5A), // малиновый
        Color(0xFF778CA3), // графит
    )

    fun color(index: Int): Color = colors[((index % colors.size) + colors.size) % colors.size]

    fun argb(index: Int): Int = color(index).toArgb()
}

object IconCatalog {
    val symbols: List<Pair<String, ImageVector>> = listOf(
        "water" to Icons.Rounded.WaterDrop,
        "run" to Icons.AutoMirrored.Rounded.DirectionsRun,
        "walk" to Icons.AutoMirrored.Rounded.DirectionsWalk,
        "gym" to Icons.Rounded.FitnessCenter,
        "bike" to Icons.Rounded.PedalBike,
        "yoga" to Icons.Rounded.SelfImprovement,
        "swim" to Icons.Rounded.Pool,
        "hike" to Icons.Rounded.Hiking,
        "spa" to Icons.Rounded.Spa,
        "heart" to Icons.Rounded.Favorite,
        "sleep" to Icons.Rounded.Bedtime,
        "sun" to Icons.Rounded.WbSunny,
        "book" to Icons.AutoMirrored.Rounded.MenuBook,
        "write" to Icons.Rounded.Edit,
        "mind" to Icons.Rounded.Psychology,
        "study" to Icons.Rounded.School,
        "language" to Icons.Rounded.Translate,
        "world" to Icons.Rounded.Public,
        "eco" to Icons.Rounded.Eco,
        "food" to Icons.Rounded.Restaurant,
        "coffee" to Icons.Rounded.LocalCafe,
        "pills" to Icons.Rounded.Medication,
        "health" to Icons.Rounded.MedicalServices,
        "music" to Icons.Rounded.MusicNote,
        "art" to Icons.Rounded.Brush,
        "photo" to Icons.Rounded.PhotoCamera,
        "laptop" to Icons.Rounded.Laptop,
        "code" to Icons.Rounded.Code,
        "money" to Icons.Rounded.Savings,
        "shop" to Icons.Rounded.ShoppingCart,
        "home" to Icons.Rounded.Home,
        "sparkles" to Icons.Rounded.AutoAwesome,
        "star" to Icons.Rounded.Star,
        "fire" to Icons.Rounded.LocalFireDepartment,
        "bolt" to Icons.Rounded.Bolt,
        "people" to Icons.Rounded.People,
        "pets" to Icons.Rounded.Pets,
        "park" to Icons.Rounded.Park,
        "shower" to Icons.Rounded.Shower,
        "nosmoke" to Icons.Rounded.SmokeFree,
        "alarm" to Icons.Rounded.Alarm,
        "timer" to Icons.Rounded.Timer,
        "calendar" to Icons.Rounded.CalendarMonth,
        "list" to Icons.Rounded.Checklist,
        "trophy" to Icons.Rounded.EmojiEvents,
        "game" to Icons.Rounded.SportsEsports,
    )

    private val byKey = symbols.toMap()

    fun icon(key: String): ImageVector = byKey[key] ?: Icons.Rounded.Star

    val emoji: List<String> = listOf(
        "💧", "🏃", "🚶", "💪", "🧘", "🚴", "🏊", "😴",
        "📚", "✍️", "🧠", "🎓", "🌍", "🗣️", "🥗", "🍎",
        "☕", "💊", "🦷", "🧴", "🚭", "🍷", "📵", "🧹",
        "🎸", "🎨", "📷", "💻", "💰", "🙏", "❤️", "🌿",
        "☀️", "🌙", "🔥", "⭐", "🎯", "🐶", "🌱", "😊",
    )
}
