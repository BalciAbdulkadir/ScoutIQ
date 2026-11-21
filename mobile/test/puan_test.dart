import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/puan.dart';
import 'package:mobile/screens/game_screen.dart';
import 'package:mobile/screens/liderlik_screen.dart';
import 'package:mobile/services/oyun_deposu.dart';
import 'package:mobile/services/paylasim.dart';
import 'package:mobile/theme/tema.dart';
import 'package:mobile/widgets/puan_karti.dart';
import 'package:mobile/widgets/takma_ad_sayfasi.dart';

import 'yardimcilar/sahte_oyun_deposu.dart';

// Takma ad sorusunun cihazdaki bayrağı (SharedPreferences yerine)
class SahteTakmaAdSorusu implements TakmaAdSorusu {
  bool sorulduMu;
  SahteTakmaAdSorusu({this.sorulduMu = true});

  @override
  Future<bool> soruldu() async => sorulduMu;

  @override
  Future<void> isaretle() async => sorulduMu = true;
}

const zorKesisimPuani = PuanDetayi(
  puan: 316,
  zorlukCarpani: 2,
  sureCarpani: 1.5,
  sure: 30,
  kalanSaniye: 8,
  hizBonusu: 16,
);

// Bugün bitirilmiş bir Kesişim oyununu açar: bitmiş oyunda da puan kartı gösterilir
Future<SahteOyunDeposu> bitmisOyunuAc(
  WidgetTester tester, {
  PuanDetayi? puan,
  bool puanHataVerir = false,
  TakmaAdSorusu? soru,
}) async {
  final depo = SahteOyunDeposu()
    ..kayit = {'skor': 10, 'durum': 'tamamlandi'}
    ..puan = puan
    ..puanHataVerir = puanHataVerir;
  await tester.pumpWidget(ProviderScope(
    overrides: [
      oyunDeposuProvider.overrideWithValue(depo),
      takmaAdSorusuProvider.overrideWithValue(soru ?? SahteTakmaAdSorusu()),
    ],
    child: MaterialApp(theme: uygulamaTemasi(), home: const GameScreen(oyunTipi: 'kesisim_zor')),
  ));
  await tester.pumpAndSettle();
  return depo;
}

void main() {
  group('Modeller', () {
    test('puan detayı sunucudaki jsonb\'den okunur', () {
      final p = PuanDetayi.fromJson({
        'puan': 316,
        'bitti': true,
        'zorluk_carpani': 2.0,
        'sure_carpani': 1.5,
        'sure': 30,
        'kalan_saniye': 8,
        'hiz_bonusu': 16,
      });
      expect(p.puan, 316);
      expect(p.puansiz, isFalse);
      expect(p.anaPuan, 300);
      expect(p.kalanSaniye, 8);

      final suresiz = PuanDetayi.fromJson({'puan': null, 'sebep': 'suresiz'});
      expect(suresiz.puansiz, isTrue);
      expect(suresiz.suresiz, isTrue);

      // Top 10: süre yok, hız bonusu 0
      final top10 = PuanDetayi.fromJson({'puan': 150, 'bitti': true, 'zorluk_carpani': 1.5, 'sure_carpani': 1.0, 'sure': null, 'hiz_bonusu': 0});
      expect(top10.puan, 150);
      expect(top10.sure, isNull);
      expect(top10.hizBonusu, 0);
    });

    test('liderlik sonucu: kullanıcının satırı olabilir de olmayabilir de', () {
      final bos = LiderlikSonucu.fromJson({'liste': [], 'ben': null, 'katilimci': 0});
      expect(bos.liste, isEmpty);
      expect(bos.ben, isNull);
      expect(bos.benListede, isFalse);

      final dolu = LiderlikSonucu.fromJson({
        'liste': [
          {'sira': 1, 'ad': 'tribun_kartali', 'puan': 1240, 'oyun': 4, 'ben': false},
          {'sira': 1, 'ad': 'Oyuncu 3FA9', 'puan': 1240, 'oyun': 5, 'ben': true},
        ],
        'ben': {'sira': 1, 'ad': 'Oyuncu 3FA9', 'puan': 1240, 'oyun': 5},
        'katilimci': 2,
      });
      expect(dolu.liste.map((s) => s.sira), [1, 1]);
      expect(dolu.ben!.ben, isTrue);
      expect(dolu.benListede, isTrue);
      expect(dolu.katilimci, 2);
    });

    test('seçim ekranındaki ana puan sunucudaki formülle aynı', () {
      expect(anaPuanHesapla(zorluk: 'zor', sure: 30), 300);
      expect(anaPuanHesapla(zorluk: 'kolay', sure: 90), 100);
      expect(anaPuanHesapla(zorluk: 'orta', sure: 60), 188); // 187.5 yukarı yuvarlanır (Postgres round ile aynı)
      expect(anaPuanHesapla(sure: 60), 188); // Bingo
      expect(anaPuanHesapla(zorluk: 'zor'), isNull); // süresiz puansız
    });

    test('binlik ayırıcı', () {
      expect(binlik(316), '316');
      expect(binlik(1240), '1.240');
      expect(binlik(1000000), '1.000.000');
    });
  });

  group('Metinler', () {
    test('puan dökümü', () {
      expect(puanDokumu('kesisim_zor', zorKesisimPuani), '100 × Zor 2 × 30 sn 1.5 + 16 hız');
      expect(
        puanDokumu('bingo', const PuanDetayi(puan: 188, zorlukCarpani: 1.5, sureCarpani: 1.25, sure: 60)),
        '100 × Bingo 1.5 × 60 sn 1.25',
      );
      expect(puanDokumu('top10', const PuanDetayi(puan: 150)), 'Listeyi tamamladın');
    });

    test('puansız açıklama oyuna göre değişir', () {
      const bitirilemedi = PuanDetayi(sebep: 'bitirilemedi');
      expect(puansizMetni('kesisim_kolay', const PuanDetayi(sebep: 'suresiz')), 'Süresiz oynadın, bu oyun tabloya girmez.');
      expect(puansizMetni('bonservis_orta', bitirilemedi), contains('5/5 yaparsan'));
      expect(puansizMetni('izgara_zor', bitirilemedi), contains('9 kutuyu doldurursan'));
      expect(puansizMetni('bingo', bitirilemedi), contains('12 kutuyu doldurursan'));
      expect(puansizMetni('top10', bitirilemedi), contains('10 oyuncunun hepsini bulursan'));
    });

    test('paylaşımda puan skor satırının altında, puansızda yok', () {
      final puanli = kesisimPaylasimi(sonuclar: List.filled(5, true), zorluk: 'zor', sure: 30, seri: 3, puan: 316);
      final satirlar = puanli.split('\n');
      expect(satirlar[1], '🟩🟩🟩🟩🟩   5/5');
      expect(satirlar[2], '⭐ 316 puan');
      expect(satirlar[3], '🔥 3 gün seri');

      expect(kesisimPaylasimi(sonuclar: [true, false]), isNot(contains('⭐')));
      expect(top10Paylasimi(bulunanSiralar: {for (var i = 1; i <= 10; i++) i}, kalanCan: 2, puan: 150), contains('⭐ 150 puan'));
    });
  });

  group('Bitiş ekranındaki puan kartı', () {
    testWidgets('puanlı bitişte puan, döküm ve sıralama bağlantısı görünür', (tester) async {
      final depo = await bitmisOyunuAc(tester, puan: zorKesisimPuani);

      expect(find.text('+316'), findsOneWidget);
      expect(find.text('100 × Zor 2 × 30 sn 1.5 + 16 hız'), findsOneWidget);
      expect(find.textContaining('5/5 doğru'), findsOneWidget);
      expect(depo.puanIstekleri, ['kesisim_zor']);

      await tester.tap(find.text('Sıralamaya bak →'));
      await tester.pumpAndSettle();
      expect(find.byType(LiderlikScreen), findsOneWidget);
      expect(depo.liderlikIstekleri.single, (LiderlikDonemi.gun, null));
    });

    testWidgets('süresiz oyunda kart yerine açıklama yazar', (tester) async {
      await bitmisOyunuAc(tester, puan: const PuanDetayi(sebep: 'suresiz'));

      expect(find.text('Süresiz oynadın, bu oyun tabloya girmez.'), findsOneWidget);
      expect(find.text('Sıralamaya bak →'), findsNothing);
    });

    testWidgets('puan okunamazsa kart gösterilmez, oyunun sonucu yine görünür', (tester) async {
      await bitmisOyunuAc(tester, puanHataVerir: true);

      expect(find.text('Bugünkü oyununu oynadın'), findsOneWidget);
      expect(find.textContaining('+'), findsNothing);
      expect(find.text('Sıralamaya bak →'), findsNothing);
    });

    testWidgets('ilk puanlı oyunda takma ad bir kez sorulur', (tester) async {
      final soru = SahteTakmaAdSorusu(sorulduMu: false);
      await bitmisOyunuAc(tester, puan: zorKesisimPuani, soru: soru);

      expect(find.text('TAKMA ADIN'), findsOneWidget);
      expect(soru.sorulduMu, isTrue);
    });

    testWidgets('daha önce sorulduysa takma ad sorulmaz', (tester) async {
      await bitmisOyunuAc(tester, puan: zorKesisimPuani);
      expect(find.text('TAKMA ADIN'), findsNothing);
    });
  });
}
