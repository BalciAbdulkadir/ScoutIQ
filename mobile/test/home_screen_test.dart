import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/izgara.dart';
import 'package:mobile/models/oyun_modu.dart';
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

// Günlük şerit her saniye güncellenen bir zamanlayıcı kullanır: test bitmeden ekranı kapatıyoruz
Future<void> ekraniKapat(WidgetTester tester) => tester.pumpWidget(const SizedBox());

void main() {
  testWidgets('kullanıcıyı ilk adıyla karşılar', (tester) async {
    await anaMenuyuAc(tester);

    expect(find.text('Merhaba, Celal'), findsOneWidget);
    await ekraniKapat(tester);
  });

  testWidgets('günlük ilerleme bitirilen oyunları sayar, biten kutucukta skor yazar', (tester) async {
    await anaMenuyuAc(tester, oynananlar: {'kesisim': 6});

    // Kesişim, Bonservis ve Izgara: 3 günlük oyun (Izgara'nın zorlukları tek oyun sayılır)
    expect(find.text('1 / 3'), findsOneWidget);
    expect(find.text('6/10'), findsOneWidget);
    expect(find.text('Oyna'), findsNWidgets(2)); // Bonservis ve Izgara henüz oynanmadı
    await ekraniKapat(tester);
  });

  testWidgets('oyunlar kategorisiz tek ızgarada, zorluklu oyunda K O Z, diğerlerinde tek mod yazar', (tester) async {
    await anaMenuyuAc(tester);

    expect(find.text('KESİŞİM'), findsOneWidget);
    expect(find.text('BONSERVİS'), findsOneWidget);
    expect(find.text('IZGARA'), findsOneWidget);
    expect(find.text('K'), findsOneWidget);
    expect(find.text('O'), findsOneWidget);
    expect(find.text('Z'), findsOneWidget);
    expect(find.text('TEK MOD'), findsNWidgets(2));
    await ekraniKapat(tester);
  });

  testWidgets('Izgara\'da bir zorluk bitince kutucuk o zorluk ve skorla kapanır', (tester) async {
    await anaMenuyuAc(tester, oynananlar: {'izgara_kolay': 7});

    expect(find.text('7/9'), findsOneWidget);
    expect(find.text('KOLAY'), findsOneWidget);
    expect(find.text('1 / 3'), findsOneWidget);
    expect(find.text('Oyna'), findsNWidgets(2));
    await ekraniKapat(tester);
  });

  testWidgets('Izgara\'ya dokununca önce zorluk, sonra süre seçilir ve tahta o süreyle açılır', (tester) async {
    final depo = SahteOyunDeposu()..oyun = {'id': 'izgara-1', 'soru_verisi': ornekTahta};
    await anaMenuyuAc(tester, ekOverridelar: [oyunDeposuProvider.overrideWithValue(depo)]);

    await tester.tap(find.text('IZGARA'));
    await tester.pumpAndSettle();

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
    expect(ekran.sure, OyunSuresi.saniye60);
    expect(find.text('1:00'), findsOneWidget);
    await ekraniKapat(tester);
  });

  testWidgets('zorluk seçiminden geri dönülebilir', (tester) async {
    await anaMenuyuAc(tester);

    await tester.tap(find.text('IZGARA'));
    await tester.pumpAndSettle();
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
      devamEdenIzgara: IzgaraZorlugu.orta,
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
      ekOverridelar: [oyunDeposuProvider.overrideWithValue(depo)],
    );

    await tester.tap(find.text('IZGARA'));
    await tester.pumpAndSettle();

    expect(find.text('1 · ZORLUK SEÇ'), findsNothing);
    expect(tester.widget<IzgaraScreen>(find.byType(IzgaraScreen)).zorluk, IzgaraZorlugu.zor);
    await ekraniKapat(tester);
  });

  testWidgets('tüm oyunlar oynandıysa hepsinin bittiği yazar', (tester) async {
    await anaMenuyuAc(tester, oynananlar: {
      'kesisim': 6,
      'bonservis': 3,
      'izgara_orta': 4,
    });

    expect(find.text('Hepsi bitti'), findsOneWidget);
    expect(find.text('Oyna'), findsNothing);
    await ekraniKapat(tester);
  });

  testWidgets('yakındaki oyunlar ızgaranın sonunda dokunulamaz kutucuk olarak durur', (tester) async {
    await anaMenuyuAc(tester);

    expect(find.text('YAKINDA'), findsOneWidget);
    expect(find.text('BİNGO'), findsOneWidget);
    expect(find.ancestor(of: find.text('BİNGO'), matching: find.byType(InkWell)), findsNothing);
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
