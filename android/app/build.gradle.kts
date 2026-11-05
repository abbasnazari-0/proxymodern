import java.io.FileInputStream
import java.util.Properties

import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("kotlin-android")
    // Reads android/app/google-services.json (Firebase project `space-sum`).
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// Release signing is optional for local development. Only create the release
// signing config when key.properties exists AND contains all four values;
// otherwise Gradle would crash at configuration time (even for debug builds)
// with: "null cannot be cast to non-null type kotlin.String".
val releaseKeystoreKeys =
    listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
val hasReleaseKeystore =
    keystorePropertiesFile.exists() &&
        releaseKeystoreKeys.all {
            !keystoreProperties.getProperty(it).isNullOrBlank()
        }
if (keystorePropertiesFile.exists() && !hasReleaseKeystore) {
    logger.warn(
        "android/key.properties exists but is incomplete; " +
            "the release build will use the debug signing key.",
    )
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

android {
    namespace = "af.arianadeveloper.proxymodern"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // لازم برای flutter_local_notifications (نمایش نوتیفیکیشن در Foreground)
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "af.arianadeveloper.proxymodern"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile =
                    keystoreProperties.getProperty("storeFile")?.let { file(it) }
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Uses the real upload key when android/key.properties is present;
            // otherwise falls back to the debug key so `flutter run`/debug and
            // local release builds keep working without a keystore.
            signingConfig =
                if (hasReleaseKeystore) {
                    signingConfigs.getByName("release")
                } else {
                    signingConfigs.getByName("debug")
                }

            // ------------------------------------------------------------------
            // APK size tuning
            // ------------------------------------------------------------------
            // R8 minification is OFF by default. It only saves ~2 MiB and some
            // plugins are reflection-heavy, so minification can break them in
            // subtle ways. Re-enable with -PminifyRelease=true and re-test on a
            // real device before shipping.
            val minifyRelease =
                (project.findProperty("minifyRelease") as String?)?.toBoolean() ?: false
            isMinifyEnabled = minifyRelease
            isShrinkResources = minifyRelease
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    // Native libraries are stored *uncompressed* inside the .apk by default
    // (that is what lets Android mmap them straight out of the archive).
    // Storing them compressed shrinks the .apk by roughly another 20 MB, but
    // the installer then has to extract them, so the on-device footprint grows
    // instead. Off by default; opt in per build with:
    //   flutter build apk --release --split-per-abi -PcompressNativeLibs=true
    packaging {
        jniLibs {
            val compressNativeLibs =
                (project.findProperty("compressNativeLibs") as String?)?.toBoolean() ?: false
            useLegacyPackaging = compressNativeLibs
        }
    }
}

dependencies {
    // Required by flutter_local_notifications (java.time backport on older
    // devices). Keep at 2.1.4+ whenever AGP is upgraded.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

flutter {
    source = "../.."
}
