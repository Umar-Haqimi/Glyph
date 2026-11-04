import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: read from android/key.properties (git-ignored) or from environment variables
// (GLYPH_KEYSTORE_FILE, GLYPH_KEYSTORE_PASSWORD, GLYPH_KEY_ALIAS, GLYPH_KEY_PASSWORD). Nothing about the
// keystore is committed (.gitignore covers key.properties, *.jks and *.keystore).
// storeFile is resolved relative to the android/ directory (rootProject.file), so
// `storeFile=../release.jks` is app/release.jks; an absolute path works too.
// If neither is present the release build falls back to the debug key so CI and local builds always pass;
// such an APK is for testing only. Set GLYPH_REQUIRE_SIGNING=1 (tool/build_release.sh does) to make a
// release build without a keystore fail instead.
val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) FileInputStream(file).use { load(it) }
}

// An empty or blank value counts as missing (an exported but empty variable, or `storePassword=` in
// key.properties, must not look like a configured keystore).
fun signingValue(propertyName: String, envName: String): String? =
    (keyProperties.getProperty(propertyName)?.takeIf { it.isNotBlank() } ?: System.getenv(envName))
        ?.takeIf { it.isNotBlank() }

val releaseStoreFile = signingValue("storeFile", "GLYPH_KEYSTORE_FILE")
val releaseStorePassword = signingValue("storePassword", "GLYPH_KEYSTORE_PASSWORD")
val releaseKeyAlias = signingValue("keyAlias", "GLYPH_KEY_ALIAS")
val releaseKeyPassword = signingValue("keyPassword", "GLYPH_KEY_PASSWORD")
val requireReleaseSigning = System.getenv("GLYPH_REQUIRE_SIGNING") == "1"
val hasReleaseSigning = releaseStoreFile != null &&
    releaseStorePassword != null &&
    releaseKeyAlias != null &&
    releaseKeyPassword != null

android {
    namespace = "my.umarh.glyph"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "my.umarh.glyph"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = rootProject.file(releaseStoreFile!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

// GLYPH_REQUIRE_SIGNING=1: refuse to build a release without a release keystore (debug builds are unaffected).
gradle.taskGraph.whenReady {
    val releasing = allTasks.any { it.name.contains("Release") && (it.name.startsWith("assemble") || it.name.startsWith("package") || it.name.startsWith("bundle")) }
    if (requireReleaseSigning && releasing && !hasReleaseSigning) {
        throw GradleException(
            "GLYPH_REQUIRE_SIGNING=1 but no release keystore is configured: " +
                "set android/key.properties or GLYPH_KEYSTORE_FILE / GLYPH_KEYSTORE_PASSWORD / GLYPH_KEY_ALIAS / GLYPH_KEY_PASSWORD",
        )
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // FileProvider for the exported PGN (MainActivity.sharePgn). Already on the classpath through
    // the Flutter embedding; stated so the build does not depend on that.
    implementation("androidx.core:core:1.13.1")
}

flutter {
    source = "../.."
}
