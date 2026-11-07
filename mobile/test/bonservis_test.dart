import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/bonservis_sorusu.dart';
import 'package:mobile/providers/bonservis_provider.dart';
import 'package:mobile/screens/bonservis_screen.dart';
import 'package:mobile/services/oyun_deposu.dart';
import 'package:mobile/widgets/oyun_ortak.dart';
import 'package:mobile/widgets/oyuncu_fotografi.dart';

import 'yardimcilar/sahte_oyun_deposu.dart';

// Backend'in ürettiği biçimde 5 bağımsız ikili. Soldaki oyuncunun bedeli görünür, sağdaki tahmin edilir.
//   1. Pedri (50) x Saka (70)       -> daha fazla
//   2. Kane (90) x Dumfries (40)    -> daha az
//   3. Barella (60) x Rice (100)    -> daha fazla
//   4. Osimhen (75) x Kim (50)      -> daha az
//   5. Wirtz (125) x Isak (145)     -> daha fazla
Map<String, dynamic> soru(String a, int aBedel, String b, int bBedel) => {
      'oyuncu_a': a,
      'oyuncu_a_id': 'id-$a',
      'oyuncu_a_bonservis': aBedel * 1000000,
      'oyuncu_b': b,
      'oyuncu_b_id': 'id-$b',
      'oyuncu_b_bonservis': bBedel * 1000000,
    };

final sorular = [
  soru('Pedri', 50, 'Saka', 70),
  soru('Kane', 90, 'Dumfries', 40),
  soru('Barella', 60, 'Rice', 100),
  soru('Osimhen', 75, 'Kim', 50),
  soru('Wirtz', 125, 'Isak', 145),
];

// Her sorunun doğru tahmini: sağdaki oyuncu daha mı pahalı
const dogruTahminler = [true, false, true, false, true];

SahteOyunDeposu bonservisDeposu() => SahteOyunDeposu()..oyun = {'id': 'oyun-b', 'soru_verisi': sorular};

// Testteki oyunun seçilen süresi (saniye); null: süresiz. oyunuBaslat ayarlar.
int? testSuresi;

Future<(ProviderContainer, SahteOyunDeposu)> oyunuBaslat([void Function(SahteOyunDeposu)? ayarla, int? sure]) async {
  testSuresi = sure;
  final depo = bonservisDeposu();
  ayarla?.call(depo);

  final container = ProviderContainer(overrides: [oyunDeposuProvider.overrideWithValue(depo)]);
  addTearDown(container.dispose);
  container.listen(bonservisProvider(testSuresi), (_, _) {});

  for (var i = 0; i < 100 && container.read(bonservisProvider(testSuresi)).durum == BonservisDurumu.yukleniyor; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  return (container, depo);
}

BonservisNotifier notifier(ProviderContainer c) => c.read(bonservisProvider(testSuresi).notifier);
BonservisState durum(ProviderContainer c) => c.read(bonservisProvider(testSuresi));

void main() {
  group('Sorular', () {
    test('soldaki oyuncu referans (bedeli görünür), sağdaki rakip (tahmin edilir)', () {
      final okunan = bonservisSorulariniOku(sorular);

      expect(okunan.map((s) => s.referans.isim), ['Pedri', 'Kane', 'Barella', 'Osimhen', 'Wirtz']);
      expect(okunan.map((s) => s.rakip.isim), ['Saka', 'Dumfries', 'Rice', 'Kim', 'Isak']);
      expect(okunan.map((s) => s.rakipDahaPahali), dogruTahminler);
      expect(okunan.first.referans.toplamBonservis, 50000000);
    });

    test('bedeller milyon Euro olarak yazılır', () {
      expect(bonservisMetni(79000000), '79 M€');
      expect(bonservisMetni(77400000), '77,4 M€');
      expect(bonservisMetni(5500000), '5,5 M€');
    });

    test('fotoğraf adresleri sorudan okunur, fotoğrafsız eski oyunlarda boş kalır', () {
      final okunan = bonservisSorulariniOku([
        {...soru('Pedri', 50, 'Saka', 70), 'oyuncu_a_foto': 'https://foto.test/pedri.jpg', 'oyuncu_b_foto': null},
        soru('Kane', 90, 'Dumfries', 40),
      ]);

      expect(okunan[0].referans.fotoUrl, 'https://foto.test/pedri.jpg');
      expect(okunan[0].rakip.fotoUrl, isNull);
      expect(okunan[1].referans.fotoUrl, isNull);
    });

    test('fotoğraf yoksa avatar için ad ve soyadın baş harfleri alınır', () {
      expect(OyuncuFotografi.basHarfler('Alexander Sørloth'), 'AS');
      expect(OyuncuFotografi.basHarfler('Pedri'), 'P');
      expect(OyuncuFotografi.basHarfler('Kevin De Bruyne'), 'KB');
    });
  });

  group('Oyun akışı', () {
    test('oyun açılınca kayıt "basladi" olarak atılır', () async {
      final (c, depo) = await oyunuBaslat();

      expect(durum(c).durum, BonservisDurumu.oynaniyor);
      expect(durum(c).soru!.referans.isim, 'Pedri');
      expect(depo.kayit, {'skor': 0, 'durum': 'basladi'});
    });

    test('doğru tahmin 2 puan kazandırır, sonuç gösterilir, devam edince sıradaki soruya geçilir', () async {
      final (c, depo) = await oyunuBaslat();

      await notifier(c).tahminEt(dahaFazla: true);

      expect(durum(c).skor, 2);
      expect(durum(c).sonCevapDogru, isTrue);
      expect(durum(c).soruIndex, 0);
      expect(depo.yazilanSkorlar.single, (skor: 2, bitti: false));

      notifier(c).devamEt();

      expect(durum(c).soruIndex, 1);
      expect(durum(c).sonCevapDogru, isNull);
      expect(durum(c).soru!.referans.isim, 'Kane');
    });

    test('yanlış tahminde oyun bitmez, puan artmaz, sıradaki soruya geçilir', () async {
      final (c, depo) = await oyunuBaslat();

      await notifier(c).tahminEt(dahaFazla: false);

      expect(durum(c).sonCevapDogru, isFalse);
      expect(durum(c).skor, 0);
      expect(depo.kayit, {'skor': 0, 'durum': 'basladi'});

      notifier(c).devamEt();
      expect(durum(c).durum, BonservisDurumu.oynaniyor);
      expect(durum(c).soruIndex, 1);
    });

    test('yanlışlar olsa da beş soru oynanır, oyun son soruda biter ve kayıt kilitlenir', () async {
      final (c, depo) = await oyunuBaslat();

      // 1., 3. ve 5. soru doğru, 2. ve 4. yanlış
      for (var i = 0; i < dogruTahminler.length; i++) {
        await notifier(c).tahminEt(dahaFazla: i.isEven ? dogruTahminler[i] : !dogruTahminler[i]);
        notifier(c).devamEt();
      }

      expect(durum(c).durum, BonservisDurumu.bitti);
      expect(durum(c).skor, 6);
      expect(durum(c).sonuclar, [true, false, true, false, true]);
      expect(depo.yazilanSkorlar.where((s) => s.bitti), hasLength(1));
      expect(depo.kayit, {'skor': 6, 'durum': 'tamamlandi'});
    });

    test('beş soruyu da bilen 10 puanla bitirir', () async {
      final (c, depo) = await oyunuBaslat();

      for (final tahmin in dogruTahminler) {
        await notifier(c).tahminEt(dahaFazla: tahmin);
        notifier(c).devamEt();
      }

      expect(durum(c).durum, BonservisDurumu.bitti);
      expect(durum(c).skor, 10);
      expect(durum(c).sonuclar, [true, true, true, true, true]);
      expect(depo.yazilanSkorlar.where((s) => s.bitti), hasLength(1));
      expect(depo.kayit, {'skor': 10, 'durum': 'tamamlandi'});
    });

    test('sonuç gösterilirken yeni tahmin yok sayılır', () async {
      final (c, depo) = await oyunuBaslat();

      await notifier(c).tahminEt(dahaFazla: true);
      await notifier(c).tahminEt(dahaFazla: true);

      expect(durum(c).skor, 2);
      expect(depo.yazilanSkorlar, hasLength(1));
    });

    test('tahmin kaydedilirken ikinci tahmin yok sayılır', () async {
      final (c, depo) = await oyunuBaslat((d) => d.skorYazBekletici = Completer<void>());

      final ilk = notifier(c).tahminEt(dahaFazla: true);
      expect(durum(c).gonderiliyor, isTrue);
      final ikinci = notifier(c).tahminEt(dahaFazla: false);
      depo.skorYazBekletici!.complete();
      await Future.wait([ilk, ikinci]);

      expect(depo.yazilanSkorlar, hasLength(1));
      expect(durum(c).sonCevapDogru, isTrue);
    });

    test('tahmin kaydedilemezse hata döner ve tekrar denenebilir', () async {
      final (c, depo) = await oyunuBaslat((d) => d.skorYazHataVerir = true);

      final hata = await notifier(c).tahminEt(dahaFazla: true);

      expect(hata, contains('gönderilemedi'));
      expect(durum(c).sonCevapDogru, isNull);
      expect(durum(c).tahminEdilebilir, isTrue);

      depo.skorYazHataVerir = false;
      await notifier(c).tahminEt(dahaFazla: true);
      expect(durum(c).skor, 2);
    });

    test('bugün oynanmış oyun açılmaz', () async {
      final (c, _) = await oyunuBaslat((d) => d.kayit = {'skor': 3, 'durum': 'tamamlandi'});

      expect(durum(c).durum, BonservisDurumu.zatenOynandi);
      expect(durum(c).skor, 3);
    });

    test('yarıda bırakılan oyun açılmaz', () async {
      final (c, depo) = await oyunuBaslat((d) => d.kayit = {'skor': 2, 'durum': 'basladi'});

      expect(durum(c).durum, BonservisDurumu.yaridaBirakildi);
      expect(depo.yarimKayitKapatildi, isTrue);
    });
  });

  group('Ekran', () {
    Future<SahteOyunDeposu> ekraniAc(WidgetTester tester, {int? sure}) async {
      // Emulatördeki telefon boyutu (1080x2400)
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);

      final depo = bonservisDeposu();
      await tester.pumpWidget(ProviderScope(
        overrides: [oyunDeposuProvider.overrideWithValue(depo)],
        child: MaterialApp(home: BonservisScreen(sure: sure)),
      ));
      await tester.pumpAndSettle();
      return depo;
    }

    Future<void> tahminEt(WidgetTester tester, String buton) async {
      await tester.tap(find.text(buton));
      await tester.pumpAndSettle();
    }

    testWidgets('küçük ekranda taşma olmaz, butonlara kaydırarak ulaşılır', (tester) async {
      tester.view.physicalSize = const Size(720, 1280);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(ProviderScope(
        overrides: [oyunDeposuProvider.overrideWithValue(bonservisDeposu())],
        child: const MaterialApp(home: BonservisScreen()),
      ));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Daha fazla'));
      await tester.tap(find.text('Daha fazla'));
      await tester.pumpAndSettle();

      expect(find.text('Doğru'), findsOneWidget);
    });

    testWidgets('referansın bedeli görünür, rakibinki gizlidir', (tester) async {
      await ekraniAc(tester);

      expect(find.text('Pedri'), findsOneWidget);
      expect(find.text('50 M€'), findsOneWidget);
      expect(find.text('Saka'), findsOneWidget);
      expect(find.text('? M€'), findsOneWidget);
      expect(find.text('Soru 1/5'), findsOneWidget);
    });

    testWidgets('doğru tahminde bedel açılır, sonra sıradaki soruya geçilir', (tester) async {
      await ekraniAc(tester);

      await tahminEt(tester, 'Daha fazla');

      expect(find.text('Doğru'), findsOneWidget);
      expect(find.text('70 M€'), findsOneWidget);
      expect(find.text('Daha fazla'), findsNothing);

      await tester.pump(BonservisScreen.sonucBeklemesi);
      await tester.pumpAndSettle();

      expect(find.text('Soru 2/5'), findsOneWidget);
      expect(find.text('Dumfries'), findsOneWidget);
      expect(find.text('Daha fazla'), findsOneWidget);
    });

    testWidgets('doğru cevap "Daha Az" ise "Daha Az" doğru sayılır', (tester) async {
      await ekraniAc(tester);
      await tahminEt(tester, 'Daha fazla'); // 1. soru: Saka daha pahalı
      await tester.tap(find.text('Devam'));
      await tester.pumpAndSettle();

      await tahminEt(tester, 'Daha az'); // 2. soru: Dumfries (40) < Kane (90)

      expect(find.text('Doğru'), findsOneWidget);
      expect(find.text('4 puan'), findsOneWidget);
    });

    testWidgets('"Sıradaki" butonu beklemeden geçirir', (tester) async {
      await ekraniAc(tester);

      await tahminEt(tester, 'Daha fazla');
      await tester.tap(find.text('Devam'));
      await tester.pumpAndSettle();

      expect(find.text('Soru 2/5'), findsOneWidget);
    });

    testWidgets('yanlış tahminde oyun sürer, beş soru bitince puan ve eşleşmeler listelenir', (tester) async {
      await ekraniAc(tester);

      await tahminEt(tester, 'Daha fazla'); // doğru
      await tester.tap(find.text('Devam'));
      await tester.pumpAndSettle();
      await tahminEt(tester, 'Daha fazla'); // yanlış: Dumfries daha ucuz

      expect(find.text('Yanlış'), findsOneWidget);
      await tester.tap(find.text('Devam'));
      await tester.pumpAndSettle();
      expect(find.text('Soru 3/5'), findsOneWidget);

      // Kalan üç soruyu doğru bil: 4 doğru, 8 puan
      for (final buton in ['Daha fazla', 'Daha az', 'Daha fazla']) {
        await tahminEt(tester, buton);
        // Son soruda buton "Sonuçları gör" olur
        final sonSoru = find.text('Sonuçları gör').evaluate().isNotEmpty;
        await tester.tap(find.text(sonSoru ? 'Sonuçları gör' : 'Devam'));
        await tester.pumpAndSettle();
      }

      expect(find.text('8/10'), findsOneWidget);
      expect(find.text('ÖZET'), findsOneWidget);
      expect(find.textContaining('Dumfries'), findsOneWidget);
    });

    testWidgets('süresiz oyunda sayaç görünmez', (tester) async {
      await ekraniAc(tester);

      expect(find.byType(SureSayaci), findsNothing);
    });

    testWidgets('süreli oyunda sayaç görünür', (tester) async {
      await ekraniAc(tester, sure: 60);

      expect(find.byType(SureSayaci), findsOneWidget);
      expect(find.text('1:00'), findsOneWidget);
    });
  });

  group('Süre', () {
    test('süre seçildiyse oyun başlarken sayaç kurulur, süresizde kurulmaz', () async {
      final (suresiz, _) = await oyunuBaslat();
      expect(durum(suresiz).bitisZamani, isNull);

      final once = DateTime.now();
      final (sureli, _) = await oyunuBaslat(null, 90);
      expect(durum(sureli).bitisZamani!.difference(once).inSeconds, inInclusiveRange(89, 90));
    });

    test('süre dolunca oyun o anki skorla biter ve kayıt kilitlenir', () async {
      final (c, depo) = await oyunuBaslat(null, 30);
      await notifier(c).tahminEt(dahaFazla: dogruTahminler[0]);
      notifier(c).devamEt();
      await notifier(c).tahminEt(dahaFazla: !dogruTahminler[1]);

      await notifier(c).sureDoldu();

      expect(durum(c).durum, BonservisDurumu.bitti);
      expect(durum(c).sureDoldu, isTrue);
      expect(durum(c).skor, 2);
      expect(durum(c).sonuclar, [true, false]);
      expect(depo.kayit, {'skor': 2, 'durum': 'tamamlandi'});

      // Sonuç bandındaki bekleme süre dolduktan sonra bitince sıradaki soruya geçilmez
      notifier(c).devamEt();
      expect(durum(c).durum, BonservisDurumu.bitti);
      expect(durum(c).soruIndex, 1);
    });

    test('tahmin gönderilirken süre dolarsa bildirim yok sayılır, tahmin işlenir', () async {
      final (c, depo) = await oyunuBaslat(null, 30);
      depo.skorYazBekletici = Completer<void>();

      final tahmin = notifier(c).tahminEt(dahaFazla: dogruTahminler[0]);
      await Future<void>.delayed(Duration.zero);
      await notifier(c).sureDoldu();
      expect(durum(c).durum, BonservisDurumu.oynaniyor);

      depo.skorYazBekletici!.complete();
      await tahmin;
      await notifier(c).sureDoldu();

      expect(durum(c).durum, BonservisDurumu.bitti);
      expect(depo.kayit, {'skor': 2, 'durum': 'tamamlandi'});
    });
  });
}
