# ── Flutter & Dart ProGuard / R8 Rules ───────────────────
# Keep Flutter's generated code and callback methods that are
# invoked via reflection or native -> Dart JNI calls.

# ── Flutter engine ──
-keep class io.flutter.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.embedding.** { *; }

# ── Firebase ──
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# ── Keep data classes used in serialization / JSON ──
-keepattributes Signature
-keepattributes *Annotation*

# ── WooCommerce / WordPress API models (prevent stripping) ──
-keep class com.example.zzmoreApp.** { *; }

# ── Kotlin coroutines ──
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}

# -- Google Play Core (deferred components � not used, suppress R8 warnings) --
-dontwarn com.google.android.play.core.**
