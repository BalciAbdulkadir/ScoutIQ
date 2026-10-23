import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/oyun_modu.dart';
import 'package:mobile/widgets/oyun_karti.dart';

final kesisim = oyunModlari.firstWhere((m) => m.tip == 'kesisim');
final bonservis = oyunModlari.firstWhere((m) => m.tip == 'bonservis');

Future<void> kartiGoster(WidgetTester tester, OyunModu mod, int? skor) {
  return tester.pumpWidget(MaterialApp(
    home: Scaffold(body: OyunKarti(mod: mod, bugunkuSkor: skor, onTap: () {})),
  ));
}

void main() {
  testWidgets('bugün oynanmamış aktif oyunda "Oyna" yazar', (tester) async {
    await kartiGoster(tester, kesisim, null);

    expect(find.text('Oyna'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsNothing);
  });

  testWidgets('bugün oynanmış oyunda "Oyna" yerine skor yazar', (tester) async {
    await kartiGoster(tester, kesisim, 8);

    expect(find.text('Oyna'), findsNothing);
    expect(find.text('8/10'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('henüz hazır olmayan oyunda "Hazırlanıyor" yazar', (tester) async {
    await kartiGoster(tester, bonservis, null);

    expect(find.text('Hazırlanıyor'), findsOneWidget);
    expect(find.text('Oyna'), findsNothing);
  });

  test('ilk fazda sadece Kesişim oynanabilir durumda', () {
    final aktifler = oyunModlari.where((m) => m.durum == OyunDurumu.aktif).map((m) => m.tip);
    expect(aktifler, ['kesisim']);
  });
}
