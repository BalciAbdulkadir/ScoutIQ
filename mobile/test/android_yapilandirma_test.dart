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

  test('release derlemede kod küçültme kapalı (proguard kuralı gerekmesin)', () {
    expect(gradle, contains('isMinifyEnabled = false'));
    expect(gradle, contains('isShrinkResources = false'));
  });

  test('reklam kimliği kapalı: AD_ID izni çıkarılır, Analytics reklam kimliği toplamaz', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('xmlns:tools="http://schemas.android.com/tools"'));
    expect(
      manifest,
      matches(RegExp(r'<uses-permission\s+android:name="com\.google\.android\.gms\.permission\.AD_ID"\s+tools:node="remove"\s*/>')),
    );
    for (final izin in ['android.permission.ACCESS_ADSERVICES_AD_ID', 'android.permission.ACCESS_ADSERVICES_ATTRIBUTION']) {
      expect(manifest, contains('<uses-permission android:name="$izin" tools:node="remove"/>'));
    }
    expect(
      manifest,
      matches(RegExp(r'<meta-data\s+android:name="google_analytics_adid_collection_enabled"\s+android:value="false"\s*/>')),
    );
    // meta-data <application> içinde olmalı, yoksa Android okumaz
    final uygulama = manifest.substring(manifest.indexOf('<application'), manifest.indexOf('</application>'));
    expect(uygulama, contains('google_analytics_adid_collection_enabled'));
  });

  test('pubspec açıklaması şablon metni değil', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, isNot(contains('A new Flutter project.')));
  });
}
