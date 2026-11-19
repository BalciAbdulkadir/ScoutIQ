import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/oyuncu_oneri.dart';
import 'package:mobile/providers/game_provider.dart';
import 'package:mobile/services/oyun_deposu.dart';
import 'package:mobile/services/oyun_sonu.dart';
import 'package:mobile/services/puanlama.dart';

import 'yardimcilar/sahte_hatirlatma.dart';
import 'yardimcilar/sahte_oyun_deposu.dart';

class SahtePuanlamaPenceresi implements PuanlamaPenceresi {
  int acilmaSayisi = 0;

  @override
  Future<void> ac() async => acilmaSayisi++;
}

void main() {
  test('iyi sonuç: oyunun en yüksek skorunun en az %70\'i', () {
    expect(iyiSonuc('kesisim_orta', 8), isTrue);
    expect(iyiSonuc('kesisim_orta', 6), isFalse);
    expect(iyiSonuc('bonservis_zor', 8), isTrue);
    expect(iyiSonuc('izgara_kolay', 7), isTrue);
    expect(iyiSonuc('izgara_kolay', 6), isFalse);
    expect(iyiSonuc('bingo', 9), isTrue);
    expect(iyiSonuc('bingo', 8), isFalse);
    expect(iyiSonuc('top10', 7), isTrue);
    expect(iyiSonuc('top10', 6), isFalse);
    expect(iyiSonuc('bilinmeyen', 100), isFalse);
  });

  group('Puanla isteği', () {
    late BellekPuanlamaDeposu depo;
    late SahtePuanlamaPenceresi pencere;
    late PuanlamaIstegi istek;

    setUp(() {
      depo = BellekPuanlamaDeposu();
      pencere = SahtePuanlamaPenceresi();
      istek = PuanlamaIstegi(depo, pencere);
    });

    test('3 farklı gün dolmadan sorulmaz; aynı gün birden çok oyun tek gün sayılır', () async {
      await istek.oyunBitti(gunlukOyunTipi: 'top10', skor: 10, bugun: '2026-11-17');
      await istek.oyunBitti(gunlukOyunTipi: 'bingo', skor: 12, bugun: '2026-11-18');
      await istek.oyunBitti(gunlukOyunTipi: 'izgara_zor', skor: 9, bugun: '2026-11-18');

      expect(pencere.acilmaSayisi, 0);
      expect(depo.gunler, {'2026-11-17', '2026-11-18'});
    });

    test('üçüncü günde iyi sonuçta bir kez sorulur, bir daha sorulmaz', () async {
      await istek.oyunBitti(gunlukOyunTipi: 'top10', skor: 2, bugun: '2026-11-17');
      await istek.oyunBitti(gunlukOyunTipi: 'top10', skor: 2, bugun: '2026-11-18');

      final acildi = await istek.oyunBitti(gunlukOyunTipi: 'kesisim_kolay', skor: 10, bugun: '2026-11-19');
      await istek.oyunBitti(gunlukOyunTipi: 'bingo', skor: 12, bugun: '2026-11-20');

      expect(acildi, isTrue);
      expect(pencere.acilmaSayisi, 1);
      expect(depo.sorulduMu, isTrue);
    });

    test('kötü sonuçta sorulmaz, sonraki iyi sonuçta sorulur', () async {
      for (final gun in ['2026-11-17', '2026-11-18', '2026-11-19']) {
        await istek.oyunBitti(gunlukOyunTipi: 'izgara_orta', skor: 3, bugun: gun);
      }
      expect(pencere.acilmaSayisi, 0);

      await istek.oyunBitti(gunlukOyunTipi: 'izgara_orta', skor: 8, bugun: '2026-11-19');
      expect(pencere.acilmaSayisi, 1);
    });
  });

  test('oyun oynanırken iyi sonuçla bitince istek oyun sonundan gider', () async {
    final depo = BellekPuanlamaDeposu()..gunler.addAll({'2026-11-17', '2026-11-18'});
    final pencere = SahtePuanlamaPenceresi();
    final c = ProviderContainer(overrides: [
      oyunDeposuProvider.overrideWithValue(SahteOyunDeposu()),
      oyunSonuProvider.overrideWithValue(
          OyunSonu(SahteHatirlatma(), PuanlamaIstegi(depo, pencere), bugun: () => '2026-11-19')),
    ]);
    addTearDown(c.dispose);
    const secim = (oyunTipi: 'kesisim_kolay', sure: null);
    c.listen(gameProvider(secim), (_, _) {});
    for (var i = 0; i < 100 && c.read(gameProvider(secim)).status == 'loading'; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    for (var i = 0; i < 5; i++) {
      await c.read(gameProvider(secim).notifier).makeGuess(const OyuncuOneri(id: 'o-1', isim: 'Arda Güler'));
    }
    await Future<void>.delayed(Duration.zero);

    expect(c.read(gameProvider(secim)).score, 10);
    expect(pencere.acilmaSayisi, 1);
  });
}
