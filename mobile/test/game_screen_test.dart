import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/screens/game_screen.dart';
import 'package:mobile/services/oyun_deposu.dart';

import 'yardimcilar/sahte_oyun_deposu.dart';

// Arama, yazmanın bitmesini bu kadar bekler (game_screen.dart'taki zamanlayıcı)
const aramaBeklemesi = Duration(milliseconds: 300);

Future<SahteOyunDeposu> ekraniAc(WidgetTester tester, [void Function(SahteOyunDeposu)? ayarla]) async {
  final depo = SahteOyunDeposu();
  ayarla?.call(depo);

  await tester.pumpWidget(ProviderScope(
    overrides: [oyunDeposuProvider.overrideWithValue(depo)],
    child: const MaterialApp(home: GameScreen()),
  ));
  await tester.pumpAndSettle();
  return depo;
}

Future<void> yaz(WidgetTester tester, String metin) async {
  await tester.enterText(find.byType(TextField), metin);
  await tester.pump(aramaBeklemesi);
  await tester.pump();
}

IconButton gonderButonu(WidgetTester tester) =>
    tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send));

void main() {
  testWidgets('soru, kulüp isimleri ve zorluk etiketiyle gösterilir', (tester) async {
    await ekraniAc(tester);

    expect(find.text('Soru 1/5'), findsOneWidget);
    expect(find.text('Kulüp A0'), findsOneWidget);
    expect(find.text('Kulüp B0'), findsOneWidget);
    expect(find.text('KOLAY'), findsOneWidget);
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

  testWidgets('sonuç yoksa "bulunamadı" yazar', (tester) async {
    await ekraniAc(tester, (d) => d.oneriler = []);

    await yaz(tester, 'xqz');

    expect(find.text('Bu isimde oyuncu bulunamadı.'), findsOneWidget);
  });

  testWidgets('listeden seçilmeden gönder butonu kapalıdır', (tester) async {
    await ekraniAc(tester);

    await yaz(tester, 'Arda Güler');

    expect(gonderButonu(tester).onPressed, isNull);
  });

  testWidgets('listeden seçmeden klavyeden gönderilirse uyarı çıkar, cevap gönderilmez', (tester) async {
    final depo = await ekraniAc(tester);

    await yaz(tester, 'Arda Güler');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();

    expect(find.text('Cevabını listeden seçmelisin.'), findsOneWidget);
    expect(depo.cevapKontrolSayisi, 0);
  });

  testWidgets('listeden seçilen oyuncu gönderilir ve sonuç gösterilir', (tester) async {
    final depo = await ekraniAc(tester);

    await yaz(tester, 'ar');
    await tester.tap(find.text('Arda Güler'));
    await tester.pump();

    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(gonderButonu(tester).onPressed, isNotNull);

    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(depo.cevapKontrolSayisi, 1);
    expect(find.text('Doğru'), findsOneWidget);
    expect(find.textContaining('Arda Güler'), findsOneWidget);
    expect(find.text('Soru 2/5'), findsOneWidget);
  });

  testWidgets('seçimden sonra isim değiştirilirse seçim iptal olur', (tester) async {
    await ekraniAc(tester);

    await yaz(tester, 'ar');
    await tester.tap(find.text('Arda Güler'));
    await tester.pump();
    expect(gonderButonu(tester).onPressed, isNotNull);

    await yaz(tester, 'Arda Güle');

    expect(find.byIcon(Icons.check_circle), findsNothing);
    expect(gonderButonu(tester).onPressed, isNull);
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
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();
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

  testWidgets('yarıda bırakılan oyun açılmaz', (tester) async {
    await ekraniAc(tester, (d) => d.kayit = {'skor': 2, 'durum': 'basladi'});

    expect(find.text('Bugünkü hakkını kullandın'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });
}
