# Модели данных сериализуются в JSON, их имена полей должны сохраниться.
-keep class com.personal.habits.data.** { *; }
-keepclassmembers class com.personal.habits.data.** {
    *** Companion;
    kotlinx.serialization.KSerializer serializer(...);
}
-keepattributes *Annotation*, InnerClasses, Signature
-dontnote kotlinx.serialization.**
