import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/oyuncu_oneri.dart';
import 'package:mobile/screens/game_screen.dart';
import 'package:mobile/widgets/kulup_logosu.dart';
import 'package:mobile/widgets/oyun_ortak.dart';
import 'package:mobile/services/oyun_deposu.dart';

import 'yardimcilar/sahte_oyun_deposu.dart';

// Arama, yazmanın bitmesini en fazla bu kadar bekler (oyuncu_arama.dart'taki zamanlayıcı)
const aramaBeklemesi = Duration(milliseconds: 300);

Future<SahteOyunDeposu> ekraniAc(WidgetTester tester, [void Function(SahteOyunDeposu)? ayarla, int? sure]) async {
  final depo = SahteOyunDeposu();
  ayarla?.call(depo);

  await tester.pumpWidget(ProviderScope(
    overrides: [oyunDeposuProvider.overrideWithValue(depo)],
    child: MaterialApp(home: GameScreen(oyunTipi: 'kesisim_kolay', sure: sure)),
  ));
  await tester.pumpAndSettle();
  return depo;
}

Future<void> yaz(WidgetTester tester, String metin) async {
  await tester.enterText(find.byType(TextField), metin);
  await tester.pump(aramaBeklemesi);
  await tester.pump();
}

final gonderButonu = find.widgetWithText(FilledButton, 'GÖNDER');

// Seçili oyuncuyu gönderir ve alanın kısa geri bildirimi (yeşil / üstü çizili isim) bitene kadar bekler
Future<void> gonder(WidgetTester tester) async {
  await tester.tap(gonderButonu);
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('soru, kulüp isimleri ve zorluk etiketiyle gösterilir', (tester) async {
    await ekraniAc(tester);

    expect(find.text('Soru 1/5'), findsOneWidget);
    expect(find.text('Kulüp A0'), findsOneWidget);
    expect(find.text('Kulüp B0'), findsOneWidget);
    expect(find.text('KOLAY'), findsOneWidget);
  });

  testWidgets('etiket sorunun kademesini değil oynanan modu gösterir', (tester) async {
    final depo = SahteOyunDeposu();
    // Zor modun ilk sorusu ünlü kademesinden: soru verisinde 'kolay' yazar
    (depo.oyun!['soru_verisi'] as List)[0]['zorluk'] = 'kolay';

    await tester.pumpWidget(ProviderScope(
      overrides: [oyunDeposuProvider.overrideWithValue(depo)],
      child: const MaterialApp(home: GameScreen(oyunTipi: 'kesisim_zor')),
    ));
    await tester.pumpAndSettle();

    expect(find.text('ZOR'), findsOneWidget);
    expect(find.text('KOLAY'), findsNothing);
  });

  testWidgets('logosu olan kulübün logosu, olmayanın kalkan ikonu görünür', (tester) async {
    await ekraniAc(tester, (d) {
      final sorular = d.oyun!['soru_verisi'] as List;
      sorular[0] = {'kulup_a': 'Galatasaray', 'kulup_b': 'Parma', 'kulup_a_logo': 'https://logo.test/141.png', 'zorluk': 'kolay'};
    });

    // Logolar soldan sağa kulüp sırasıyla: önce Galatasaray, sonra Parma
    final logolar = find.byType(KulupLogosu);
    expect(logolar, findsNWidgets(2));

    final logo = tester.widget<Image>(find.descendant(of: logolar.at(0), matching: find.byType(Image)));
    expect((logo.image as ResizeImage).imageProvider, isA<NetworkImage>());
    expect(find.descendant(of: logolar.at(1), matching: find.byType(Image)), findsNothing);
    expect(find.descendant(of: logolar.at(1), matching: find.byIcon(Icons.shield_outlined)), findsOneWidget);
  });

  testWidgets('tek harfle arama yapılmaz, iki harften sonra öneri listesi çıkar', (tester) async {
    final depo = await ekraniAc(tester);

    await yaz(tester, 'a');
    expect(depo.arananlar, isEmpty);
    expect(find.text('Arda Güler'), findsNothing);

    await yaz(tester, 'ar');
    expect(depo.arananlar, ['ar']);
    expect(find.text('Arda Güler'), findsOneWidget);
    expect(find.text('Mesut Özil'), findsOneWidget);
  });

  testWidgets('öneri listesinde fotoğrafı olan oyuncunun fotoğrafı, olmayanın baş harfleri görünür', (tester) async {
    await ekraniAc(tester, (d) => d.oneriler = const [
          OyuncuOneri(id: 'o-1', isim: 'Arda Güler', fotoUrl: 'https://foto.test/arda.jpg'),
          OyuncuOneri(id: 'o-2', isim: 'Mesut Özil'),
        ]);

    await yaz(tester, 'ar');

    final fotograflar = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(fotograflar, hasLength(1));
    expect((fotograflar.single.image as ResizeImage).imageProvider, isA<NetworkImage>());
    expect(find.text('MÖ'), findsOneWidget);
  });

  testWidgets('sonuç yoksa "bulunamadı" yazar', (tester) async {
    await ekraniAc(tester, (d) => d.oneriler = []);

    await yaz(tester, 'xqz');

    expect(find.textContaining('Bu isimde kimse yok.'), findsOneWidget);
  });

  testWidgets('listeden seçilmeden gönder butonu görünmez', (tester) async {
    await ekraniAc(tester);

    await yaz(tester, 'Arda Güler');

    expect(gonderButonu, findsNothing);
  });

  testWidgets('yazma alanında klavye düzeltmesi ve kelime önerileri kapalıdır', (tester) async {
    await ekraniAc(tester);

    final alan = tester.widget<TextField>(find.byType(TextField));
    expect(alan.autocorrect, isFalse);
    expect(alan.enableSuggestions, isFalse);
  });

  testWidgets('klavyedeki tuş listedeki ilk oyuncuyu seçer, cevabı göndermez', (tester) async {
    final depo = await ekraniAc(tester);

    await yaz(tester, 'ar');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(find.byType(TextField), findsNothing);
    expect(find.text('Arda Güler'), findsOneWidget);
    expect(gonderButonu, findsOneWidget);
    expect(depo.cevapKontrolSayisi, 0);
  });

  testWidgets('liste boşken klavyedeki tuşa basılırsa alanın altında uyarı çıkar', (tester) async {
    final depo = await ekraniAc(tester, (d) => d.oneriler = []);

    await yaz(tester, 'xqz');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(find.text('Listeden bir oyuncu seç.'), findsOneWidget);
    expect(depo.cevapKontrolSayisi, 0);
  });

  testWidgets('listede yazılan harfler vurgulanır', (tester) async {
    await ekraniAc(tester);

    await yaz(tester, 'ar');

    final satir = tester.widget<Text>(find.text('Arda Güler'));
    final parcalar = (satir.textSpan! as TextSpan).children!.cast<TextSpan>().map((p) => p.text).toList();
    expect(parcalar, ['', 'Ar', 'da Güler']);
  });

  testWidgets('listeden seçilen oyuncu gönderilir ve sonuç gösterilir', (tester) async {
    final depo = await ekraniAc(tester);

    await yaz(tester, 'ar');
    await tester.tap(find.text('Arda Güler'));
    await tester.pump();

    // Seçilen oyuncu etikete dönüşür, Gönder butonu çıkar
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Arda Güler'), findsOneWidget);
    expect(tester.widget<FilledButton>(gonderButonu).onPressed, isNotNull);

    await gonder(tester);

    expect(depo.cevapKontrolSayisi, 1);
    expect(find.text('Doğru'), findsOneWidget);
    expect(find.textContaining('Arda Güler'), findsOneWidget);
    expect(find.text('Soru 2/5'), findsOneWidget);
  });

  testWidgets('seçim × ile kaldırılınca yazma alanı geri gelir', (tester) async {
    await ekraniAc(tester);

    await yaz(tester, 'ar');
    await tester.tap(find.text('Arda Güler'));
    await tester.pump();
    expect(gonderButonu, findsOneWidget);

    await tester.tap(find.byTooltip('Seçimi kaldır'));
    await tester.pump();

    expect(find.byType(TextField), findsOneWidget);
    expect(gonderButonu, findsNothing);
  });

  testWidgets('yanlış cevapta isim kısa bir an kalır, sonra alan boşalır', (tester) async {
    final depo = await ekraniAc(tester);

    await yaz(tester, 'ar');
    await tester.tap(find.text('Mesut Özil'));
    await tester.pump();
    await tester.tap(gonderButonu);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(depo.cevapKontrolSayisi, 1);
    expect(find.byType(TextField), findsNothing);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Yanlış'), findsOneWidget);
  });

  testWidgets('bitiş özetinde yanlış bilinen sorunun doğru cevabı gösterilir', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await ekraniAc(tester);

    // 2. soru yanlış (Mesut Özil), diğerleri doğru (Arda Güler)
    for (var i = 0; i < 5; i++) {
      await yaz(tester, 'ar');
      await tester.tap(find.text(i == 1 ? 'Mesut Özil' : 'Arda Güler'));
      await tester.pump();
      await gonder(tester);
    }

    expect(find.text('ÖZET'), findsOneWidget);
    expect(find.text('Cevabın: Mesut Özil'), findsOneWidget);
    expect(find.text('Doğru cevap: Doğru Oyuncu 1'), findsOneWidget);
    // Doğru bilinen sorularda doğru cevap tekrar yazılmaz
    expect(find.textContaining('Doğru cevap:'), findsOneWidget);
  });

  testWidgets('bugün oynanmış oyun açılmaz', (tester) async {
    await ekraniAc(tester, (d) => d.kayit = {'skor': 8, 'durum': 'tamamlandi'});

    expect(find.text('Bugünkü oyununu oynadın'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('yarıda bırakılan oyun kaldığı sorudan devam eder', (tester) async {
    await ekraniAc(tester, (d) {
      d.kayit = {'skor': 2, 'durum': 'basladi'};
      d.ilerleme = [
        {'dogru': true, 'cevap': 'Arda Güler'},
      ];
    });

    expect(find.text('Soru 2/5'), findsOneWidget);
    expect(find.text('1 doğru'), findsOneWidget);
    expect(find.text('Kulüp A1'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('süreli oyunda sayaç görünür, süresizde görünmez', (tester) async {
    await ekraniAc(tester, null, 30);
    expect(find.byType(SureSayaci), findsOneWidget);
    expect(find.text('0:30'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await ekraniAc(tester);
    expect(find.byType(SureSayaci), findsNothing);
  });
}
