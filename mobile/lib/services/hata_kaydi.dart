import 'dart:async';
import 'dart:io';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'oyun_deposu.dart';

// Oyunda hatanın çıktığı adım
enum OyunIslemi {
  acilis('acilis'), // oyun açılırken (oyun_ac ve tahtayı kuran okumalar)
  hamle('hamle'), // cevap, tahmin, kutuya koyma, pas
  pes('pes');

  final String deger;
  const OyunIslemi(this.deger);
}

// Oyun açılırken ya da hamlede gelen beklenmeyen hatalar (044_sure_kisiti_duzeltme.sql). Kullanıcı bunları sadece
// "Bağlantı sorunu" olarak görür; Crashlytics'e ölümcül olmayan hata olarak gider ki sunucudaki bir hata
// (ör. 043'te kısıtların 40 saniyeyi reddetmesi) fark edilsin. Kullanıcıya gösterilen mesaj değişmez.
// Ekranlar Crashlytics'i doğrudan çağırmaz, bu arayüzü kullanır; testlerde sahtesi verilir.
abstract class HataKaydi {
  // oyunTipi: günlük oyun tipi (ör. kesisim_orta); sure: seçilen süre, saniye (süresizse null)
  Future<void> oyunHatasi(Object hata, StackTrace iz,
      {required OyunIslemi islem, required String oyunTipi, int? sure});
}

// Beklenen durumlar ve internet bağlantısı hataları gönderilmez: bunlar sunucunun hatası değildir,
// bağlantısı kopan her telefon Crashlytics'i doldurur.
bool gonderilecekHata(Object hata) => !(hata is OyunAcikDegil ||
    hata is BaskaModOynandi ||
    hata is SocketException ||
    hata is TimeoutException ||
    hata is ClientException);

// Crashlytics'e giden hata. Sunucunun hata kodu ve mesajı; PostgrestException'ın details alanı gönderilmez,
// çünkü kısıt hatalarında satırın tamamını (kullanıcı id'si dahil) taşır.
class SunucuHatasi implements Exception {
  final String? kod;
  final String mesaj;

  SunucuHatasi(this.kod, this.mesaj);

  factory SunucuHatasi.from(Object hata) => hata is PostgrestException
      ? SunucuHatasi(hata.code, hata.message)
      : SunucuHatasi(null, '${hata.runtimeType}: $hata');

  @override
  String toString() => kod == null ? mesaj : '[$kod] $mesaj';
}

// Gönderilen bilgiler: işlem, oyun tipi, süre, sunucunun hata kodu ve mesajı. Kişisel veri ve oyuncu ismi yoktur.
Map<String, String> hataBilgileri(Object hata, {required OyunIslemi islem, required String oyunTipi, int? sure}) {
  final sunucu = SunucuHatasi.from(hata);
  return {
    'islem': islem.deger,
    'oyun_tipi': oyunTipi,
    'sure': '${sure ?? 0}',
    'kod': sunucu.kod ?? '-',
    'mesaj': sunucu.mesaj,
  };
}

// Crashlytics'e ölümcül olmayan hata olarak gönderir. Debug derlemede göndermez (main.dart toplamayı kapatır).
class CrashlyticsHataKaydi implements HataKaydi {
  final FirebaseCrashlytics _crashlytics;

  CrashlyticsHataKaydi(this._crashlytics);

  @override
  Future<void> oyunHatasi(Object hata, StackTrace iz,
      {required OyunIslemi islem, required String oyunTipi, int? sure}) async {
    if (kDebugMode || !gonderilecekHata(hata)) return;
    final bilgiler = hataBilgileri(hata, islem: islem, oyunTipi: oyunTipi, sure: sure);
    try {
      await _crashlytics.recordError(
        SunucuHatasi.from(hata),
        iz,
        reason: '${islem.deger} $oyunTipi',
        information: [for (final MapEntry(:key, :value) in bilgiler.entries) '$key: $value'],
        fatal: false,
      );
    } catch (_) {
      // Hata kaydı oyunu asla bozmasın
    }
  }
}

// Firebase kurulmamışsa (google-services.json yoksa) ya da testlerde: hiçbir şey göndermez
class BosHataKaydi implements HataKaydi {
  const BosHataKaydi();

  @override
  Future<void> oyunHatasi(Object hata, StackTrace iz,
      {required OyunIslemi islem, required String oyunTipi, int? sure}) async {}
}

// main.dart Firebase açılabildiyse CrashlyticsHataKaydi ile ezer
final hataKaydiProvider = Provider<HataKaydi>((ref) => const BosHataKaydi());
