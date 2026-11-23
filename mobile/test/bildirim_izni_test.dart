import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/services/hatirlatma.dart';
import 'package:mobile/widgets/bildirim_izni_sayfasi.dart';

import 'home_screen_test.dart' show anaMenuyuAc, ekraniKapat;
import 'yardimcilar/sahte_hatirlatma.dart';

// Bildirim izni: sistemin penceresinden önce uygulamanın temalı sayfası (widgets/bildirim_izni_sayfasi.dart)
void main() {
  setUp(bildirimIzniBakildiSifirla);

  Future<SahteHatirlatma> ac(WidgetTester tester, {Map<String, int> oynananlar = const {'kesisim_orta': 6}, SahteHatirlatma? h}) async {
    final hatirlatma = h ?? SahteHatirlatma();
    await anaMenuyuAc(tester, oynananlar: oynananlar, ekOverridelar: [hatirlatmaProvider.overrideWithValue(hatirlatma)]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // sayfanın açılma animasyonu
    return hatirlatma;
  }

  testWidgets('bugün oyun bittiyse temalı sayfa açılır; "Bildirimleri aç" sistemin penceresini ister', (tester) async {
    final h = await ac(tester);

    expect(find.text('SERİNİ KAÇIRMA'), findsOneWidget);
    expect(find.text('Bugünün bulmacaları seni bekliyor 🔥'), findsOneWidget); // örnek bildirim
    expect(h.izinIstekSayisi, 0);

    await tester.tap(find.text('BİLDİRİMLERİ AÇ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(h.izinIstekSayisi, 1);
    expect(find.text('SERİNİ KAÇIRMA'), findsNothing);
    await ekraniKapat(tester);
  });

  testWidgets('"Şimdi değil" sistemin penceresini açmaz ve bir daha sormaz', (tester) async {
    final h = await ac(tester);

    await tester.tap(find.text('Şimdi değil'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(h.izinIstekSayisi, 0);
    expect(h.izinSorulduMu, isTrue);
    await ekraniKapat(tester);

    bildirimIzniBakildiSifirla(); // uygulama yeniden açıldı
    await ac(tester, h: h);
    expect(find.text('SERİNİ KAÇIRMA'), findsNothing);
    await ekraniKapat(tester);
  });

  testWidgets('bugün oyun bitmediyse sayfa açılmaz', (tester) async {
    final h = await ac(tester, oynananlar: const {});

    expect(find.text('SERİNİ KAÇIRMA'), findsNothing);
    expect(h.izinSorulduMu, isFalse);
    await ekraniKapat(tester);
  });

  testWidgets('telefon zaten izin veriyorsa sayfa açılmaz, sorulmuş sayılır', (tester) async {
    final h = await ac(tester, h: SahteHatirlatma()..izinVarMi = true);

    expect(find.text('SERİNİ KAÇIRMA'), findsNothing);
    expect(h.izinSorulduMu, isTrue);
    expect(h.izinIstekSayisi, 0);
    await ekraniKapat(tester);
  });

  testWidgets('hatırlatma kapalıysa ya da daha önce sorulduysa sayfa açılmaz', (tester) async {
    await ac(tester, h: SahteHatirlatma()..acik = false);
    expect(find.text('SERİNİ KAÇIRMA'), findsNothing);
    await ekraniKapat(tester);

    bildirimIzniBakildiSifirla();
    await ac(tester, h: SahteHatirlatma()..izinSorulduMu = true);
    expect(find.text('SERİNİ KAÇIRMA'), findsNothing);
    await ekraniKapat(tester);
  });

  testWidgets('küçük ekranda taşma olmaz', (tester) async {
    tester.view.physicalSize = const Size(640, 1136);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: BildirimIzniSayfasi())));
    expect(tester.takeException(), isNull);
  });
}
