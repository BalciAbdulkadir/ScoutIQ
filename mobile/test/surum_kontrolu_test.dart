import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/screens/guncelleme_screen.dart';
import 'package:mobile/services/paylasim.dart';
import 'package:mobile/services/surum_kontrolu.dart';
import 'package:mobile/theme/tema.dart';

// Sunucuya gitmeyen sahte depo: istenen sınırı döndürür, istenirse hata verir ya da hiç cevap vermez
class SahteSurumDeposu implements SurumDeposu {
  SurumSarti? sart;
  bool hataVerir = false;
  bool cevapVermez = false;

  SahteSurumDeposu([this.sart]);

  @override
  Future<SurumSarti?> oku() async {
    if (hataVerir) throw Exception('internet yok');
    if (cevapVermez) return Completer<SurumSarti?>().future;
    return sart;
  }
}

void main() {
  group('guncellemeGerekli', () {
    test('sürüm kodu sınırdan küçükse güncelleme gerekir', () {
      expect(guncellemeGerekli(surumKodu: '1', enDusukSurumKodu: 2), isTrue);
      expect(guncellemeGerekli(surumKodu: '9', enDusukSurumKodu: 10), isTrue);
    });

    test('sınıra eşit ya da büyükse gerekmez', () {
      expect(guncellemeGerekli(surumKodu: '2', enDusukSurumKodu: 2), isFalse);
      expect(guncellemeGerekli(surumKodu: '10', enDusukSurumKodu: 9), isFalse);
    });

    test('sayılar metin gibi değil sayı gibi karşılaştırılır', () {
      expect(guncellemeGerekli(surumKodu: '100', enDusukSurumKodu: 20), isFalse);
      expect(guncellemeGerekli(surumKodu: ' 3 ', enDusukSurumKodu: 4), isTrue);
    });

    test('sürüm kodu okunamazsa ya da sınır yoksa uygulama engellenmez', () {
      expect(guncellemeGerekli(surumKodu: '', enDusukSurumKodu: 5), isFalse);
      expect(guncellemeGerekli(surumKodu: 'abc', enDusukSurumKodu: 5), isFalse);
      expect(guncellemeGerekli(surumKodu: '1', enDusukSurumKodu: null), isFalse);
    });
  });

  test('sunucu mesajı boşsa uygulamanın mesajı gösterilir', () {
    expect(guncellemeMesaji(null), varsayilanGuncellemeMesaji);
    expect(guncellemeMesaji('  '), varsayilanGuncellemeMesaji);
    expect(guncellemeMesaji('Yeni Top 10 için güncelle'), 'Yeni Top 10 için güncelle');
  });

  group('açılış', () {
    late List<Uri> acilanlar;
    late bool acilabilir;

    setUp(() {
      acilanlar = [];
      acilabilir = true;
    });

    Future<void> uygulamayiAc(WidgetTester tester, SahteSurumDeposu depo, {String surumKodu = '1'}) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          surumDeposuProvider.overrideWithValue(depo),
          surumKoduProvider.overrideWithValue(() async => surumKodu),
          baglantiAciciProvider.overrideWithValue((adres) async {
            acilanlar.add(adres);
            return acilabilir;
          }),
        ],
        child: MaterialApp(
          theme: uygulamaTemasi(),
          home: const SurumKapisi(child: Scaffold(body: Text('giriş ekranı'))),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('sürüm güncelse uygulama normal açılır', (tester) async {
      await uygulamayiAc(tester, SahteSurumDeposu((enDusukSurumKodu: 1, mesaj: null)));

      expect(find.text('giriş ekranı'), findsOneWidget);
      expect(find.byType(GuncellemeScreen), findsNothing);
    });

    testWidgets('sürüm eskiyse giriş yerine güncelleme sayfası açılır', (tester) async {
      await uygulamayiAc(tester, SahteSurumDeposu((enDusukSurumKodu: 2, mesaj: 'Yeni sürüm hazır.')));

      expect(find.byType(GuncellemeScreen), findsOneWidget);
      expect(find.text('GÜNCELLEME GEREKLİ'), findsOneWidget);
      expect(find.text('Yeni sürüm hazır.'), findsOneWidget);
      expect(find.text('giriş ekranı'), findsNothing);
    });

    testWidgets('sunucu mesajı yoksa varsayılan mesaj yazar', (tester) async {
      await uygulamayiAc(tester, SahteSurumDeposu((enDusukSurumKodu: 2, mesaj: null)));

      expect(find.text(varsayilanGuncellemeMesaji), findsOneWidget);
    });

    testWidgets('istek başarısız olursa (internet yok) uygulama engellenmez', (tester) async {
      await uygulamayiAc(tester, SahteSurumDeposu()..hataVerir = true);

      expect(find.text('giriş ekranı'), findsOneWidget);
    });

    testWidgets('tabloda satır yoksa uygulama engellenmez', (tester) async {
      await uygulamayiAc(tester, SahteSurumDeposu());

      expect(find.text('giriş ekranı'), findsOneWidget);
    });

    testWidgets('sunucu cevap vermezse açılış süre dolunca normal devam eder', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          surumDeposuProvider.overrideWithValue(SahteSurumDeposu()..cevapVermez = true),
          surumKoduProvider.overrideWithValue(() async => '1'),
        ],
        child: const MaterialApp(home: SurumKapisi(child: Scaffold(body: Text('giriş ekranı')))),
      ));
      await tester.pump();
      expect(find.text('giriş ekranı'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pump(surumKontroluSuresi + const Duration(milliseconds: 100));
      await tester.pump();
      expect(find.text('giriş ekranı'), findsOneWidget);
    });

    testWidgets('Güncelle düğmesi Play sayfasını açar', (tester) async {
      await uygulamayiAc(tester, SahteSurumDeposu((enDusukSurumKodu: 2, mesaj: null)));

      await tester.tap(find.text('GÜNCELLE'));
      await tester.pump();

      expect(acilanlar, [Uri.parse(playStoreLinki)]);
    });

    testWidgets('Play açılamazsa bağlantı mesajla gösterilir', (tester) async {
      acilabilir = false;
      await uygulamayiAc(tester, SahteSurumDeposu((enDusukSurumKodu: 2, mesaj: null)));

      await tester.tap(find.text('GÜNCELLE'));
      await tester.pump();

      expect(find.textContaining(playStoreLinki), findsOneWidget);
    });

    testWidgets('güncelleme sayfası geri tuşuyla kapatılamaz', (tester) async {
      await uygulamayiAc(tester, SahteSurumDeposu((enDusukSurumKodu: 2, mesaj: null)));

      final kapanabilir = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(kapanabilir, isTrue); // Geri tuşu sayfada yakalandı, uygulama kapanmadı
      expect(find.byType(GuncellemeScreen), findsOneWidget);
      final pop = tester.widget<PopScope>(find.byType(PopScope));
      expect(pop.canPop, isFalse);
    });
  });
}
