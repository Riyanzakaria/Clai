plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.riyanzakaria.clai"
    compileSdk = flutter.compileSdkVersion
    // ndkVersion dilepas: tidak ada kode native yang dibangun dari sumber di F1; AGP tidak perlu mengunduh NDK (lihat catatan build).

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.riyanzakaria.clai"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // v4.4.1: perampingan rilis standar - R8 minify + shrinkResources.
            // Wajib lulus uji putar penuh di emulator sebelum diserahkan;
            // bila jalur just_audio/audio_service/InnerTube patah dan aturan
            // keep tidak menyelesaikannya dengan bersih, nonaktifkan lagi.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
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

dependencies {
    // F2 Batch 2.1 (cara ketiga, keputusan riyan 24 Okt 2026): OCR Tangkap-
    // gambar memakai Tesseract lewat Tesseract4Android. MODELNYA TIDAK ikut
    // di APK — berkas traineddata diunduh sekali di dalam aplikasi dari aset
    // GitHub Releases (lihat OcrModelController). Dulu: ML Kit terbundel
    // (com.google.mlkit:text-recognition) — dilepas, menghemat ±12 MB.
    implementation("cz.adaptech.tesseract4android:tesseract4android:4.8.0")
}
