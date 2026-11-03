import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/izgara.dart';
import 'package:mobile/providers/hub_provider.dart';
import 'package:mobile/screens/home_screen.dart';
import 'package:mobile/screens/izgara_screen.dart';
import 'package:mobile/services/oyun_deposu.dart';
import 'package:mobile/theme/tema.dart';

import 'izgara_test.dart' show ornekTahta;
import 'yardimcilar/sahte_oyun_deposu.dart';

Future<void> anaMenuyuAc(
  WidgetTester tester, {
  Map<String, int> oynananlar = const {},
  IzgaraZorlugu? devamEdenIzgara,
  List<Override> ekOverridelar = const [],
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      kullaniciProvider.overrideWithValue(const KullaniciBilgisi(ad: 'Celal Test', eposta: 'test@ornek.com')),
      bugunOynananlarProvider.overrideWith((ref) async => oynananlar),
      devamEdenIzgaraProvider.overrideWith((ref) async => devamEdenIzgara),
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

    // Kesişim, Bonservis ve Izgara'nın üç zorluğu: 5 günlük oyun
    expect(find.text('1/5 oyun tamamlandı'), findsOneWidget);
    expect(find.text('6/10'), findsOneWidget);
    expect(find.text('Oyna'), findsNWidgets(2)); // Bonservis ve Izgara henüz oynanmadı
    await ekraniKapat(tester);
  });

  testWidgets('Izgara kartında bitirilen zorluk sayısı yazar', (tester) async {
    await anaMenuyuAc(tester, oynananlar: {'izgara_kolay': 7});

    expect(find.text('1/3 bitti'), findsOneWidget);
    expect(find.text('Oyna'), findsNWidgets(3));
    await ekraniKapat(tester);
  });

  testWidgets('Izgara kartına dokununca zorluk seçimi açılır', (tester) async {
    await anaMenuyuAc(tester, oynananlar: {'izgara_orta': 5});

    await tester.tap(find.text('Izgara'));
    await tester.pumpAndSettle();

    expect(find.text('KOLAY'), findsOneWidget);
    expect(find.text('ORTA'), findsOneWidget);
    expect(find.text('ZOR'), findsOneWidget);
    expect(find.text('5/9'), findsOneWidget);
    await ekraniKapat(tester);
  });

  testWidgets('yarım kalan Izgara varsa kartta "Devam et" yazar ve zorluk sorulmadan tahta açılır', (tester) async {
    final depo = SahteOyunDeposu()..oyun = {'id': 'izgara-1', 'soru_verisi': ornekTahta};
    await anaMenuyuAc(
      tester,
      devamEdenIzgara: IzgaraZorlugu.orta,
      ekOverridelar: [oyunDeposuProvider.overrideWithValue(depo)],
    );

    expect(find.text('Devam et'), findsOneWidget);

    await tester.tap(find.text('Izgara'));
    await tester.pumpAndSettle();

    // Zorluk seçimi açılmadı, doğrudan orta tahta açıldı
    expect(find.text('Her zorluk ayrı bir tahta, her biri günde bir kez oynanır. 9 tahmin hakkın var.'), findsNothing);
    expect(find.byType(IzgaraScreen), findsOneWidget);
    expect(find.text('ORTA'), findsOneWidget);
    await ekraniKapat(tester);
  });

  testWidgets('yarım kalan Izgara yoksa zorluk seçimi açılır', (tester) async {
    await anaMenuyuAc(tester);

    await tester.tap(find.text('Izgara'));
    await tester.pumpAndSettle();

    expect(find.byType(IzgaraScreen), findsNothing);
    expect(find.text('KOLAY'), findsOneWidget);
    await ekraniKapat(tester);
  });

  testWidgets('zorluk seçiminde süre seçilir ve tahta o süreyle açılır', (tester) async {
    final depo = SahteOyunDeposu()..oyun = {'id': 'izgara-1', 'soru_verisi': ornekTahta};
    await anaMenuyuAc(tester, ekOverridelar: [oyunDeposuProvider.overrideWithValue(depo)]);

    await tester.tap(find.text('Izgara'));
    await tester.pumpAndSettle();
    expect(find.text('Süre yok'), findsOneWidget);

    await tester.tap(find.text('60 sn'));
    await tester.pump();
    await tester.tap(find.text('KOLAY'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byWidgetPredicate((w) => w is IzgaraScreen && w.zorluk == IzgaraZorlugu.kolay && w.sure == 60), findsOneWidget);
    expect(depo.sureBaslatmaIstekleri, [60]);
    await ekraniKapat(tester);
  });

  testWidgets('tüm oyunlar oynandıysa hepsinin bittiği yazar', (tester) async {
    await anaMenuyuAc(tester, oynananlar: {
      'kesisim': 6,
      'bonservis': 3,
      'izgara_kolay': 9,
      'izgara_orta': 4,
      'izgara_zor': 2,
    });

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
