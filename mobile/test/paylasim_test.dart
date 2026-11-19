import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/top10.dart';
import 'package:mobile/providers/hub_provider.dart';
import 'package:mobile/screens/game_screen.dart';
import 'package:mobile/screens/top10_screen.dart';
import 'package:mobile/services/analitik.dart';
import 'package:mobile/services/oyun_deposu.dart';
import 'package:mobile/services/paylasim.dart';

import 'top10_test.dart' show top10Deposu;
import 'yardimcilar/sahte_analitik.dart';
import 'yardimcilar/sahte_oyun_deposu.dart';

class SahtePaylasici implements Paylasici {
  final List<String> paylasilanlar = [];

  @override
  Future<void> paylas(String metin) async => paylasilanlar.add(metin);
}

void main() {
  group('Metinler', () {
    test('başlık: zorluk ve süre varsa yazar, yoksa yazmaz', () {
      expect(paylasimBasligi(oyunAdi: 'Izgara', zorluk: 'zor', sure: 60), 'FootyLore · Izgara · Zor · 60 sn');
      expect(paylasimBasligi(oyunAdi: 'Bingo', sure: 90), 'FootyLore · Bingo · 90 sn');
      expect(paylasimBasligi(oyunAdi: 'Top 10'), 'FootyLore · Top 10');
      expect(paylasimBasligi(oyunAdi: 'Kesişim', zorluk: 'kolay', sure: null), 'FootyLore · Kesişim · Kolay');
    });

    test('Izgara: 3x3 kare, skor son satırda, seri ve Play linki', () {
      final metin = izgaraPaylasimi(doluHucreler: {0, 1, 3, 4, 5, 7, 8}, zorluk: 'zor', sure: 60, seri: 6);

      expect(metin, 'FootyLore · Izgara · Zor · 60 sn\n'
          '🟩🟩⬛\n'
          '🟩🟩🟩\n'
          '⬛🟩🟩   7/9\n'
          '🔥 6 gün seri\n'
          '$playStoreLinki');
    });

    test('Kesişim: 5 soru için doğru/yanlış sırası; süre dolunca cevaplanmayanlar boş', () {
      expect(kesisimPaylasimi(sonuclar: [true, false, true, true, false], zorluk: 'orta').split('\n')[1],
          '🟩🟥🟩🟩🟥   3/5');
      expect(kesisimPaylasimi(sonuclar: [true, true], zorluk: 'zor', sure: 30).split('\n')[1], '🟩🟩⬛⬛⬛   2/5');
    });

    test('Bonservis: 5 tahmin için doğru/yanlış sırası', () {
      final metin = bonservisPaylasimi(sonuclar: [false, true, true, true, true], zorluk: 'kolay', sure: 90);

      expect(metin.split('\n'), ['FootyLore · Bonservis · Kolay · 90 sn', '🟥🟩🟩🟩🟩   4/5', playStoreLinki]);
    });

    test('Bingo: 4x3 kart, zorluk yazmaz', () {
      final metin = bingoPaylasimi(doluKutular: {0, 1, 2, 3, 5, 6, 8, 9, 11}, sure: null);

      expect(metin.split('\n'), [
        'FootyLore · Bingo',
        '🟩🟩🟩',
        '🟩⬛🟩',
        '🟩⬛🟩',
        '🟩⬛🟩   9/12',
        playStoreLinki,
      ]);
    });

    test('Top 10: 10 satır bulundu/bulunamadı, skor ve kalan canlar', () {
      final metin = top10Paylasimi(bulunanSiralar: {1, 2, 4, 6, 7, 9, 10}, kalanCan: 1, seri: 3);

      expect(metin.split('\n'), [
        'FootyLore · Top 10',
        '🟩🟩⬛🟩⬛',
        '🟩🟩⬛🟩🟩   7/10',
        '❤️🤍🤍',
        '🔥 3 gün seri',
        playStoreLinki,
      ]);
    });

    test('seri yoksa seri satırı yazmaz', () {
      expect(top10Paylasimi(bulunanSiralar: {}, kalanCan: 3, seri: 0), isNot(contains('seri')));
      expect(izgaraPaylasimi(doluHucreler: {}, seri: null), isNot(contains('🔥')));
    });
  });

  group('Düğme', () {
    testWidgets('Top 10 bitince "Sonucu paylaş" metni paylaşır, analitiğe sonuc_paylasildi gider', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      final paylasici = SahtePaylasici();
      final analitik = SahteAnalitik();

      await tester.pumpWidget(ProviderScope(
        overrides: [
          oyunDeposuProvider.overrideWithValue(top10Deposu()
            ..kayit = {'skor': 1, 'durum': 'tamamlandi'}
            ..top10TahminListesi = [const Top10Tahmini(oyuncuIsim: 'Arda Güler', sira: 3)]),
          paylasiciProvider.overrideWithValue(paylasici),
          analitikProvider.overrideWithValue(analitik),
          seriProvider.overrideWith((ref) async => 4),
        ],
        child: const MaterialApp(home: Top10Screen()),
      ));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Sonucu paylaş'), 300);
      await tester.tap(find.text('Sonucu paylaş'));
      await tester.pumpAndSettle();

      expect(paylasici.paylasilanlar.single, startsWith('FootyLore · Top 10\n⬛⬛🟩⬛⬛'));
      expect(paylasici.paylasilanlar.single, contains('🔥 4 gün seri'));
      expect(paylasici.paylasilanlar.single, isNot(contains('Arda')));
      expect(analitik.son('sonuc_paylasildi'), {'oyun_tipi': 'top10'});
    });

    testWidgets('bugün oynanmış Kesişim açılınca da paylaşılabilir', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      final paylasici = SahtePaylasici();

      await tester.pumpWidget(ProviderScope(
        overrides: [
          oyunDeposuProvider.overrideWithValue(SahteOyunDeposu()
            ..kayit = {'skor': 4, 'durum': 'tamamlandi'}
            ..ilerleme = [
              {'dogru': true},
              {'dogru': false},
              {'dogru': true},
              {'dogru': false},
              {'dogru': false},
            ]),
          paylasiciProvider.overrideWithValue(paylasici),
          seriProvider.overrideWith((ref) async => 0),
        ],
        child: const MaterialApp(home: GameScreen(oyunTipi: 'kesisim_zor')),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Bugünkü oyununu oynadın'), findsOneWidget);
      await tester.tap(find.text('Sonucu paylaş'));
      await tester.pumpAndSettle();

      expect(paylasici.paylasilanlar.single.split('\n').take(2), ['FootyLore · Kesişim · Zor', '🟩🟥🟩🟥🟥   2/5']);
    });
  });
}
