import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Play'e yüklenecek paketin ayarları. Paket adı ilk yüklemeden sonra değiştirilemez; yanlışlıkla bozulmasın.
void main() {
  const paketAdi = 'com.footylore.app';
  final gradle = File('android/app/build.gradle.kts').readAsStringSync();

  test('paket adı ve namespace Play için uygun (com.example değil)', () {
    expect(gradle, contains('applicationId = "$paketAdi"'));
    expect(gradle, contains('namespace = "$paketAdi"'));
    expect(gradle, isNot(contains('com.example')));
  });

  test('MainActivity paket adının klasöründe ve paket satırı doğru', () {
    final activity = File('android/app/src/main/kotlin/com/footylore/app/MainActivity.kt');
    expect(activity.existsSync(), isTrue);
    expect(activity.readAsStringSync(), startsWith('package $paketAdi'));
    expect(Directory('android/app/src/main/kotlin/com/example').existsSync(), isFalse);
  });

  test("release imzası key.properties'ten okunur, anahtar dosyaları repoya girmez", () {
    expect(gradle, contains('key.properties'));
    expect(gradle, contains('signingConfigs.getByName("release")'));
    final yoksay = File('android/.gitignore').readAsStringSync();
    expect(yoksay, contains('key.properties'));
    expect(yoksay, contains('**/*.jks'));
  });

  test('release paketi key.properties ya da google-services.json eksikken derlenmez', () {
    // Kontrol sadece release paketleme görevlerinde çalışır; debug derleme ve testler dosyasız çalışır
    for (final gorev in ['assembleRelease', 'bundleRelease']) {
      expect(gradle, contains('"$gorev"'));
    }
    expect(gradle, contains('gradle.taskGraph.whenReady'));
    expect(gradle, contains('throw GradleException('));
    expect(gradle, contains('FootyLore release derlemesi durdu'));
    // Mesaj eksik dosyayı ve nereye konacağını söyler
    expect(gradle, contains('key.properties yok'));
    expect(gradle, contains('google-services.json yok'));
    expect(gradle, contains('anahtarDosyasi.absolutePath'));
    expect(gradle, contains('firebaseAyari.absolutePath'));
    // Eskisi gibi uyarı verip debug anahtarıyla Play paketi üretmez
    expect(gradle, isNot(contains('debug anahtarıyla imzalanıyor')));
  });

  test('release derlemede kod küçültme kapalı (proguard kuralı gerekmesin)', () {
    expect(gradle, contains('isMinifyEnabled = false'));
    expect(gradle, contains('isShrinkResources = false'));
  });

  test('pubspec açıklaması şablon metni değil', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, isNot(contains('A new Flutter project.')));
  });
}
