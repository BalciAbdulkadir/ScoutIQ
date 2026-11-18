import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/oyun_modu.dart';
import 'package:mobile/screens/top10_screen.dart';
import 'package:mobile/services/oyun_deposu.dart';
import 'package:mobile/widgets/oyun_kurallari.dart';

import 'top10_test.dart' show top10Deposu;

void main() {
  Future<void> dugmeyiAc(WidgetTester tester, String oyun) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(appBar: AppBar(actions: [KurallarDugmesi(oyun: oyun)])),
    ));
  }

  for (final mod in oyunModlari.where((m) => m.onizleme != null)) {
    testWidgets('${mod.baslik}: "?" düğmesi oyunun kurallarını açar, "Oyuna dön" kapatır', (tester) async {
      await dugmeyiAc(tester, mod.tip!);

      await tester.tap(find.byTooltip('Nasıl oynanır'));
      await tester.pumpAndSettle();

      expect(find.text('NASIL OYNANIR'), findsOneWidget);
      expect(find.text(mod.onizleme!.ozet), findsOneWidget);
      expect(find.text(mod.onizleme!.kurallar.first), findsOneWidget);

      await tester.tap(find.text('OYUNA DÖN'));
      await tester.pumpAndSettle();
      expect(find.text('NASIL OYNANIR'), findsNothing);
    });
  }

  testWidgets('bilinmeyen oyunda düğme görünmez', (tester) async {
    await dugmeyiAc(tester, 'yok');

    expect(find.byTooltip('Nasıl oynanır'), findsNothing);
  });

  testWidgets('oyun ekranında "?" düğmesi var, kurallar açılınca oyun kaldığı yerde durur', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [oyunDeposuProvider.overrideWithValue(top10Deposu())],
      child: const MaterialApp(home: Top10Screen()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Nasıl oynanır'));
    await tester.pumpAndSettle();
    expect(find.text('NASIL OYNANIR'), findsOneWidget);

    await tester.tap(find.text('OYUNA DÖN'));
    await tester.pumpAndSettle();
    expect(find.text('0/10'), findsOneWidget);
    expect(find.text('Pes et'), findsOneWidget);
  });
}
