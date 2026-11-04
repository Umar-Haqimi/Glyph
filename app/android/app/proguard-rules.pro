# Glyph R8 keep rules. Flutter's Gradle plugin already adds the Flutter engine rules.
# Keep annotations and generic signatures used by reflection-based libraries
# (tink / gson in flutter_secure_storage arrive in a later milestone).
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod
# Flutter references Play Core deferred components classes that are not shipped (no Play Services).
-dontwarn com.google.android.play.core.**
