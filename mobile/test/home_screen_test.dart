import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/izgara.dart';
import 'package:mobile/providers/hub_provider.dart';
import 'package:mobile/screens/bingo_screen.dart';
import 'package:mobile/screens/bonservis_screen.dart';
import 'package:mobile/screens/game_screen.dart';
import 'package:mobile/screens/home_screen.dart';
import 'package:mobile/screens/izgara_screen.dart';
import 'package:mobile/services/oyun_deposu.dart';
import 'package:mobile/theme/tema.dart';
import 'package:mobile/widgets/izgara_zorluk_secimi.dart';

import 'bonservis_test.dart' show sorular;
import 'izgara_test.dart' show ornekTahta;
import 'yardimcilar/sahte_oyun_deposu.dart';

Future<void> anaMenuyuAc(
  WidgetTester tester, {
  Map<String, int> oynananlar = const {},
  BugunkuIzgara? bugunkuIzgara,
  Map<String, BugunkuMod> bugunkuModlar = const {}, // oyun -> bugün açılan zorluk (Kesişim, Bonservis)
  List<Override> ekOverridelar = const [],
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      kullaniciProvider.overrideWithValue(const KullaniciBilgisi(ad: 'Celal Test', eposta: 'test@ornek.com')),
      bugunOynananlarProvider.overrideWith((ref) async => oynananlar),
      bugunkuIzgaraProvider.overrideWith((ref) async => bugunkuIzgara),
      bugunkuModProvider.overrideWith((ref, oyun) async => bugunkuModlar[oyun]),
      ...ekOverridelar,
    ],
    child: MaterialApp(theme: uygulamaTemasi(), home: const HomeScreen()),
  ));
  await tester.pump();
}

// Oyuna ilk dokunuşta gelen kural sayfasını geçer
Future<void> kurallariGec(WidgetTester tester) async {
  expect(find.text('NASIL OYNANIR'), findsOneWidget);
  await tester.tap(find.textContaining('ANLADIM'));
  await tester.pumpAndSettle();
}

// Günlük şerit her saniye güncellenen bir zamanlayıcı kullanır: test bitmeden ekranı kapatıyoruz
Future<void> ekraniKapat(WidgetTester tester) => tester.pumpWidget(const SizedBox());

void main() {
  testWidgets('kullanıcıyı ilk adıyla karşılar', (tester) async {
    await anaMenuyuAc(tester);

    expect(find.text('Merhaba, Celal'), findsOneWidget);
    await ekraniKapat(tester);
  });

  testWidgets('günlük ilerleme bitirilen oyunları sayar, biten kutucukta skor yazar', (tester) async {
    await anaMenuyuAc(tester, oynananlar: {'kesisim_kolay': 6});

    // Kesişim, Bonservis, Izgara ve Bingo: 4 günlük oyun (bir oyunun zorlukları tek oyun sayılır)
    expect(find.text('1 / 4'), findsOneWidget);
    expect(find.text('6/10'), findsOneWidget);
    expect(find.text('KOLAY'), findsOneWidget); // Kesişim'de oynanan zorluk
    expect(find.text('Oyna'), findsNWidgets(3)); // Bonservis, Izgara ve Bingo henüz oynanmadı
    await ekraniKapat(tester);
  });

  testWidgets("oyunlar kategorisiz tek ızgarada, zorluklu oyunlarda K O Z, Bingo'da tek mod yazar", (tester) async {
    await anaMenuyuAc(tester);

    expect(find.text('KESİŞİM'), findsOneWidget);
    expect(find.text('BONSERVİS'), findsOneWidget);
    expect(find.text('IZGARA'), findsOneWidget);
    expect(find.text('K'), findsNWidgets(3));
    expect(find.text('O'), findsNWidgets(3));
    expect(find.text('Z'), findsNWidgets(3));
    expect(find.text('TEK MOD'), findsOneWidget);
    await ekraniKapat(tester);
  });

  testWidgets('Kesişim\'e dokununca önce zorluk, sonra süre seçilir ve o zorluğun oyunu o süreyle açılır', (tester) async {
    final depo = SahteOyunDeposu();
    await anaMenuyuAc(tester, ekOverridelar: [oyunDeposuProvider.overrideWithValue(depo)]);

    await tester.tap(find.text('KESİŞİM'));
    await tester.pumpAndSettle();
    await kurallariGec(tester);

    expect(find.text('1 · ZORLUK SEÇ'), findsOneWidget);
    expect(find.text('Sadece ünlü oyuncular'), findsOneWidget);

    await tester.tap(find.text('ORTA'));
    await tester.pumpAndSettle();

    expect(find.text('2 · SÜRE SEÇ'), findsOneWidget);
    await tester.tap(find.text('30'));
    await tester.pump();
    await tester.tap(find.text('ORTA · 30 SN BAŞLA'));
    await tester.pumpAndSettle();

    final ekran = tester.widget<GameScreen>(find.byType(GameScreen));
    expect(ekran.oyunTipi, 'kesisim_orta');
    expect(ekran.sure, 30);
    expect(depo.istenenOyunTipleri, ['kesisim_orta']);
    expect(find.text('0:30'), findsOneWidget);
    await ekraniKapat(tester);
  });

  testWidgets('bugün Bonservis\'in bir zorluğu açıldıysa seçim sorulmaz, o zorluk açılır', (tester) async {
    final depo = SahteOyunDeposu()..kayit = {'skor': 6, 'durum': 'tamamlandi'};
    await anaMenuyuAc(
      tester,
      oynananlar: {'bonservis_zor': 6},
      bugunkuModlar: {'bonservis': (zorluk: 2, bitti: true)},
      ekOverridelar: [oyunDeposuProvider.overrideWithValue(depo)],
    );

    expect(find.text('ZOR'), findsOneWidget);

    await tester.tap(find.text('BONSERVİS'));
    await tester.pumpAndSettle();

    expect(find.text('ZORLUK SEÇ'), findsNothing);
    expect(tester.widget<BonservisScreen>(find.byType(BonservisScreen)).oyunTipi, 'bonservis_zor');
    expect(depo.kayitAcSayisi, 0);
    await ekraniKapat(tester);
  });

  testWidgets('Izgara\'da bir zorluk bitince kutucuk o zorluk ve skorla kapanır', (tester) async {
    await anaMenuyuAc(tester, oynananlar: {'izgara_kolay': 7});

    expect(find.text('7/9'), findsOneWidget);
    expect(find.text('KOLAY'), findsOneWidget);
    expect(find.text('1 / 4'), findsOneWidget);
    expect(find.text('Oyna'), findsNWidgets(3));
    await ekraniKapat(tester);
  });

  testWidgets('Izgara\'ya dokununca önce zorluk, sonra süre seçilir ve tahta o süreyle açılır', (tester) async {
    final depo = SahteOyunDeposu()..oyun = {'id': 'izgara-1', 'soru_verisi': ornekTahta};
    await anaMenuyuAc(tester, ekOverridelar: [oyunDeposuProvider.overrideWithValue(depo)]);

    await tester.tap(find.text('IZGARA'));
    await tester.pumpAndSettle();
    await kurallariGec(tester);

    expect(find.text('1 · ZORLUK SEÇ'), findsOneWidget);
    expect(find.text('KOLAY'), findsOneWidget);
    expect(find.text('ORTA'), findsOneWidget);
    expect(find.text('ZOR'), findsOneWidget);

    await tester.tap(find.text('ORTA'));
    await tester.pumpAndSettle();

    expect(find.text('2 · SÜRE SEÇ'), findsOneWidget);
    expect(find.text('∞'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);
    expect(find.text('60'), findsOneWidget);
    expect(find.text('90'), findsOneWidget);
    // Süre seçilmeden başlanamaz
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);

    await tester.tap(find.text('60'));
    await tester.pump();
    await tester.tap(find.text('ORTA · 60 SN BAŞLA'));
    await tester.pumpAndSettle();

    final ekran = tester.widget<IzgaraScreen>(find.byType(IzgaraScreen));
    expect(ekran.zorluk, IzgaraZorlugu.orta);
    expect(ekran.sure, 60);
    // Süre sunucuda başlatıldı
    expect(depo.sureBaslatmaIstekleri, [60]);
    expect(find.text('1:00'), findsOneWidget);
    await ekraniKapat(tester);
  });

  testWidgets('Bonservis süresiz seçilince sayaçsız açılır', (tester) async {
    await anaMenuyuAc(tester, ekOverridelar: [oyunDeposuProvider.overrideWithValue(SahteOyunDeposu())]);

    await tester.tap(find.text('BONSERVİS'));
    await tester.pumpAndSettle();
    await kurallariGec(tester);
    await tester.tap(find.text('KOLAY'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('∞'));
    await tester.pump();
    await tester.tap(find.text('KOLAY · SÜRESİZ BAŞLA'));
    await tester.pumpAndSettle();

    final ekran = tester.widget<BonservisScreen>(find.byType(BonservisScreen));
    expect(ekran.oyunTipi, 'bonservis_kolay');
    expect(ekran.sure, isNull);
    await ekraniKapat(tester);
  });

  testWidgets("bugün oynanmış Kesişim'e dokununca seçim sorulmadan sonuç açılır", (tester) async {
    final depo = SahteOyunDeposu()..kayit = {'skor': 6, 'durum': 'tamamlandi'};
    await anaMenuyuAc(
      tester,
      oynananlar: {'kesisim_kolay': 6},
      bugunkuModlar: {'kesisim': (zorluk: 0, bitti: true)},
      ekOverridelar: [oyunDeposuProvider.overrideWithValue(depo)],
    );

    await tester.tap(find.text('KESİŞİM'));
    await tester.pumpAndSettle();

    expect(find.text('1 · ZORLUK SEÇ'), findsNothing);
    expect(find.text('Bugünkü oyununu oynadın'), findsOneWidget);
    await ekraniKapat(tester);
  });

  testWidgets('yarım kalan Bonservis\'te "Devam et" yazar, süre sorulmadan kaldığı yerden açılır', (tester) async {
    final depo = SahteOyunDeposu()
      ..oyun = {'id': 'oyun-b', 'soru_verisi': sorular}
      ..kayit = {'skor': 2, 'durum': 'basladi'}
      ..ilerleme = [
        {'dogru': true},
      ]
      ..oyunSureToplam = 60
      ..oyunSureKalan = 40;
    await anaMenuyuAc(
      tester,
      bugunkuModlar: {'bonservis': (zorluk: 1, bitti: false)},
      ekOverridelar: [oyunDeposuProvider.overrideWithValue(depo)],
    );

    expect(find.text('Devam et'), findsOneWidget);
    expect(find.text('ORTA'), findsOneWidget);

    await tester.tap(find.text('BONSERVİS'));
    await tester.pumpAndSettle();

    expect(find.text('1 · ZORLUK SEÇ'), findsNothing);
    expect(tester.widget<BonservisScreen>(find.byType(BonservisScreen)).oyunTipi, 'bonservis_orta');
    expect(find.text('Soru 2/5'), findsOneWidget);
    expect(find.text('0:40'), findsOneWidget);
    await ekraniKapat(tester);
  });

  testWidgets('zorluk seçiminden geri dönülebilir', (tester) async {
    await anaMenuyuAc(tester);

    await tester.tap(find.text('IZGARA'));
    await tester.pumpAndSettle();
    await kurallariGec(tester);
    await tester.tap(find.text('ZOR'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('← Zorluğu değiştir'));
    await tester.pumpAndSettle();

    expect(find.text('1 · ZORLUK SEÇ'), findsOneWidget);
    await ekraniKapat(tester);
  });

  testWidgets('yarım kalan Izgara varsa kutucukta "Devam et" yazar ve seçim sorulmadan tahta açılır', (tester) async {
    final depo = SahteOyunDeposu()..oyun = {'id': 'izgara-1', 'soru_verisi': ornekTahta};
    await anaMenuyuAc(
      tester,
      bugunkuIzgara: (zorluk: IzgaraZorlugu.orta, bitti: false),
      ekOverridelar: [oyunDeposuProvider.overrideWithValue(depo)],
    );

    expect(find.text('Devam et'), findsOneWidget);

    await tester.tap(find.text('IZGARA'));
    await tester.pumpAndSettle();

    // Seçim açılmadı, doğrudan orta tahta açıldı
    expect(find.text('1 · ZORLUK SEÇ'), findsNothing);
    expect(find.byType(IzgaraScreen), findsOneWidget);
    expect(find.text('ORTA'), findsOneWidget);
    await ekraniKapat(tester);
  });

  testWidgets('bugün Izgara bitmişse seçim açılmaz, oynanan tahtanın sonucu açılır', (tester) async {
    final depo = SahteOyunDeposu()
      ..oyun = {'id': 'izgara-1', 'soru_verisi': ornekTahta}
      ..kayit = {'skor': 4, 'durum': 'tamamlandi'};
    await anaMenuyuAc(
      tester,
      oynananlar: {'izgara_zor': 4},
      bugunkuIzgara: (zorluk: IzgaraZorlugu.zor, bitti: true),
      ekOverridelar: [oyunDeposuProvider.overrideWithValue(depo)],
    );

    await tester.tap(find.text('IZGARA'));
    await tester.pumpAndSettle();

    expect(find.text('1 · ZORLUK SEÇ'), findsNothing);
    expect(tester.widget<IzgaraScreen>(find.byType(IzgaraScreen)).zorluk, IzgaraZorlugu.zor);
    expect(depo.kayitAcSayisi, 0);
    await ekraniKapat(tester);
  });

  testWidgets('tüm oyunlar oynandıysa hepsinin bittiği yazar', (tester) async {
    await anaMenuyuAc(tester, oynananlar: {
      'kesisim_kolay': 6,
      'bonservis_zor': 3,
      'izgara_orta': 4,
      'bingo': 12,
    });

    expect(find.text('Hepsi bitti'), findsOneWidget);
    expect(find.text('Oyna'), findsNothing);
    await ekraniKapat(tester);
  });

  testWidgets('Bingo\'ya dokununca zorluk sorulmaz, 30 saniyesiz süre seçilir ve kart açılır', (tester) async {
    await anaMenuyuAc(tester, ekOverridelar: [oyunDeposuProvider.overrideWithValue(SahteOyunDeposu())]);

    expect(find.text('YAKINDA'), findsNothing);

    await tester.tap(find.text('BİNGO'));
    await tester.pumpAndSettle();
    await kurallariGec(tester);
    expect(find.text('1 · ZORLUK SEÇ'), findsNothing);
    expect(find.text('∞'), findsOneWidget);
    expect(find.text('30'), findsNothing);
    expect(find.text('60'), findsOneWidget);
    expect(find.text('90'), findsOneWidget);

    await tester.tap(find.text('60'));
    await tester.pump();
    await tester.tap(find.text('60 SN BAŞLA'));
    await tester.pumpAndSettle();

    final ekran = tester.widget<BingoScreen>(find.byType(BingoScreen));
    expect(ekran.oyunTipi, 'bingo');
    expect(ekran.sure, 60);
    await ekraniKapat(tester);
  });

  testWidgets('oyuna ilk dokunuşta önce kurallar ve puanlama gösterilir, kurallara geri dönülebilir', (tester) async {
    await anaMenuyuAc(tester);

    await tester.tap(find.text('KESİŞİM'));
    await tester.pumpAndSettle();

    expect(find.text('NASIL OYNANIR'), findsOneWidget);
    expect(find.textContaining('5 soru var'), findsOneWidget);
    expect(find.text('Her doğru cevap 2 puan. En fazla 10 puan.'), findsOneWidget);
    expect(find.text('1 · ZORLUK SEÇ'), findsNothing);

    await tester.tap(find.text('ANLADIM · ZORLUK SEÇ'));
    await tester.pumpAndSettle();
    expect(find.text('1 · ZORLUK SEÇ'), findsOneWidget);

    await tester.tap(find.text('← Kurallara dön'));
    await tester.pumpAndSettle();
    expect(find.text('NASIL OYNANIR'), findsOneWidget);
    await ekraniKapat(tester);
  });

  testWidgets("her oyunun önizlemesinde kendi kuralları var, Bingo'da süre seçimine geçilir", (tester) async {
    await anaMenuyuAc(tester);

    for (final (oyun, puan) in [
      ('BONSERVİS', 'Her doğru tahmin 2 puan. En fazla 10 puan.'),
      ('IZGARA', 'Her dolu kutu 1 puan. En fazla 9 puan.'),
      ('BİNGO', 'Her dolu kutu 1 puan. En fazla 12 puan.'),
    ]) {
      await tester.tap(find.text(oyun).first);
      await tester.pumpAndSettle();
      expect(find.text('NASIL OYNANIR'), findsOneWidget);
      expect(find.text(puan), findsOneWidget);
      if (oyun == 'BİNGO') {
        await tester.tap(find.text('ANLADIM · SÜRE SEÇ'));
        await tester.pumpAndSettle();
        expect(find.text('SÜRE SEÇ'), findsWidgets);
      }
      Navigator.of(tester.element(find.byType(ZorlukSureSecimSayfasi))).pop();
      await tester.pumpAndSettle();
    }
    await ekraniKapat(tester);
  });

  testWidgets('çıkış onay sorar, vazgeçince oturum açık kalır', (tester) async {
    await anaMenuyuAc(tester);

    await tester.tap(find.byTooltip('Hesap'));
    await tester.pumpAndSettle();
    expect(find.text('test@ornek.com'), findsOneWidget);

    await tester.tap(find.text('Çıkış yap'));
    await tester.pumpAndSettle();
    expect(find.text('Çıkış yapılsın mı?'), findsOneWidget);

    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(find.text('Çıkış yapılsın mı?'), findsNothing);
    expect(find.text('Merhaba, Celal'), findsOneWidget);
    await ekraniKapat(tester);
  });
}
