# ProGuard rules for Ishara app

# Flutter embedding
-keep class io.flutter.** { *; }

# JNI native bindings
-keepclasseswithmembernames class * {
    native <methods>;
}

# Llama Flutter Android
-keep class com.write4me.llama_flutter_android.** { *; }
-keep class kotlin.jvm.functions.Function1
-keepclassmembers class * implements kotlin.jvm.functions.Function1 {
    public java.lang.Object invoke(java.lang.Object);
}

# TensorFlow Lite
-keep class org.tensorflow.lite.** { *; }
-dontwarn org.tensorflow.lite.**

# Google ML Kit
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.**

# Camera Plugin
-keep class io.flutter.plugins.camera.** { *; }

# Flutter TTS
-keep class com.tundralabs.fluttertts.** { *; }

# SQLite & Drift
-keep class com.tekartik.sqflite.** { *; }
-keep class org.sqlite.** { *; }
-dontwarn org.sqlite.**
