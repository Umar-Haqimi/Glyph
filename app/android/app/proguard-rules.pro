# Glyph R8 / ProGuard rules for the release build (minify + shrinkResources are on).
#
# Audit (M8, docs/DECISIONS.md "R8 audit"): Flutter's Gradle plugin adds the engine rules, AAPT2 keeps every
# class named in the manifest (MainActivity, ShareIntakeActivity, the FileProvider), and each plugin
# below was read for reflection / JNI look-ups by class name; none needs a rule of its own:
#   - flutter_secure_storage: Tink (tink-android ships META-INF/proguard/protobuf.pro for its protobuf-lite
#     fields) and AndroidKeyStore; no Class.forName in the plugin.
#   - file_picker / android_file_picker: a Flutter plugin class registered by GeneratedPluginRegistrant
#     (kept by reference). It does not use package:jni from Dart.
#   - jni / jni_flutter (pulled in by file_picker): they ship consumer-rules.pro that keep what they look up.
#   - dynamic_color: material-components ships its own rules.
#   - multistockfish_*, sqlite3: native code over dart:ffi, no Java classes are looked up.
#   - path_provider, MethodChannels of MainActivity: Pigeon / MethodChannel, no reflection.
# If a new plugin looks classes up by name (JNI `findClass`, `Class.forName`, Gson on its own models), add
# its keep rule here and a line to the audit above.

# Readable, mappable stack traces from a release crash (the mapping file is a build output,
# build/app/outputs/mapping/release/mapping.txt, and is not shipped in the APK).
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# Generic signatures and annotations used by libraries that inspect their own types.
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod

# Flutter references Play Core deferred-component classes that Glyph does not ship (no Play Services).
-dontwarn com.google.android.play.core.**
