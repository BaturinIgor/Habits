# Модели данных сериализуются в JSON, их имена полей должны сохраниться.
-keep class com.personal.habits.data.** { *; }
-keepclassmembers class com.personal.habits.data.** {
    *** Companion;
    kotlinx.serialization.KSerializer serializer(...);
}
-keepattributes *Annotation*, InnerClasses, Signature
-dontnote kotlinx.serialization.**

# Glance создаёт обработчики нажатий виджета по имени класса.
-keep class * implements androidx.glance.appwidget.action.ActionCallback { <init>(); }
-keep class com.personal.habits.widget.** { *; }
