import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "af.arianadeveloper.proxymodern"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
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
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String
        }
    }

    buildTypes {
        release {
            // Signing with the release upload key (movie-chi-keystore.jks).
            signingConfig = signingConfigs.getByName("release")

            // ------------------------------------------------------------------
            // APK size tuning
            // ------------------------------------------------------------------
            // R8 minification is OFF by default. It only saves ~2 MiB (classes.dex
            // are reflection-heavy and minification can break ad loading in subtle
            // ways. Re-enable with -PminifyRelease=true once ads are confirmed
            // working, and re-test ad display before shipping.
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

flutter {
    source = "../.."
}
