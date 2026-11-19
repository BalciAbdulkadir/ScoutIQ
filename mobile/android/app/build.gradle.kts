import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release imzası: android/key.properties dosyasından okunur (storeFile, storePassword, keyAlias, keyPassword).
// key.properties ve .jks dosyaları repoya girmez (android/.gitignore). Dosya yoksa release derleme debug anahtarıyla
// imzalanır: geliştirme makinelerinde `flutter build` çalışmaya devam eder ama bu paket Play'e yüklenemez.
val anahtarDosyasi = rootProject.file("key.properties")
val anahtar = Properties().apply {
    if (anahtarDosyasi.exists()) anahtarDosyasi.inputStream().use { load(it) }
}
val releaseAnahtariVar = anahtarDosyasi.exists()

// Firebase (Crashlytics, Analytics): ayarları Firebase konsolundan indirilen app/google-services.json'dadır.
// Dosya yoksa Firebase eklentileri uygulanmaz: uygulama derlenir ve Firebase'siz çalışır (main.dart).
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
    apply(plugin = "com.google.firebase.crashlytics")
} else {
    logger.warn("UYARI: android/app/google-services.json yok, Firebase (Crashlytics, Analytics) kapalı derleniyor.")
}

android {
    // Play'deki paket adı: ilk yüklemeden sonra değiştirilemez
    namespace = "com.footylore.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.footylore.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseAnahtariVar) {
            create("release") {
                storeFile = rootProject.file(anahtar.getProperty("storeFile"))
                storePassword = anahtar.getProperty("storePassword")
                keyAlias = anahtar.getProperty("keyAlias")
                keyPassword = anahtar.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (releaseAnahtariVar) {
                signingConfigs.getByName("release")
            } else {
                logger.warn("UYARI: android/key.properties yok, release derleme debug anahtarıyla imzalanıyor (Play'e yüklenemez).")
                signingConfigs.getByName("debug")
            }
            // Kod küçültme kapalı: açılırsa Supabase ve google_sign_in için proguard kuralları gerekir
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
