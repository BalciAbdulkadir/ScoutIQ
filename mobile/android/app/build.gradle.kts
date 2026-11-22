import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release imzası: android/key.properties dosyasından okunur (storeFile, storePassword, keyAlias, keyPassword).
// key.properties ve .jks dosyaları repoya girmez (android/.gitignore). Dosya yoksa debug derleme ve testler çalışır;
// release paketi (bundleRelease, assembleRelease) derlenmeye başlamadan durur (aşağıdaki "Release dosyaları" kontrolü).
val anahtarDosyasi = rootProject.file("key.properties")
val anahtar = Properties().apply {
    if (anahtarDosyasi.exists()) anahtarDosyasi.inputStream().use { load(it) }
}
val releaseAnahtariVar = anahtarDosyasi.exists()

// Firebase (Crashlytics, Analytics): ayarları Firebase konsolundan indirilen app/google-services.json'dadır.
// Dosya yoksa Firebase eklentileri uygulanmaz: debug derlenir ve Firebase'siz çalışır (main.dart). Release durur.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
    apply(plugin = "com.google.firebase.crashlytics")
} else {
    logger.warn("UYARI: android/app/google-services.json yok, Firebase (Crashlytics, Analytics) kapalı derleniyor.")
}

// Release dosyaları: Play'e gidecek paket (bundleRelease, assembleRelease ve bunların paketleme görevleri) imza
// dosyası ya da Firebase ayarı eksikken derlenmez. Eskiden sadece uyarı verip debug anahtarıyla imzalıyordu; o paket
// Play'e yüklenemez, Firebase'siz paket de çökme ve analitik toplamaz. Debug derleme ve testler bu kontrole girmez.
val releaseGorevleri = setOf("assembleRelease", "bundleRelease", "packageRelease", "packageReleaseBundle")

fun releaseEksikleri(): List<String> {
    val eksikler = mutableListOf<String>()
    if (!anahtarDosyasi.exists()) {
        eksikler += "- key.properties yok. Release imzası bu dosyadan okunur (storeFile, storePassword, keyAlias, " +
            "keyPassword). Dosyayı şuraya koy: ${anahtarDosyasi.absolutePath}"
    } else {
        val yol = anahtar.getProperty("storeFile")?.trim()
        if (yol.isNullOrEmpty()) {
            eksikler += "- key.properties içinde storeFile satırı yok. .jks dosyasının yolunu yaz " +
                "(tırnaksız, / ile; ör. storeFile=D:/keystore/footylore-release.jks): ${anahtarDosyasi.absolutePath}"
        } else if (!rootProject.file(yol).exists()) {
            eksikler += "- key.properties'teki storeFile bulunamadı: ${rootProject.file(yol).absolutePath}. " +
                ".jks dosyasını oraya koy ya da yolu düzelt (tırnaksız, / ile; Türkçe karakterli klasör kullanma)."
        }
        for (alan in listOf("storePassword", "keyAlias", "keyPassword")) {
            if (anahtar.getProperty(alan).isNullOrBlank()) {
                eksikler += "- key.properties içinde $alan satırı yok ya da boş: ${anahtarDosyasi.absolutePath}"
            }
        }
    }
    val firebaseAyari = file("google-services.json")
    if (!firebaseAyari.exists()) {
        eksikler += "- google-services.json yok. Firebase konsolundan (Proje ayarları > Android uygulaması " +
            "com.footylore.app) indirip şuraya koy: ${firebaseAyari.absolutePath}"
    }
    return eksikler
}

gradle.taskGraph.whenReady {
    val releaseDerleniyor = allTasks.any { it.project == project && it.name in releaseGorevleri }
    if (!releaseDerleniyor) return@whenReady
    val eksikler = releaseEksikleri()
    if (eksikler.isNotEmpty()) {
        throw GradleException(
            (listOf("", "FootyLore release derlemesi durdu: Play'e gidecek paket için dosya eksik.") + eksikler +
                listOf("Debug derleme (flutter run) bu dosyalar olmadan da çalışır.")).joinToString(System.lineSeparator())
        )
    }
}

android {
    // Play'deki paket adı: ilk yüklemeden sonra değiştirilemez
    namespace = "com.footylore.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications yeni Java zaman API'lerini kullanır: eski Android sürümleri için gerekir
        isCoreLibraryDesugaringEnabled = true
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
            // key.properties yoksa release paketi yukarıdaki kontrolde durur. Debug anahtarı sadece release
            // yapılandırması gereken ama paket üretmeyen görevler (signingReport gibi) için yer tutar.
            signingConfig = if (releaseAnahtariVar) {
                signingConfigs.getByName("release")
            } else {
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
