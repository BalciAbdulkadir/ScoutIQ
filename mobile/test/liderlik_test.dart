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

LiderlikSatiri satir(int sira, String ad, int puan, {bool ben = false, String? kimlik, bool varsayilan = false}) =>
    LiderlikSatiri(sira: sira, ad: ad, puan: puan, oyun: 3, ben: ben, kullaniciId: kimlik, varsayilan: varsayilan);

// Takma ad bildirme testleri için: kürsüde üç kişi, listede kullanıcı, takma adlı biri ve varsayılan adlı biri
final bildirmeTablosu = LiderlikSonucu(liste: [
  satir(1, 'tribun_kartali', 400, kimlik: 'k1'),
  satir(2, 'sari_lacivert', 300, kimlik: 'k2'),
  satir(3, 'cimbom_1905', 200, kimlik: 'k3'),
  satir(4, 'kanarya_10', 150, ben: true, kimlik: 'ben'),
  satir(5, 'kotu_ad', 120, kimlik: 'k5'),
  satir(6, 'Oyuncu 3FA9', 100, kimlik: 'k6', varsayilan: true),
]);

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
  testWidgets('kimse yoksa boş tahta ve "puanlı oyun oynamadın" yazar', (tester) async {
    final (depo, analitik) = await siralamayiAc(tester);

    expect(find.text('Bugün tahta boş. İlk puanı sen yaz.'), findsOneWidget);
    expect(find.text('Bugün puanlı oyun oynamadın. Süreli bir oyun oyna, tabloya gir.'), findsOneWidget);
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

  group('takma ad bildirme', () {
    test('satırdaki kimlik ve varsayılan ad bayrağı okunur; eski sunucu kimlik göndermezse bildirilemez', () {
      final yeni = LiderlikSatiri.fromJson(
          {'sira': 1, 'ad': 'kotu_ad', 'puan': 10, 'oyun': 1, 'ben': false, 'kullanici_id': 'k5', 'varsayilan': false});
      expect(yeni.kullaniciId, 'k5');
      expect(yeni.bildirilebilir, isTrue);

      final varsayilan = LiderlikSatiri.fromJson(
          {'sira': 2, 'ad': 'Oyuncu 3FA9', 'puan': 5, 'oyun': 1, 'ben': false, 'kullanici_id': 'k6', 'varsayilan': true});
      expect(varsayilan.bildirilebilir, isFalse);

      final ben = LiderlikSatiri.fromJson(
          {'sira': 3, 'ad': 'kanarya_10', 'puan': 4, 'oyun': 1, 'ben': true, 'kullanici_id': 'ben'});
      expect(ben.bildirilebilir, isFalse);

      final eski = LiderlikSatiri.fromJson({'sira': 1, 'ad': 'kotu_ad', 'puan': 10, 'oyun': 1, 'ben': false});
      expect(eski.bildirilebilir, isFalse);
    });

    testWidgets('başkasının satırına uzun basınca onay sorulur, onaylanınca bildirilir', (tester) async {
      final (depo, _) = await siralamayiAc(tester, liderlik: bildirmeTablosu);

      await tester.longPress(find.text('kotu_ad'));
      await tester.pumpAndSettle();
      expect(find.text('Bu adı bildir'), findsOneWidget);
      expect(find.textContaining("'kotu_ad'"), findsOneWidget);

      await tester.tap(find.text('Bildir'));
      await tester.pumpAndSettle();

      expect(depo.bildirilenler, ['k5']);
      expect(find.text('Teşekkürler, inceleyeceğiz.'), findsOneWidget);
    });

    testWidgets('vazgeçilirse bildirim gitmez', (tester) async {
      final (depo, _) = await siralamayiAc(tester, liderlik: bildirmeTablosu);

      await tester.longPress(find.text('kotu_ad'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();

      expect(depo.bildirilenler, isEmpty);
      expect(find.text('Teşekkürler, inceleyeceğiz.'), findsNothing);
    });

    testWidgets('kürsüdeki kişi de bildirilebilir', (tester) async {
      final (depo, _) = await siralamayiAc(tester, liderlik: bildirmeTablosu);

      await tester.longPress(find.text('tribun_kartali'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bildir'));
      await tester.pumpAndSettle();

      expect(depo.bildirilenler, ['k1']);
    });

    testWidgets('kendi satırı ve sistemin ürettiği ad bildirilemez', (tester) async {
      final (depo, _) = await siralamayiAc(tester, liderlik: bildirmeTablosu);

      await tester.longPress(find.text('kanarya_10 (sen)'));
      await tester.pumpAndSettle();
      expect(find.text('Bu adı bildir'), findsNothing);

      await tester.longPress(find.text('Oyuncu 3FA9'));
      await tester.pumpAndSettle();
      expect(find.text('Bu adı bildir'), findsNothing);

      expect(depo.bildirilenler, isEmpty);
    });

    testWidgets('sunucu reddederse sebebi yazar (ör. yeterince gün oynamamış)', (tester) async {
      final (depo, _) = await siralamayiAc(tester, liderlik: bildirmeTablosu);
      depo.bildirmeReddi = bildirimHataMesaji('bildirim_icin_erken');

      await tester.longPress(find.text('kotu_ad'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bildir'));
      await tester.pumpAndSettle();

      expect(find.text('Ad bildirmek için en az 3 farklı gün oyun bitirmiş olman gerekir.'), findsOneWidget);
      expect(find.text('Teşekkürler, inceleyeceğiz.'), findsNothing);
    });

    test('profil sıfırlanma bilgisini okur; eski sunucu göndermezse sıfırlanmamış sayılır', () {
      final sifirlanmis = Profil.fromJson(
          {'takma_ad': 'Oyuncu 3FA9', 'varsayilan': true, 'degistirilebilir_tarih': null, 'sifirlandi': true});
      expect(sifirlanmis.sifirlandi, isTrue);
      expect(sifirlanmis.degistirilebilir(DateTime.now()), isTrue);

      final eski = Profil.fromJson({'takma_ad': 'kanarya_10', 'varsayilan': false, 'degistirilebilir_tarih': null});
      expect(eski.sifirlandi, isFalse);
    });

    test('sunucu ipuçları Türkçe mesaja çevrilir', () {
      expect(takmaAdHataMesaji('takma_ad_kilitli'), 'Takma adını değiştiremezsin');
      expect(takmaAdHataMesaji('takma_ad_sifirlanmis'), contains('bildirildiği için kullanılamaz'));
      expect(bildirimHataMesaji('varsayilan_ad'), 'Bu ad bildirilemez.');
      expect(bildirimHataMesaji('kendini_bildiremez'), 'Kendi adını bildiremezsin.');
      expect(bildirimHataMesaji(null), 'Bildirim gönderilemedi. Tekrar dene.');
    });

    testWidgets('bildirim gönderilemezse mesaj çıkar', (tester) async {
      final (depo, _) = await siralamayiAc(tester, liderlik: bildirmeTablosu);
      depo.bildirmeHataVerir = true;

      await tester.longPress(find.text('kotu_ad'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bildir'));
      await tester.pumpAndSettle();

      expect(find.text('Bildirim gönderilemedi. Tekrar dene.'), findsOneWidget);
      expect(find.text('Teşekkürler, inceleyeceğiz.'), findsNothing);
    });
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
