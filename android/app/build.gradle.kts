plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "ir.montala.montala"
    compileSdk = 36

    // This app has no native (C/C++) code of its own — sqflite uses the
    // platform's built-in SQLite and no plugin above ships a .so. Pinning the
    // NDK to whatever the SDK already has (or to "" when none is installed)
    // stops Flutter's Gradle plugin from trying to download a 2 GB toolchain
    // that the build never uses.
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "ir.montala.montala"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = 36
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Signed with the debug key so `flutter build apk` works out of the
            // box. Replace with a real keystore before publishing.
            signingConfig = signingConfigs.getByName("debug")
            // R8 is disabled: it requires the Build Tools strip tool, and this
            // app is a Dart binary plus a few Kotlin shell classes, so there is
            // nothing meaningful to shrink.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
