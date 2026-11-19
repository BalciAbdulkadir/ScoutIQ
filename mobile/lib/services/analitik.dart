import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Oyunun neden bittiği (oyun_bitti olayının bitis_sebebi parametresi)
enum BitisSebebi {
  tamamlandi('tamamlandi'),
  pes('pes'),
  sureDoldu('sure_doldu'),
  canBitti('can_bitti');

  final String deger;
  const BitisSebebi(this.deger);
}

// Kullanım olayları. Kişisel veri ve oyuncu ismi gönderilmez: sadece oyun tipi, zorluk, süre, skor ve bitiş sebebi.
// Ekranlar Firebase'i doğrudan çağırmaz, bu arayüzü kullanır; testlerde sahtesi verilir.
abstract class Analitik {
  // oyun_tipi: kesisim, bonservis, izgara, bingo, top10. zorluk: kolay, orta, zor (zorluksuz oyunda yok).
  // sure: saniye (süresiz oyunda 0)
  Future<void> oyunBasladi({required String oyunTipi, String? zorluk, int? sure});
  Future<void> oyunBitti({required String oyunTipi, String? zorluk, required int skor, required BitisSebebi sebep});
  Future<void> oyunYaridaBirakildi({required String oyunTipi});
  Future<void> sonucPaylasildi({required String oyunTipi});
  Future<void> bildirimAcildi();
}

// Günlük oyun tipini oyuna ve zorluğa ayırır: kesisim_orta -> (kesisim, orta), bingo -> (bingo, null)
({String oyun, String? zorluk}) oyunVeZorluk(String gunlukOyunTipi) {
  final parcalar = gunlukOyunTipi.split('_');
  const zorluklar = {'kolay', 'orta', 'zor'};
  if (parcalar.length == 2 && zorluklar.contains(parcalar[1])) return (oyun: parcalar[0], zorluk: parcalar[1]);
  return (oyun: gunlukOyunTipi, zorluk: null);
}

// Olayların ortak parametreleri; Firebase değer olarak null kabul etmez, boş olanlar gönderilmez
Map<String, Object> _parametreler(Map<String, Object?> ham) => {
      for (final MapEntry(:key, :value) in ham.entries)
        if (value != null) key: value,
    };

// Firebase Analytics'e gönderir. Debug derlemede göndermez (geliştirme verisi istatistiklere karışmasın).
class FirebaseAnalitik implements Analitik {
  final FirebaseAnalytics _analytics;

  FirebaseAnalitik(this._analytics);

  Future<void> _gonder(String ad, [Map<String, Object?> parametreler = const {}]) async {
    if (kDebugMode) return;
    try {
      await _analytics.logEvent(name: ad, parameters: _parametreler(parametreler));
    } catch (_) {
      // Analitik oyunu asla bozmasın
    }
  }

  @override
  Future<void> oyunBasladi({required String oyunTipi, String? zorluk, int? sure}) =>
      _gonder('oyun_basladi', {'oyun_tipi': oyunTipi, 'zorluk': zorluk, 'sure': sure ?? 0});

  @override
  Future<void> oyunBitti({required String oyunTipi, String? zorluk, required int skor, required BitisSebebi sebep}) =>
      _gonder('oyun_bitti', {'oyun_tipi': oyunTipi, 'zorluk': zorluk, 'skor': skor, 'bitis_sebebi': sebep.deger});

  @override
  Future<void> oyunYaridaBirakildi({required String oyunTipi}) => _gonder('oyun_yarida_birakildi', {'oyun_tipi': oyunTipi});

  @override
  Future<void> sonucPaylasildi({required String oyunTipi}) => _gonder('sonuc_paylasildi', {'oyun_tipi': oyunTipi});

  @override
  Future<void> bildirimAcildi() => _gonder('bildirim_acildi');
}

// Firebase kurulmamışsa (google-services.json yoksa) ya da testlerde: hiçbir şey göndermez
class BosAnalitik implements Analitik {
  const BosAnalitik();

  @override
  Future<void> oyunBasladi({required String oyunTipi, String? zorluk, int? sure}) async {}

  @override
  Future<void> oyunBitti({required String oyunTipi, String? zorluk, required int skor, required BitisSebebi sebep}) async {}

  @override
  Future<void> oyunYaridaBirakildi({required String oyunTipi}) async {}

  @override
  Future<void> sonucPaylasildi({required String oyunTipi}) async {}

  @override
  Future<void> bildirimAcildi() async {}
}

// main.dart Firebase açılabildiyse FirebaseAnalitik ile ezer
final analitikProvider = Provider<Analitik>((ref) => const BosAnalitik());

// Bir oyun ekranının analitik olayları. Her oyunun provider'ı bir tane tutar:
// - basladi: yeni kayıt açılınca (yarım kalan oyun tekrar açılınca değil)
// - durumDegisti: oyun oynanırken bitince oyun_bitti (bitmiş oyunu açmak sayılmaz)
// - kapandi: ekran oyun sürerken kapanınca oyun_yarida_birakildi
class OyunOlaylari {
  final Analitik _analitik;
  final String _oyun;
  final String? _zorluk;

  OyunOlaylari(this._analitik, String gunlukOyunTipi)
      : _oyun = oyunVeZorluk(gunlukOyunTipi).oyun,
        _zorluk = oyunVeZorluk(gunlukOyunTipi).zorluk;

  void basladi({int? sure}) => _analitik.oyunBasladi(oyunTipi: _oyun, zorluk: _zorluk, sure: sure);

  void bitti({required int skor, required BitisSebebi sebep}) =>
      _analitik.oyunBitti(oyunTipi: _oyun, zorluk: _zorluk, skor: skor, sebep: sebep);

  void yaridaBirakildi() => _analitik.oyunYaridaBirakildi(oyunTipi: _oyun);
}
