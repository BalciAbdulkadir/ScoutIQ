import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/bonservis_sorusu.dart';
import 'package:mobile/providers/bonservis_provider.dart';
import 'package:mobile/screens/bonservis_screen.dart';
import 'package:mobile/services/oyun_deposu.dart';
import 'package:mobile/widgets/bonservis_oyuncu_karti.dart';

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

Future<(ProviderContainer, SahteOyunDeposu)> oyunuBaslat([void Function(SahteOyunDeposu)? ayarla]) async {
  final depo = bonservisDeposu();
  ayarla?.call(depo);

  final container = ProviderContainer(overrides: [oyunDeposuProvider.overrideWithValue(depo)]);
  addTearDown(container.dispose);
  container.listen(bonservisProvider, (_, _) {});

  for (var i = 0; i < 100 && container.read(bonservisProvider).durum == BonservisDurumu.yukleniyor; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  return (container, depo);
}

BonservisNotifier notifier(ProviderContainer c) => c.read(bonservisProvider.notifier);
BonservisState durum(ProviderContainer c) => c.read(bonservisProvider);

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

    test('avatar için ad ve soyadın baş harfleri alınır', () {
      expect(BonservisOyuncuKarti.basHarfler('Alexander Sørloth'), 'AS');
      expect(BonservisOyuncuKarti.basHarfler('Pedri'), 'P');
      expect(BonservisOyuncuKarti.basHarfler('Kevin De Bruyne'), 'KB');
    });
  });

  group('Oyun akışı', () {
    test('oyun açılınca kayıt "basladi" olarak atılır', () async {
      final (c, depo) = await oyunuBaslat();

      expect(durum(c).durum, BonservisDurumu.oynaniyor);
      expect(durum(c).soru!.referans.isim, 'Pedri');
      expect(depo.kayit, {'skor': 0, 'durum': 'basladi'});
    });

    test('doğru tahmin skoru artırır, sonuç gösterilir, devam edince sıradaki soruya geçilir', () async {
      final (c, depo) = await oyunuBaslat();

      await notifier(c).tahminEt(dahaFazla: true);

      expect(durum(c).skor, 1);
      expect(durum(c).sonCevapDogru, isTrue);
      expect(durum(c).soruIndex, 0);
      expect(depo.yazilanSkorlar.single, (skor: 1, bitti: false));

      notifier(c).devamEt();

      expect(durum(c).soruIndex, 1);
      expect(durum(c).sonCevapDogru, isNull);
      expect(durum(c).soru!.referans.isim, 'Kane');
    });

    test('yanlış tahminde oyun biter ve kayıt kilitlenir', () async {
      final (c, depo) = await oyunuBaslat();

      await notifier(c).tahminEt(dahaFazla: false);

      expect(durum(c).sonCevapDogru, isFalse);
      expect(depo.kayit, {'skor': 0, 'durum': 'tamamlandi'});

      notifier(c).devamEt();
      expect(durum(c).durum, BonservisDurumu.bitti);
    });

    test('beş soruyu da bilen 5 puanla bitirir', () async {
      final (c, depo) = await oyunuBaslat();

      for (final tahmin in dogruTahminler) {
        await notifier(c).tahminEt(dahaFazla: tahmin);
        notifier(c).devamEt();
      }

      expect(durum(c).durum, BonservisDurumu.bitti);
      expect(durum(c).skor, 5);
      expect(durum(c).sonuclar, [true, true, true, true, true]);
      expect(depo.yazilanSkorlar.where((s) => s.bitti), hasLength(1));
      expect(depo.kayit, {'skor': 5, 'durum': 'tamamlandi'});
    });

    test('sonuç gösterilirken yeni tahmin yok sayılır', () async {
      final (c, depo) = await oyunuBaslat();

      await notifier(c).tahminEt(dahaFazla: true);
      await notifier(c).tahminEt(dahaFazla: true);

      expect(durum(c).skor, 1);
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
      expect(durum(c).skor, 1);
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
    Future<SahteOyunDeposu> ekraniAc(WidgetTester tester) async {
      // Emulatördeki telefon boyutu (1080x2400)
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);

      final depo = bonservisDeposu();
      await tester.pumpWidget(ProviderScope(
        overrides: [oyunDeposuProvider.overrideWithValue(depo)],
        child: const MaterialApp(home: BonservisScreen()),
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

      await tester.ensureVisible(find.text('Daha Fazla'));
      await tester.tap(find.text('Daha Fazla'));
      await tester.pumpAndSettle();

      expect(find.text('Doğru!'), findsOneWidget);
    });

    testWidgets('referansın bedeli görünür, rakibinki gizlidir', (tester) async {
      await ekraniAc(tester);

      expect(find.text('Pedri'), findsOneWidget);
      expect(find.text('50 M€'), findsOneWidget);
      expect(find.text('Saka'), findsOneWidget);
      expect(find.text('? M€'), findsOneWidget);
      expect(find.text('Soru 1 / 5'), findsOneWidget);
    });

    testWidgets('doğru tahminde bedel açılır, sonra sıradaki soruya geçilir', (tester) async {
      await ekraniAc(tester);

      await tahminEt(tester, 'Daha Fazla');

      expect(find.text('Doğru!'), findsOneWidget);
      expect(find.text('70 M€'), findsOneWidget);
      expect(find.text('Daha Fazla'), findsNothing);

      await tester.pump(BonservisScreen.sonucBeklemesi);
      await tester.pumpAndSettle();

      expect(find.text('Soru 2 / 5'), findsOneWidget);
      expect(find.text('Dumfries'), findsOneWidget);
      expect(find.text('Daha Fazla'), findsOneWidget);
    });

    testWidgets('doğru cevap "Daha Az" ise "Daha Az" doğru sayılır', (tester) async {
      await ekraniAc(tester);
      await tahminEt(tester, 'Daha Fazla'); // 1. soru: Saka daha pahalı
      await tester.tap(find.text('Sıradaki'));
      await tester.pumpAndSettle();

      await tahminEt(tester, 'Daha Az'); // 2. soru: Dumfries (40) < Kane (90)

      expect(find.text('Doğru!'), findsOneWidget);
      expect(find.text('Skor: 2'), findsOneWidget);
    });

    testWidgets('"Sıradaki" butonu beklemeden geçirir', (tester) async {
      await ekraniAc(tester);

      await tahminEt(tester, 'Daha Fazla');
      await tester.tap(find.text('Sıradaki'));
      await tester.pumpAndSettle();

      expect(find.text('Soru 2 / 5'), findsOneWidget);
    });

    testWidgets('yanlış tahminde oyun biter ve eşleşmeler listelenir', (tester) async {
      await ekraniAc(tester);

      await tahminEt(tester, 'Daha Fazla'); // doğru
      await tester.tap(find.text('Sıradaki'));
      await tester.pumpAndSettle();
      await tahminEt(tester, 'Daha Fazla'); // yanlış: Dumfries daha ucuz

      expect(find.text('Yanlış!'), findsOneWidget);
      await tester.tap(find.text('Sonucu Gör'));
      await tester.pumpAndSettle();

      expect(find.text('1/5'), findsOneWidget);
      expect(find.text('Bugünün eşleşmeleri'), findsOneWidget);
      expect(find.text('Dumfries'), findsOneWidget);
    });
  });
}
