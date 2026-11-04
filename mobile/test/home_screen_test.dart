import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/izgara.dart';
import 'package:mobile/providers/hub_provider.dart';
import 'package:mobile/screens/home_screen.dart';
import 'package:mobile/screens/izgara_screen.dart';
import 'package:mobile/screens/izgara_sure_screen.dart';
import 'package:mobile/services/oyun_deposu.dart';
import 'package:mobile/theme/tema.dart';

import 'izgara_test.dart' show ornekTahta;
import 'yardimcilar/sahte_oyun_deposu.dart';

Future<void> anaMenuyuAc(
  WidgetTester tester, {
  Map<String, int> oynananlar = const {},
  BugunkuIzgara? bugunkuIzgara,
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
      ...ekOverridelar,
    ],
    child: MaterialApp(theme: uygulamaTemasi(), home: const HomeScreen()),
  ));
  await tester.pump();
}

// Günlük kart her saniye güncellenen bir zamanlayıcı kullanır: test bitmeden ekranı kapatıyoruz
Future<void> ekraniKapat(WidgetTester tester) => tester.pumpWidget(const SizedBox());

void main() {
  testWidgets('kullanıcıyı ilk adıyla karşılar', (tester) async {
    await anaMenuyuAc(tester);

    expect(find.text('Merhaba, Celal'), findsOneWidget);
    await ekraniKapat(tester);
  });

  testWidgets('günlük ilerleme oynanan oyun sayısını gösterir', (tester) async {
    await anaMenuyuAc(tester, oynananlar: {'kesisim': 6});

    // Kesişim, Bonservis ve Izgara: 3 günlük oyun (Izgara'da günde tek zorluk oynanır)
    expect(find.text('1/3 oyun tamamlandı'), findsOneWidget);
    expect(find.text('6/10'), findsOneWidget);
    expect(find.text('Oyna'), findsNWidgets(2)); // Bonservis ve Izgara henüz oynanmadı
    await ekraniKapat(tester);
  });

  testWidgets('bir zorlukta Izgara bitince kartta o tahtanın skoru ve "Bitti" yazar', (tester) async {
    await anaMenuyuAc(
      tester,
      oynananlar: {'izgara_zor': 7},
      bugunkuIzgara: (zorluk: IzgaraZorlugu.zor, bitti: true),
    );

    expect(find.text('7/9'), findsOneWidget);
    expect(find.text('Oyna'), findsNWidgets(2)); // Kesişim ve Bonservis
    expect(find.text('1/3 oyun tamamlandı'), findsOneWidget);
    await ekraniKapat(tester);
  });

  testWidgets('Izgara kartına dokununca zorluk seçimi açılır', (tester) async {
    await anaMenuyuAc(tester);

    await tester.tap(find.text('Izgara'));
    await tester.pumpAndSettle();

    expect(find.text('KOLAY'), findsOneWidget);
    expect(find.text('ORTA'), findsOneWidget);
    expect(find.text('ZOR'), findsOneWidget);
    expect(find.text('Günde tek bir Izgara oynayabilirsin. Seçtiğin zorluk bugünün tahtası olur.'), findsOneWidget);
    // Süre zorluk seçiminde sorulmaz
    expect(find.text('Süre yok'), findsNothing);
    await ekraniKapat(tester);
  });

  testWidgets('yarım kalan Izgara varsa kartta "Devam et" yazar ve zorluk sorulmadan tahta açılır', (tester) async {
    final depo = SahteOyunDeposu()..oyun = {'id': 'izgara-1', 'soru_verisi': ornekTahta};
    await anaMenuyuAc(
      tester,
      bugunkuIzgara: (zorluk: IzgaraZorlugu.orta, bitti: false),
      ekOverridelar: [oyunDeposuProvider.overrideWithValue(depo)],
    );

    expect(find.text('Devam et'), findsOneWidget);

    await tester.tap(find.text('Izgara'));
    await tester.pumpAndSettle();

    expect(find.text('KOLAY'), findsNothing);
    expect(find.byType(IzgaraScreen), findsOneWidget);
    expect(find.text('ORTA'), findsOneWidget);
    await ekraniKapat(tester);
  });

  testWidgets('bugün bitirilmiş Izgara varsa başka zorluk seçtirilmez, o tahta sonucuyla açılır', (tester) async {
    final depo = SahteOyunDeposu()
      ..oyun = {'id': 'izgara-1', 'soru_verisi': ornekTahta}
      ..kayit = {'skor': 0, 'durum': 'tamamlandi'};
    await anaMenuyuAc(
      tester,
      oynananlar: {'izgara_zor': 0},
      bugunkuIzgara: (zorluk: IzgaraZorlugu.zor, bitti: true),
      ekOverridelar: [oyunDeposuProvider.overrideWithValue(depo)],
    );

    await tester.tap(find.text('Izgara'));
    await tester.pumpAndSettle();

    expect(find.text('KOLAY'), findsNothing);
    expect(find.byWidgetPredicate((w) => w is IzgaraScreen && w.zorluk == IzgaraZorlugu.zor), findsOneWidget);
    expect(find.text('Ana menüye dön'), findsOneWidget);
    expect(depo.kayitAcSayisi, 0);
    await ekraniKapat(tester);
  });

  testWidgets('zorluk seçilince süre ekranı açılır, seçilen süreyle tahta başlar', (tester) async {
    final depo = SahteOyunDeposu()..oyun = {'id': 'izgara-1', 'soru_verisi': ornekTahta};
    await anaMenuyuAc(tester, ekOverridelar: [oyunDeposuProvider.overrideWithValue(depo)]);

    await tester.tap(find.text('Izgara'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('KOLAY'));
    await tester.pumpAndSettle();

    expect(find.byType(IzgaraSureScreen), findsOneWidget);
    expect(find.text('Süreni seç'), findsOneWidget);
    expect(find.text('Süre yok'), findsOneWidget);
    expect(find.text('90 saniye'), findsOneWidget);

    await tester.tap(find.text('60 saniye'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byType(IzgaraSureScreen), findsNothing);
    expect(find.byWidgetPredicate((w) => w is IzgaraScreen && w.zorluk == IzgaraZorlugu.kolay && w.sure == 60), findsOneWidget);
    expect(depo.sureBaslatmaIstekleri, [60]);
    await ekraniKapat(tester);
  });

  testWidgets('süre ekranından geri dönülürse oyun başlamaz', (tester) async {
    final depo = SahteOyunDeposu()..oyun = {'id': 'izgara-1', 'soru_verisi': ornekTahta};
    await anaMenuyuAc(tester, ekOverridelar: [oyunDeposuProvider.overrideWithValue(depo)]);

    await tester.tap(find.text('Izgara'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ORTA'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byType(IzgaraSureScreen), findsNothing);
    expect(find.byType(IzgaraScreen), findsNothing);
    expect(depo.kayitAcSayisi, 0);
    await ekraniKapat(tester);
  });

  testWidgets('tüm oyunlar oynandıysa hepsinin bittiği yazar', (tester) async {
    await anaMenuyuAc(tester, oynananlar: {
      'kesisim': 6,
      'bonservis': 3,
      'izgara_orta': 4,
    }, bugunkuIzgara: (zorluk: IzgaraZorlugu.orta, bitti: true));

    expect(find.text('Tüm oyunlar tamamlandı'), findsOneWidget);
    expect(find.text('Oyna'), findsNothing);
    await ekraniKapat(tester);
  });

  testWidgets('yakında bölümünde planlanan modlar listelenir', (tester) async {
    await anaMenuyuAc(tester);

    expect(find.text('YAKINDA'), findsOneWidget);
    expect(find.text('Bingo'), findsOneWidget);
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
