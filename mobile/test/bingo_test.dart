import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/bingo.dart';
import 'package:mobile/providers/bingo_provider.dart';
import 'package:mobile/screens/bingo_screen.dart';
import 'package:mobile/services/gunluk_oyun.dart';
import 'package:mobile/services/oyun_deposu.dart';

import 'yardimcilar/sahte_oyun_deposu.dart';

// 12 kutu (4 satır, 3 sütun): 4 kulüp, 3 milli takım, 2 lig, 3 başarı; deste 16 oyuncu
final ornekKart = {
  'hucreler': [
    for (var i = 0; i < 4; i++) {'tip': 'kulup', 'anahtar': 'k$i', 'isim': 'Kulüp $i', 'id': 'kulup-$i', 'logo': null},
    for (var i = 0; i < 3; i++) {'tip': 'milli', 'anahtar': 'm$i', 'isim': 'Ülke $i'},
    for (var i = 0; i < 2; i++) {'tip': 'lig', 'anahtar': 'l$i', 'isim': 'Lig $i'},
    for (var i = 0; i < 3; i++) {'tip': 'basari', 'anahtar': 'b$i', 'isim': 'Kupa $i'},
  ],
  'oyuncular': [
    for (var i = 1; i <= 16; i++) {'id': 'o-$i', 'isim': 'Oyuncu $i', 'foto': null},
  ],
};

const testOyunTipi = 'bingo';

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
    test('sıradaki oyuncu: son gelenden sonraki yerleşmemiş ilk oyuncu, deste başa döner', () {
      expect(bingoSiradaki(desteBoyutu: 4, yerlesenler: {}, son: 0), 1);
      expect(bingoSiradaki(desteBoyutu: 4, yerlesenler: {}, son: 4), 1);
      expect(bingoSiradaki(desteBoyutu: 4, yerlesenler: {1, 2}, son: 4), 3);
      expect(bingoSiradaki(desteBoyutu: 4, yerlesenler: {1, 3, 4}, son: 2), 2);
      expect(bingoSiradaki(desteBoyutu: 4, yerlesenler: {1, 2, 3, 4}, son: 2), isNull);
    });


    test('soru verisinden 12 kutu ve deste okunur, kart 4 satır 3 sütundur', () {
      final kart = BingoKarti.oku(ornekKart)!;

      expect(kart.hucreler, hasLength(12));
      expect(kart.satirSayisi, 4);
      expect(kart.sutunSayisi, 3);
      expect(kart.deste, hasLength(16));
      expect(kart.hucreler.first.tip, BingoKategoriTipi.kulup);
      expect(kart.hucreler.last.tip, BingoKategoriTipi.basari);
      expect(kart.hucreler.last.aciklama, 'kazandı');
    });

    test('eksik ya da bozuk kart okunmaz', () {
      expect(BingoKarti.oku(null), isNull);
      expect(BingoKarti.oku({'hucreler': [], 'oyuncular': []}), isNull);
      expect(BingoKarti.oku({...ornekKart, 'oyuncular': []}), isNull);
    });

    test('tek moddan önce üretilmiş 16 kutulu kart da 4x4 okunur', () {
      final hucreler = ornekKart['hucreler']!;
      final kart = BingoKarti.oku({...ornekKart, 'hucreler': [...hucreler, ...hucreler.take(4)]})!;

      expect(kart.hucreSayisi, 16);
      expect(kart.sutunSayisi, 4);
      expect(kart.satirSayisi, 4);
    });
  });

  group('Oyunun açılması', () {
    test('günün kartı varsa oyun başlar, tek modlu Bingo kaydı açılır ve ilk oyuncu gelir', () async {
      final (c, depo) = await kartiAc();

      expect(durum(c).durum, BingoDurumu.oynaniyor);
      expect(durum(c).siradaki!.isim, 'Oyuncu 1');
      expect(durum(c).siradakiSira, 1);
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

    test('deste dönmüşken yarım kalan kart doğru oyuncuyla açılır', () async {
      final (c, depo) = await kartiAc((d) => d
        ..bingoDesteBoyutu = 3
        ..kayit = {'skor': 1, 'durum': 'basladi'}
        ..bingoHamleListesi = [
          const BingoHamlesi(sira: 1, oyuncu: 1, hucre: 0, dogru: true),
          const BingoHamlesi(sira: 2, oyuncu: 2, dogru: false),
          const BingoHamlesi(sira: 3, oyuncu: 3, dogru: false),
          const BingoHamlesi(sira: 4, oyuncu: 2, dogru: false),
        ]);

      expect(durum(c).hucreler[0]!.isim, 'Oyuncu 1');
      expect(durum(c).siradaki!.isim, 'Oyuncu 3');

      await notifier(c).pasGec();
      expect(depo.bingoHamleIstekleri.single.sira, 5);
      expect(durum(c).siradaki!.isim, 'Oyuncu 2');
    });

    test('bitmiş kart sonucuyla ve boş kutuların örnek cevaplarıyla açılır', () async {
      final (c, _) = await kartiAc((d) => d
        ..kayit = {'skor': 1, 'durum': 'tamamlandi'}
        ..bingoHamleListesi = [const BingoHamlesi(sira: 1, hucre: 0, dogru: true)]);

      expect(durum(c).durum, BingoDurumu.bitti);
      expect(durum(c).ornekCevaplar.containsKey(0), isFalse);
      expect(durum(c).ornekCevaplar, hasLength(11));
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

    test('yanlış kutuya konan oyuncu gitmez, kutu kırmızı gösterilir, başka kutu denenebilir', () async {
      final (c, depo) = await kartiAc();

      await notifier(c).yerlestir(3);

      expect(durum(c).hucreler, isEmpty);
      expect(durum(c).siradaki!.isim, 'Oyuncu 1');
      expect(durum(c).hamleSayisi, 0);
      expect(durum(c).sonHamle!.dogru, isFalse);
      expect(durum(c).yanlisKutu, 3);

      // Ceza yok: aynı oyuncu doğru kutuya konabilir
      await notifier(c).yerlestir(0);

      expect(depo.bingoHamleIstekleri, [(sira: 1, hucre: 3), (sira: 1, hucre: 0)]);
      expect(durum(c).hucreler[0]!.isim, 'Oyuncu 1');
      expect(durum(c).siradaki!.isim, 'Oyuncu 2');
      expect(durum(c).yanlisKutu, isNull);
    });

    test('yanlış kutudan sonra pas geçilince oyuncu gider', () async {
      final (c, _) = await kartiAc();

      await notifier(c).yerlestir(3);
      await notifier(c).pasGec();

      expect(durum(c).siradaki!.isim, 'Oyuncu 2');
      expect(durum(c).yanlisKutu, isNull);
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

    test('kalan oyuncuların hiçbiri boş kutulara uymuyorsa oyun biter ve örnek cevaplar yüklenir', () async {
      // Sadece 1. oyuncu (kutu 0) ve 2. oyuncu (kutu 5 ya da 6) bir kutuya uyar
      final (c, _) = await kartiAc();

      await notifier(c).yerlestir(0);
      await notifier(c).pasGec();
      expect(durum(c).durum, BingoDurumu.oynaniyor); // 2. oyuncu hâlâ uyuyor, sırası tekrar gelecek

      for (var i = 0; i < 20 && durum(c).siradaki!.isim != 'Oyuncu 2'; i++) {
        await notifier(c).pasGec();
      }
      await notifier(c).yerlestir(5);

      expect(durum(c).durum, BingoDurumu.bitti);
      expect(durum(c).skor, 2);
      expect(durum(c).ornekCevaplar, hasLength(10));
    });

    test('pas sınırsızdır: destede sıra döner, pas geçilen oyuncu tekrar gelir, yerleşen gelmez', () async {
      final (c, depo) = await kartiAc((d) => d.bingoDesteBoyutu = 3);

      await notifier(c).yerlestir(0); // 1. oyuncu yerleşti
      await notifier(c).pasGec(); // 2
      await notifier(c).pasGec(); // 3
      expect(durum(c).siradaki!.isim, 'Oyuncu 2'); // 1 yerleştiği için atlanır

      await notifier(c).pasGec(); // 2
      await notifier(c).pasGec(); // 3
      await notifier(c).pasGec(); // 2
      expect(durum(c).siradaki!.isim, 'Oyuncu 3');
      expect(durum(c).durum, BingoDurumu.oynaniyor);
      expect(depo.bingoHamleIstekleri.map((h) => h.sira), [1, 2, 3, 4, 5, 6]);
    });

    test('sunucu sıradaki oyuncuyu söylemezse uygulama aynı kuralla bulur', () async {
      final (c, _) = await kartiAc((d) => d.bingoSiradakiGonderir = false);

      await notifier(c).yerlestir(0); // 1. oyuncu yerleşti
      for (var i = 0; i < 15; i++) {
        await notifier(c).pasGec(); // 2..16
      }

      expect(durum(c).siradaki!.isim, 'Oyuncu 2');
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
        child: const MaterialApp(home: BingoScreen()),
      ));
      await tester.pumpAndSettle();
      return depo;
    }

    testWidgets('sıradaki oyuncu ve 12 kutulu kart görünür, zorluk etiketi yoktur', (tester) async {
      await ekraniAc(tester);

      expect(find.text('Oyuncu 1'), findsOneWidget);
      expect(find.text('ORTA'), findsNothing);
      expect(find.text('Kulüp 0'), findsOneWidget);
      expect(find.text('Kupa 2'), findsOneWidget);
      expect(find.text('0/12 kutu'), findsOneWidget);
      expect(find.textContaining('oyuncu kaldı'), findsNothing);
    });

    testWidgets('yanlış kutuya dokununca oyuncu ekranda kalır', (tester) async {
      await ekraniAc(tester);

      await tester.tap(find.text('Kulüp 3'));
      await tester.pumpAndSettle();

      expect(find.text('Oyuncu 1'), findsOneWidget);
      expect(find.textContaining('Yanlış', findRichText: true), findsOneWidget);
      expect(find.text('0/12 kutu'), findsOneWidget);
    });

    testWidgets('kutuya dokununca oyuncu yerleşir, pas ile sıradaki gelir', (tester) async {
      final depo = await ekraniAc(tester);

      await tester.tap(find.text('Kulüp 0'));
      await tester.pumpAndSettle();
      expect(find.text('1/12 kutu'), findsOneWidget);
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
        child: const MaterialApp(home: BingoScreen()),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kulüp 0'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('1/12 kutu'), findsOneWidget);
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
