import 'package:mobile/services/analitik.dart';

// Testler için: gönderilen olayları kaydeder, hiçbir yere göndermez
class SahteAnalitik implements Analitik {
  final List<(String, Map<String, Object?>)> olaylar = [];

  List<String> get adlar => [for (final (ad, _) in olaylar) ad];

  Map<String, Object?> son(String ad) => olaylar.lastWhere((o) => o.$1 == ad).$2;

  @override
  Future<void> oyunBasladi({required String oyunTipi, String? zorluk, int? sure}) async =>
      olaylar.add(('oyun_basladi', {'oyun_tipi': oyunTipi, 'zorluk': zorluk, 'sure': sure}));

  @override
  Future<void> oyunBitti({required String oyunTipi, String? zorluk, required int skor, required BitisSebebi sebep, int? puan}) async =>
      olaylar.add(('oyun_bitti', {
        'oyun_tipi': oyunTipi,
        'zorluk': zorluk,
        'skor': skor,
        'bitis_sebebi': sebep.deger,
        'puan': ?puan,
      }));

  @override
  Future<void> oyunYaridaBirakildi({required String oyunTipi}) async =>
      olaylar.add(('oyun_yarida_birakildi', {'oyun_tipi': oyunTipi}));

  @override
  Future<void> sonucPaylasildi({required String oyunTipi}) async => olaylar.add(('sonuc_paylasildi', {'oyun_tipi': oyunTipi}));

  @override
  Future<void> bildirimAcildi() async => olaylar.add(('bildirim_acildi', {}));

  @override
  Future<void> liderlikAcildi({required String donem}) async => olaylar.add(('liderlik_acildi', {'donem': donem}));
}
