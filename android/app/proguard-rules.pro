# R8 / ProGuard rules for release builds.
#
# Goal: keep native-bridge / reflection-using plugin code alive
# through R8 minification + obfuscation. Default Flutter app
# template ships without any rules, which works fine for pure
# Dart apps but breaks plugins that load classes via reflection
# at runtime.
#
# Update as new plugins are added. The auto-generated
# missing_rules.txt at build/app/outputs/mapping/release/ is a
# good starting point when something else breaks.

# -----------------------------------------------------------
# tflite_flutter — bundled MobileFaceNet model loaded via JNI.
# The GPU delegate is an optional API surface we don't link
# against (CPU inference only on this device tier).
# -----------------------------------------------------------
-dontwarn org.tensorflow.lite.gpu.**
-keep class org.tensorflow.lite.** { *; }
-keep interface org.tensorflow.lite.** { *; }

# -----------------------------------------------------------
# Google ML Kit — face detection plugin uses reflection to
# bind Flutter platform channels to Java classes.
# -----------------------------------------------------------
-keep class com.google_mlkit_commons.** { *; }
-keep class com.google_mlkit_face_detection.** { *; }
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.vision.** { *; }
-dontwarn com.google.mlkit.**

# -----------------------------------------------------------
# geolocator — Android background task scheduling uses
# reflection-based service registration.
# -----------------------------------------------------------
-keep class com.baseflow.geolocator.** { *; }

# -----------------------------------------------------------
# Apache Tika (transitive dep of file_picker for MIME
# detection) references JDK StAX classes that Android does
# not ship. Tika checks at runtime and falls back, so the
# warning is safe to silence.
# -----------------------------------------------------------
-dontwarn javax.xml.stream.**
-dontwarn java.beans.**
-dontwarn java.awt.**

# -----------------------------------------------------------
# General Flutter / Kotlin metadata that's used by plugin
# registration + Kotlin reflection.
# -----------------------------------------------------------
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses
-keepattributes Exceptions
-keep class kotlin.Metadata { *; }
