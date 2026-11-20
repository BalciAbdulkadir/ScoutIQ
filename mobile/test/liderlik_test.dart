import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/puan.dart';
import 'package:mobile/screens/liderlik_screen.dart';
import 'package:mobile/services/analitik.dart';
import 'package:mobile/services/oyun_deposu.dart';
import 'package:mobile/theme/tema.dart';

import 'yardimcilar/sahte_analitik.dart';
import 'yardimcilar/sahte_oyun_deposu.dart';

LiderlikSatiri satir(int sira, String ad, int puan, {bool ben = false}) =>
    LiderlikSatiri(sira: sira, ad: ad, puan: puan, oyun: 3, ben: ben);

Future<(SahteOyunDeposu, SahteAnalitik)> siralamayiAc(
  WidgetTester tester, {
  LiderlikSonucu liderlik = const LiderlikSonucu(liste: []),
  Profil profil = const Profil(takmaAd: 'kanarya_10', varsayilan: false),
  bool hataVerir = false,
  Size ekran = const Size(1080, 2400),
}) async {
  tester.view.physicalSize = ekran;
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);

  final depo = SahteOyunDeposu()
    ..liderlik = liderlik
    ..profil = profil
    ..liderlikHataVerir = hataVerir;
  final analitik = SahteAnalitik();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      oyunDeposuProvider.overrideWithValue(depo),
      analitikProvider.overrideWithValue(analitik),
    ],
    child: MaterialApp(theme: uygulamaTemasi(), home: const LiderlikScreen()),
  ));
  await tester.pumpAndSettle();
  return (depo, analitik);
}

void main() {
  testWidgets('kimse yoksa boş tahta ve "tabloya giremedin" yazar', (tester) async {
    final (depo, analitik) = await siralamayiAc(tester);

    expect(find.text('Bugün tahta boş. İlk puanı sen yaz.'), findsOneWidget);
    expect(find.text('Bugün tabloya giremedin. Süreli bir oyunu bitir, tabloya gir.'), findsOneWidget);
    expect(depo.liderlikIstekleri, [(LiderlikDonemi.gun, null)]);
    expect(analitik.son('liderlik_acildi'), {'donem': 'gun'});
  });

  testWidgets('üçten az kişi varsa kürsü olmadan liste', (tester) async {
    await siralamayiAc(
      tester,
      liderlik: LiderlikSonucu(liste: [satir(1, 'tribun_kartali', 316), satir(2, 'kanarya_10', 110, ben: true)],
          ben: satir(2, 'kanarya_10', 110, ben: true)),
    );

    expect(find.byKey(const ValueKey('kursu')), findsNothing);
    expect(find.text('tribun_kartali'), findsOneWidget);
    expect(find.text('kanarya_10 (sen)'), findsOneWidget);
    // Kullanıcı listede: altta ayrıca satırı yok
    expect(find.textContaining('Sen ·'), findsNothing);
  });

  testWidgets('ilk üç kürsüde; kullanıcı ilk 50\'de değilse kendi satırı altta durur', (tester) async {
    await siralamayiAc(
      tester,
      liderlik: LiderlikSonucu(
        liste: [for (var i = 1; i <= 50; i++) satir(i, 'oyuncu_$i', 2000 - i * 10)],
        ben: satir(214, 'kanarya_10', 640, ben: true),
        katilimci: 600,
      ),
    );

    expect(find.byKey(const ValueKey('kursu')), findsOneWidget);
    expect(find.text('oyuncu_1'), findsOneWidget);
    expect(find.text('1.990'), findsOneWidget); // binlik ayırıcı
    expect(find.text('Sen · 214. · 640 puan'), findsOneWidget);
  });

  testWidgets('dönem ve oyun değişince tablo yeniden istenir', (tester) async {
    final (depo, _) = await siralamayiAc(tester);

    await tester.tap(find.text('BU HAFTA'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Izgara'));
    await tester.tap(find.text('Izgara'));
    await tester.pumpAndSettle();

    expect(depo.liderlikIstekleri, [
      (LiderlikDonemi.gun, null),
      (LiderlikDonemi.hafta, null),
      (LiderlikDonemi.hafta, 'izgara'),
    ]);
    expect(find.text('Bu hafta tahta boş. İlk puanı sen yaz.'), findsOneWidget);
  });

  testWidgets('takma ad seçilmediyse şerit çıkar, ad kaydedilince kaybolur', (tester) async {
    final (depo, _) = await siralamayiAc(tester, profil: const Profil(takmaAd: 'Oyuncu 3FA9', varsayilan: true));

    expect(find.text("Tabloda 'Oyuncu 3FA9' görünüyorsun."), findsOneWidget);
    await tester.tap(find.text('Takma ad seç →'));
    await tester.pumpAndSettle();
    expect(find.text('TAKMA ADIN'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'tribun_kartali');
    await tester.tap(find.text('KAYDET'));
    await tester.pumpAndSettle();
    // 7 gün uyarısı
    expect(find.text('Takma adını 7 gün boyunca değiştiremezsin. Devam?'), findsOneWidget);
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();

    expect(depo.kaydedilenTakmaAdlar, ['tribun_kartali']);
    expect(find.text('TAKMA ADIN'), findsNothing);
    expect(find.textContaining('görünüyorsun'), findsNothing);
  });

  testWidgets('sunucu takma adı reddederse sebep alanın altında yazar', (tester) async {
    final (depo, _) = await siralamayiAc(tester, profil: const Profil(takmaAd: 'Oyuncu 3FA9', varsayilan: true));
    depo.takmaAdHatasi = 'Bu takma ad alınmış';

    await tester.tap(find.text('Takma ad seç →'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'kanarya');
    await tester.tap(find.text('KAYDET'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();

    expect(find.text('Bu takma ad alınmış'), findsOneWidget);
    expect(find.text('TAKMA ADIN'), findsOneWidget);
  });

  testWidgets('tablo yüklenemezse tekrar denenebilir', (tester) async {
    final (depo, _) = await siralamayiAc(tester, hataVerir: true);

    expect(find.text('Sıralama yüklenemedi.'), findsOneWidget);
    depo.liderlikHataVerir = false;
    await tester.tap(find.text('Tekrar dene'));
    await tester.pumpAndSettle();
    expect(find.text('Bugün tahta boş. İlk puanı sen yaz.'), findsOneWidget);
  });

  testWidgets('küçük ekranda taşma olmaz', (tester) async {
    await siralamayiAc(
      tester,
      ekran: const Size(840, 1491), // 320x568
      liderlik: LiderlikSonucu(
        liste: [for (var i = 1; i <= 50; i++) satir(i, 'cok_uzun_takma_ad$i', 12000 - i)],
        ben: satir(214, 'kanarya_10', 640, ben: true),
      ),
      profil: const Profil(takmaAd: 'Oyuncu 3FA9', varsayilan: true),
    );
    expect(tester.takeException(), isNull);
  });
}
