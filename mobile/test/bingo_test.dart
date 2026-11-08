import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/bingo.dart';
import 'package:mobile/providers/bingo_provider.dart';
import 'package:mobile/screens/bingo_screen.dart';
import 'package:mobile/services/gunluk_oyun.dart';
import 'package:mobile/services/oyun_deposu.dart';

import 'yardimcilar/sahte_oyun_deposu.dart';

// 16 kutu: 6 kulüp, 4 milli takım, 2 lig, 4 başarı; deste 20 oyuncu
final ornekKart = {
  'hucreler': [
    for (var i = 0; i < 6; i++) {'tip': 'kulup', 'anahtar': 'k$i', 'isim': 'Kulüp $i', 'id': 'kulup-$i', 'logo': null},
    for (var i = 0; i < 4; i++) {'tip': 'milli', 'anahtar': 'm$i', 'isim': 'Ülke $i'},
    for (var i = 0; i < 2; i++) {'tip': 'lig', 'anahtar': 'l$i', 'isim': 'Lig $i'},
    for (var i = 0; i < 4; i++) {'tip': 'basari', 'anahtar': 'b$i', 'isim': 'Kupa $i'},
  ],
  'oyuncular': [
    for (var i = 1; i <= 20; i++) {'id': 'o-$i', 'isim': 'Oyuncu $i', 'foto': null},
  ],
};

const testOyunTipi = 'bingo_orta';

SahteOyunDeposu bingoDeposu() => SahteOyunDeposu()..oyun = {'id': 'bingo-1', 'soru_verisi': ornekKart};

Future<(ProviderContainer, SahteOyunDeposu)> kartiAc([void Function(SahteOyunDeposu)? ayarla, int? sure]) async {
  final depo = bingoDeposu();
  ayarla?.call(depo);

  final container = ProviderContainer(overrides: [oyunDeposuProvider.overrideWithValue(depo)]);
  addTearDown(container.dispose);
  final provider = bingoProvider((oyunTipi: testOyunTipi, sure: sure));
  container.listen(provider, (_, _) {});
  for (var i = 0; i < 100 && container.read(provider).durum == BingoDurumu.yukleniyor; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  return (container, depo);
}

BingoState durum(ProviderContainer c, [int? sure]) => c.read(bingoProvider((oyunTipi: testOyunTipi, sure: sure)));
BingoNotifier notifier(ProviderContainer c, [int? sure]) => c.read(bingoProvider((oyunTipi: testOyunTipi, sure: sure)).notifier);

void main() {
  group('Kart', () {
    test('soru verisinden 16 kutu ve deste okunur', () {
      final kart = BingoKarti.oku(ornekKart)!;

      expect(kart.hucreler, hasLength(bingoHucreSayisi));
      expect(kart.deste, hasLength(20));
      expect(kart.hucreler.first.tip, BingoKategoriTipi.kulup);
      expect(kart.hucreler.last.tip, BingoKategoriTipi.basari);
      expect(kart.hucreler.last.aciklama, 'kazandı');
    });

    test('eksik ya da bozuk kart okunmaz', () {
      expect(BingoKarti.oku(null), isNull);
      expect(BingoKarti.oku({'hucreler': [], 'oyuncular': []}), isNull);
      expect(BingoKarti.oku({...ornekKart, 'oyuncular': []}), isNull);
    });
  });

  group('Oyunun açılması', () {
    test('günün kartı varsa oyun başlar, seçilen zorluğun kaydı açılır ve ilk oyuncu gelir', () async {
      final (c, depo) = await kartiAc();

      expect(durum(c).durum, BingoDurumu.oynaniyor);
      expect(durum(c).siradaki!.isim, 'Oyuncu 1');
      expect(durum(c).kalanOyuncu, 20);
      expect(depo.istenenOyunTipleri, [testOyunTipi]);
      expect(depo.acilanKayitTipleri, [testOyunTipi]);
    });

    test('günün kartı yoksa "oyun yok" gösterilir ve kayıt açılmaz', () async {
      final (c, depo) = await kartiAc((d) => d.oyun = null);

      expect(durum(c).durum, BingoDurumu.oyunYok);
      expect(depo.kayitAcSayisi, 0);
    });

    test('bugün başka bir zorluk oynandıysa oyun açılmaz, nedeni söylenir', () async {
      final (c, _) = await kartiAc((d) => d.baskaModOynandi = true);

      expect(durum(c).durum, BingoDurumu.hata);
      expect(durum(c).hataMesaji, baskaZorlukMesaji);
    });

    test('yarım kalan kart sunucudaki hamlelerle kaldığı yerden açılır', () async {
      final (c, depo) = await kartiAc((d) => d
        ..kayit = {'skor': 1, 'durum': 'basladi'}
        ..bingoHamleListesi = [
          const BingoHamlesi(sira: 1, hucre: 0, dogru: true),
          const BingoHamlesi(sira: 2, dogru: false),
          const BingoHamlesi(sira: 3, hucre: 7, dogru: false),
        ]);

      expect(durum(c).durum, BingoDurumu.oynaniyor);
      expect(durum(c).hucreler.keys, [0]);
      expect(durum(c).hucreler[0]!.isim, 'Oyuncu 1');
      expect(durum(c).siradaki!.isim, 'Oyuncu 4');
      expect(depo.kayitAcSayisi, 0);
    });

    test('bitmiş kart sonucuyla ve boş kutuların örnek cevaplarıyla açılır', () async {
      final (c, _) = await kartiAc((d) => d
        ..kayit = {'skor': 1, 'durum': 'tamamlandi'}
        ..bingoHamleListesi = [const BingoHamlesi(sira: 1, hucre: 0, dogru: true)]);

      expect(durum(c).durum, BingoDurumu.bitti);
      expect(durum(c).ornekCevaplar.containsKey(0), isFalse);
      expect(durum(c).ornekCevaplar, hasLength(15));
    });
  });

  group('Hamleler', () {
    test('doğru kutuya konan oyuncu kutuyu doldurur, sıradaki oyuncu gelir', () async {
      final (c, depo) = await kartiAc();

      await notifier(c).yerlestir(0);

      expect(depo.bingoHamleIstekleri, [(sira: 1, hucre: 0)]);
      expect(durum(c).hucreler[0]!.isim, 'Oyuncu 1');
      expect(durum(c).skor, 1);
      expect(durum(c).siradaki!.isim, 'Oyuncu 2');
      expect(durum(c).sonHamle!.dogru, isTrue);
    });

    test('yanlış kutuya konan oyuncu yanar, kutu boş kalır', () async {
      final (c, _) = await kartiAc();

      await notifier(c).yerlestir(3);

      expect(durum(c).hucreler, isEmpty);
      expect(durum(c).siradaki!.isim, 'Oyuncu 2');
      expect(durum(c).sonHamle!.dogru, isFalse);
      expect(durum(c).sonHamle!.hucre, 3);
    });

    test('pas geçilen oyuncu sıradakine geçer', () async {
      final (c, depo) = await kartiAc();

      await notifier(c).pasGec();

      expect(depo.bingoHamleIstekleri, [(sira: 1, hucre: null)]);
      expect(durum(c).siradaki!.isim, 'Oyuncu 2');
      expect(durum(c).sonHamle!.hucre, isNull);
    });

    test('dolu kutuya oyuncu konmaz, sunucuya istek gitmez', () async {
      final (c, depo) = await kartiAc((d) => d.bingoEslesmeleri = {1: [0], 2: [0]});

      await notifier(c).yerlestir(0);
      await notifier(c).yerlestir(0);

      expect(depo.bingoHamleIstekleri, hasLength(1));
      expect(durum(c).siradaki!.isim, 'Oyuncu 2');
    });

    test('deste bitince oyun biter ve örnek cevaplar yüklenir', () async {
      final (c, _) = await kartiAc((d) => d.bingoDesteBoyutu = 2);

      await notifier(c).yerlestir(0);
      await notifier(c).pasGec();

      expect(durum(c).durum, BingoDurumu.bitti);
      expect(durum(c).skor, 1);
      expect(durum(c).ornekCevaplar, hasLength(15));
    });

    test('bağlantı hatasında hamle sayılmaz, mesaj döner', () async {
      final (c, _) = await kartiAc((d) => d.bingoHamleHataVerir = true);

      final hata = await notifier(c).yerlestir(0);

      expect(hata, gonderimHataMesaji);
      expect(durum(c).siradaki!.isim, 'Oyuncu 1');
      expect(durum(c).gonderiliyor, isFalse);
    });

    test('pes edince oyun o anki skorla biter', () async {
      final (c, depo) = await kartiAc();

      await notifier(c).yerlestir(0);
      await notifier(c).pesEt();

      expect(durum(c).durum, BingoDurumu.bitti);
      expect(depo.bingoPesSayisi, 1);
      expect(depo.kayit!['skor'], 1);
    });
  });

  group('Süre', () {
    test('yeni oyunda seçilen süre sunucuda başlatılır', () async {
      final (c, depo) = await kartiAc((d) => d..oyunSureToplam = 60..oyunSureKalan = 60, 60);

      expect(depo.oyunSureIstekleri, [60]);
      expect(durum(c, 60).sureSaniye, 60);
      expect(durum(c, 60).bitisZamani, isNotNull);
    });

    test('uygulama kapalıyken süre dolduysa kart açılırken kapatılır', () async {
      final (c, depo) = await kartiAc((d) => d
        ..kayit = {'skor': 0, 'durum': 'basladi'}
        ..oyunSureToplam = 30
        ..oyunSureKalan = 0);

      expect(durum(c).durum, BingoDurumu.bitti);
      expect(durum(c).sureDoldu, isTrue);
      expect(depo.bingoPesSayisi, 1);
    });

    test('sunucu süreyi dolmuş bulursa hamle sayılmaz, oyun biter', () async {
      final (c, _) = await kartiAc((d) => d.bingoSuresiDoldu = true);

      await notifier(c).yerlestir(0);

      expect(durum(c).durum, BingoDurumu.bitti);
      expect(durum(c).sureDoldu, isTrue);
      expect(durum(c).hucreler, isEmpty);
    });
  });

  group('Ekran', () {
    Future<SahteOyunDeposu> ekraniAc(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);

      final depo = bingoDeposu();
      await tester.pumpWidget(ProviderScope(
        overrides: [oyunDeposuProvider.overrideWithValue(depo)],
        child: const MaterialApp(home: BingoScreen(oyunTipi: testOyunTipi)),
      ));
      await tester.pumpAndSettle();
      return depo;
    }

    testWidgets('sıradaki oyuncu, kart ve zorluk görünür', (tester) async {
      await ekraniAc(tester);

      expect(find.text('Oyuncu 1'), findsOneWidget);
      expect(find.text('ORTA'), findsOneWidget);
      expect(find.text('Kulüp 0'), findsOneWidget);
      expect(find.text('Kupa 3'), findsOneWidget);
      expect(find.text('0/16 kutu'), findsOneWidget);
      expect(find.text('20 oyuncu kaldı'), findsOneWidget);
    });

    testWidgets('kutuya dokununca oyuncu yerleşir, pas ile sıradaki gelir', (tester) async {
      final depo = await ekraniAc(tester);

      await tester.tap(find.text('Kulüp 0'));
      await tester.pumpAndSettle();
      expect(find.text('1/16 kutu'), findsOneWidget);
      expect(find.text('Oyuncu 2'), findsOneWidget);

      await tester.tap(find.text('Pas'));
      await tester.pumpAndSettle();
      expect(find.text('Oyuncu 3'), findsOneWidget);
      expect(depo.bingoHamleIstekleri, [(sira: 1, hucre: 0), (sira: 2, hucre: null)]);
    });

    testWidgets('küçük ekranda kart taşmaz', (tester) async {
      tester.view.physicalSize = const Size(640, 1136);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(ProviderScope(
        overrides: [oyunDeposuProvider.overrideWithValue(bingoDeposu())],
        child: const MaterialApp(home: BingoScreen(oyunTipi: testOyunTipi)),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kulüp 0'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('1/16 kutu'), findsOneWidget);
    });

    testWidgets('pes et onay sorar, onaylanınca sonuç ekranı açılır', (tester) async {
      await ekraniAc(tester);

      await tester.tap(find.text('Pes et'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Pes et').last);
      await tester.pumpAndSettle();

      expect(find.text('Ana menüye dön'), findsOneWidget);
      expect(find.text('Örnek Oyuncu 0'), findsOneWidget);
    });
  });
}
