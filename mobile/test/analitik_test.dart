import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/izgara.dart';
import 'package:mobile/models/oyuncu_oneri.dart';
import 'package:mobile/models/puan.dart';
import 'package:mobile/models/top10.dart';
import 'package:mobile/providers/bingo_provider.dart';
import 'package:mobile/providers/bonservis_provider.dart';
import 'package:mobile/providers/game_provider.dart';
import 'package:mobile/providers/izgara_provider.dart';
import 'package:mobile/providers/top10_provider.dart';
import 'package:mobile/services/analitik.dart';
import 'package:mobile/services/oyun_deposu.dart';

import 'bingo_test.dart' show bingoDeposu;
import 'bonservis_test.dart' show bonservisDeposu;
import 'izgara_test.dart' show izgaraDeposu;
import 'top10_test.dart' show top10Deposu;
import 'yardimcilar/sahte_analitik.dart';
import 'yardimcilar/sahte_oyun_deposu.dart';

// Provider'ı açar ve yüklenmesini bekler. Testin sonunda (ya da kapat çağrılınca) container kapanır.
Future<(ProviderContainer, SahteAnalitik)> ac<T>(SahteOyunDeposu depo, ProviderListenable<T> provider,
    bool Function(T) yukleniyor) async {
  final analitik = SahteAnalitik();
  final c = ProviderContainer(overrides: [
    oyunDeposuProvider.overrideWithValue(depo),
    analitikProvider.overrideWithValue(analitik),
  ]);
  addTearDown(c.dispose);
  final dinleyici = c.listen(provider, (_, _) {});
  addTearDown(dinleyici.close);
  for (var i = 0; i < 100 && yukleniyor(c.read(provider)); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  return (c, analitik);
}

// oyun_bitti puan sunucudan okununca gider: bekleyen işler bitsin
Future<void> bekle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('günlük oyun tipi oyun ve zorluğa ayrılır', () {
    expect(oyunVeZorluk('kesisim_orta'), (oyun: 'kesisim', zorluk: 'orta'));
    expect(oyunVeZorluk('izgara_zor'), (oyun: 'izgara', zorluk: 'zor'));
    expect(oyunVeZorluk('bingo'), (oyun: 'bingo', zorluk: null));
    expect(oyunVeZorluk('top10'), (oyun: 'top10', zorluk: null));
  });

  group('Kesişim', () {
    const secim = (oyunTipi: 'kesisim_orta', sure: 60);
    final p = gameProvider(secim);

    test('yeni oyun başlayınca oyun_basladi gider: oyun, zorluk ve süre; oyuncu ismi gitmez', () async {
      final (_, a) = await ac(SahteOyunDeposu(), p, (GameState s) => s.status == 'loading');

      expect(a.adlar, ['oyun_basladi']);
      expect(a.son('oyun_basladi'), {'oyun_tipi': 'kesisim', 'zorluk': 'orta', 'sure': 60});
    });

    test('oyun bitince oyun_bitti skor ve "tamamlandi" sebebiyle gider', () async {
      final (c, a) = await ac(SahteOyunDeposu(), p, (GameState s) => s.status == 'loading');

      for (var i = 0; i < 5; i++) {
        await c.read(p.notifier).makeGuess(const OyuncuOneri(id: 'o-1', isim: 'Arda Güler'));
      }

      await bekle();

      expect(a.son('oyun_bitti'), {'oyun_tipi': 'kesisim', 'zorluk': 'orta', 'skor': 10, 'bitis_sebebi': 'tamamlandi'});
      expect(a.olaylar.toString(), isNot(contains('Arda')));
    });

    test('puanlı bitişte oyun_bitti puanla gider, puansızda puan parametresi yok', () async {
      final depo = SahteOyunDeposu()..puan = const PuanDetayi(puan: 316, hizBonusu: 16);
      final (c, a) = await ac(depo, p, (GameState s) => s.status == 'loading');
      for (var i = 0; i < 5; i++) {
        await c.read(p.notifier).makeGuess(const OyuncuOneri(id: 'o-1', isim: 'Arda Güler'));
      }
      await bekle();
      expect(a.son('oyun_bitti')['puan'], 316);
      expect(depo.puanIstekleri, ['kesisim_orta']);

      final (c2, a2) = await ac(SahteOyunDeposu()..puan = const PuanDetayi(sebep: 'bitirilemedi'), p,
          (GameState s) => s.status == 'loading');
      await c2.read(p.notifier).sureDoldu();
      await bekle();
      expect(a2.son('oyun_bitti').containsKey('puan'), isFalse);
    });

    test('süre dolunca sebep "sure_doldu"', () async {
      final (c, a) = await ac(SahteOyunDeposu(), p, (GameState s) => s.status == 'loading');

      await c.read(p.notifier).sureDoldu();

      await bekle();

      expect(a.son('oyun_bitti')['bitis_sebebi'], 'sure_doldu');
    });

    test('oyun sürerken ekran kapanınca oyun_yarida_birakildi gider', () async {
      final (c, a) = await ac(SahteOyunDeposu(), p, (GameState s) => s.status == 'loading');

      c.dispose();

      expect(a.adlar.last, 'oyun_yarida_birakildi');
      expect(a.son('oyun_yarida_birakildi'), {'oyun_tipi': 'kesisim'});
    });

    test('yarım kalan oyun tekrar açılınca oyun_basladi gitmez; bitmiş oyunu açmak oyun_bitti göndermez', () async {
      final (_, a1) = await ac(SahteOyunDeposu()..kayit = {'skor': 2, 'durum': 'basladi'}, p,
          (GameState s) => s.status == 'loading');
      expect(a1.adlar, isNot(contains('oyun_basladi')));

      final (c2, a2) = await ac(SahteOyunDeposu()..kayit = {'skor': 6, 'durum': 'tamamlandi'}, p,
          (GameState s) => s.status == 'loading');
      c2.dispose();
      expect(a2.adlar, isEmpty);
    });
  });

  test('Bonservis: başlayınca ve bitince olay gider', () async {
    const secim = (oyunTipi: 'bonservis_kolay', sure: null);
    final p = bonservisProvider(secim);
    final (c, a) = await ac(bonservisDeposu(), p, (BonservisState s) => s.durum == BonservisDurumu.yukleniyor);

    for (var i = 0; i < 5; i++) {
      await c.read(p.notifier).tahminEt(dahaFazla: true);
      c.read(p.notifier).devamEt();
    }

    await bekle();
    expect(a.son('oyun_basladi'), {'oyun_tipi': 'bonservis', 'zorluk': 'kolay', 'sure': null});
    expect(a.son('oyun_bitti')['bitis_sebebi'], 'tamamlandi');
    expect(a.son('oyun_bitti')['skor'], c.read(p).skor);
  });

  test('Izgara: pes edince sebep "pes"', () async {
    const IzgaraAcilisi acilis = (zorluk: IzgaraZorlugu.zor, sure: 90);
    final p = izgaraProvider(acilis);
    final (c, a) = await ac(izgaraDeposu(), p, (IzgaraState s) => s.durum == IzgaraDurumu.yukleniyor);

    await c.read(p.notifier).pesEt();

    await bekle();
    expect(a.son('oyun_basladi'), {'oyun_tipi': 'izgara', 'zorluk': 'zor', 'sure': 90});
    expect(a.son('oyun_bitti'), {'oyun_tipi': 'izgara', 'zorluk': 'zor', 'skor': 0, 'bitis_sebebi': 'pes'});
  });

  test('Bingo: zorluk gönderilmez, süre dolunca sebep "sure_doldu"', () async {
    const secim = (oyunTipi: 'bingo', sure: 60);
    final p = bingoProvider(secim);
    final (c, a) = await ac(bingoDeposu(), p, (BingoState s) => s.durum == BingoDurumu.yukleniyor);

    await c.read(p.notifier).sureDoldu();

    await bekle();
    expect(a.son('oyun_basladi'), {'oyun_tipi': 'bingo', 'zorluk': null, 'sure': 60});
    expect(a.son('oyun_bitti')['bitis_sebebi'], 'sure_doldu');
  });

  test('Top 10: üçüncü yanlışta sebep "can_bitti"', () async {
    final p = top10Provider(const Top10Acilis());
    final depo = top10Deposu()
      ..oneriler = [
        for (var i = 0; i < 3; i++) OyuncuOneri(id: 'y-$i', isim: 'Yanlış $i'),
      ];
    final (c, a) = await ac(depo, p, (Top10State s) => s.durum == Top10Durumu.yukleniyor);

    for (var i = 0; i < top10Can; i++) {
      await c.read(p.notifier).tahminEt(OyuncuOneri(id: 'y-$i', isim: 'Yanlış $i'));
    }

    await bekle();
    expect(a.son('oyun_basladi'), {'oyun_tipi': 'top10', 'zorluk': null, 'sure': null});
    expect(a.son('oyun_bitti'), {'oyun_tipi': 'top10', 'zorluk': null, 'skor': 0, 'bitis_sebebi': 'can_bitti'});
  });
}
