import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/izgara.dart';
import 'package:mobile/models/oyuncu_oneri.dart';
import 'package:mobile/providers/izgara_provider.dart';
import 'package:mobile/screens/izgara_screen.dart';
import 'package:mobile/services/oyun_deposu.dart';

import 'yardimcilar/sahte_oyun_deposu.dart';

const dogruOyuncu = OyuncuOneri(id: 'o-1', isim: 'Arda Güler');
const yanlisOyuncu = OyuncuOneri(id: 'o-2', isim: 'Mesut Özil');

Map<String, dynamic> kulup(String isim) => {'tip': 'kulup', 'id': 'k-$isim', 'tm_id': '1', 'isim': isim, 'logo': null};
Map<String, dynamic> milli(String tmId, String isim) => {'tip': 'milli', 'tm_id': tmId, 'isim': isim};

// Satırlar: Galatasaray, Real Madrid, Fenerbahçe; sütunlar: Türkiye, Fransa, Juventus
final ornekTahta = {
  'satirlar': [kulup('Galatasaray'), kulup('Real Madrid'), kulup('Fenerbahçe')],
  'sutunlar': [milli('3381', 'Türkiye'), milli('3377', 'Fransa'), kulup('Juventus')],
  'cevap_sayilari': [5, 4, 6, 3, 8, 4, 7, 3, 5],
};

SahteOyunDeposu izgaraDeposu([void Function(SahteOyunDeposu)? ayarla]) {
  final depo = SahteOyunDeposu()..oyun = {'id': 'izgara-1', 'soru_verisi': ornekTahta};
  ayarla?.call(depo);
  return depo;
}

Future<(ProviderContainer, SahteOyunDeposu)> tahtayiAc([void Function(SahteOyunDeposu)? ayarla]) async {
  final depo = izgaraDeposu(ayarla);
  final container = ProviderContainer(overrides: [oyunDeposuProvider.overrideWithValue(depo)]);
  addTearDown(container.dispose);

  final provider = izgaraProvider(IzgaraZorlugu.kolay);
  container.listen(provider, (_, _) {});
  for (var i = 0; i < 100 && container.read(provider).durum == IzgaraDurumu.yukleniyor; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  return (container, depo);
}

IzgaraState durum(ProviderContainer c) => c.read(izgaraProvider(IzgaraZorlugu.kolay));
IzgaraNotifier notifier(ProviderContainer c) => c.read(izgaraProvider(IzgaraZorlugu.kolay).notifier);

void main() {
  group('Tahta verisi', () {
    test('satır ve sütun başlıkları okunur, hücre numarası satır * 3 + sütun', () {
      final tahta = IzgaraTahtasi.oku(ornekTahta)!;

      expect(tahta.satiri(5).isim, 'Real Madrid');
      expect(tahta.sutunu(5).isim, 'Juventus');
    });

    test('milli takımlar federasyon armasıyla, kulüpler kendi logosuyla gösterilir', () {
      final tahta = IzgaraTahtasi.oku(ornekTahta)!;

      expect(tahta.sutunlar[1].milli, isTrue);
      expect(tahta.sutunlar[1].logoUrl, endsWith('/3377.png'));
      expect(tahta.satirlar[0].milli, isFalse);
      expect(tahta.satirlar[0].logoUrl, isNull);
    });

    test('bozuk tahta okunmaz', () {
      expect(IzgaraTahtasi.oku(null), isNull);
      expect(IzgaraTahtasi.oku([1, 2, 3]), isNull);
      expect(IzgaraTahtasi.oku({'satirlar': [], 'sutunlar': []}), isNull);
    });
  });

  group('Oyunun açılması', () {
    test('tahta açılır ve kayıt "basladi" olarak atılır', () async {
      final (c, depo) = await tahtayiAc();

      expect(durum(c).durum, IzgaraDurumu.oynaniyor);
      expect(durum(c).kalanHak, 9);
      expect(depo.kayitAcSayisi, 1);
    });

    test('yarıda bırakılan tahta önceki tahminlerle kaldığı yerden devam eder', () async {
      final (c, depo) = await tahtayiAc((d) {
        d.kayit = {'skor': 1, 'durum': 'basladi'};
        d.izgaraTahminListesi = const [
          IzgaraTahmini(sira: 1, oyuncuIsim: 'Arda Güler', hucre: 4),
          IzgaraTahmini(sira: 2, oyuncuIsim: 'Mesut Özil'),
        ];
      });

      expect(durum(c).durum, IzgaraDurumu.oynaniyor);
      expect(durum(c).hucreler.keys, [4]);
      expect(durum(c).kalanHak, 7);
      expect(depo.kayitAcSayisi, 0);
    });

    test('bitmiş tahta tekrar oynanmaz, örnek cevaplarla gösterilir', () async {
      final (c, depo) = await tahtayiAc((d) {
        d.kayit = {'skor': 1, 'durum': 'tamamlandi'};
        d.izgaraTahminListesi = const [IzgaraTahmini(sira: 1, oyuncuIsim: 'Arda Güler', hucre: 4)];
      });

      expect(durum(c).durum, IzgaraDurumu.bitti);
      expect(durum(c).skor, 1);
      expect(durum(c).ornekCevaplar, hasLength(9));
      expect(depo.kayitAcSayisi, 0);
    });

    test('günün tahtası yoksa oyun açılmaz ve kayıt atılmaz', () async {
      final (c, depo) = await tahtayiAc((d) => d.oyun = null);

      expect(durum(c).durum, IzgaraDurumu.oyunYok);
      expect(depo.kayitAcSayisi, 0);
    });
  });

  group('Tahminler', () {
    test('doğru oyuncu sunucunun söylediği hücreye yerleşir', () async {
      final (c, _) = await tahtayiAc();

      await notifier(c).tahminEt(dogruOyuncu);

      expect(durum(c).hucreler[4]?.isim, 'Arda Güler');
      expect(durum(c).skor, 1);
      expect(durum(c).kalanHak, 8);
      expect(durum(c).sonTahmin?.dogru, isTrue);
    });

    test('yanlış tahmin hak yer, hücre dolmaz', () async {
      final (c, _) = await tahtayiAc();

      await notifier(c).tahminEt(yanlisOyuncu);

      expect(durum(c).hucreler, isEmpty);
      expect(durum(c).kalanHak, 8);
      expect(durum(c).sonTahmin?.dogru, isFalse);
    });

    test('aynı oyuncu tekrar yazılırsa hak düşmez', () async {
      final (c, _) = await tahtayiAc();

      await notifier(c).tahminEt(dogruOyuncu);
      await notifier(c).tahminEt(dogruOyuncu);

      expect(durum(c).kalanHak, 8);
      expect(durum(c).sonTahmin?.tekrar, isTrue);
    });

    test('dokuz hak bitince oyun biter ve örnek cevaplar gelir', () async {
      final (c, _) = await tahtayiAc((d) {
        d.oneriler = [for (var i = 0; i < 9; i++) OyuncuOneri(id: 'y-$i', isim: 'Yanlış $i')];
      });

      for (var i = 0; i < 9; i++) {
        await notifier(c).tahminEt(OyuncuOneri(id: 'y-$i', isim: 'Yanlış $i'));
      }

      expect(durum(c).durum, IzgaraDurumu.bitti);
      expect(durum(c).kalanHak, 0);
      expect(durum(c).ornekCevaplar, hasLength(9));
    });

    test('tahmin gönderilemezse hata döner, hak düşmez', () async {
      final (c, _) = await tahtayiAc((d) => d.izgaraTahminHataVerir = true);

      final hata = await notifier(c).tahminEt(dogruOyuncu);

      expect(hata, contains('gönderilemedi'));
      expect(durum(c).kalanHak, 9);
      expect(durum(c).gonderiliyor, isFalse);
    });

    test('pes edince oyun o anki skorla biter', () async {
      final (c, depo) = await tahtayiAc();
      await notifier(c).tahminEt(dogruOyuncu);

      await notifier(c).pesEt();

      expect(depo.izgaraPesSayisi, 1);
      expect(durum(c).durum, IzgaraDurumu.bitti);
      expect(durum(c).skor, 1);
      expect(depo.kayit, {'skor': 1, 'durum': 'tamamlandi'});
    });
  });

  group('Ekran', () {
    Future<SahteOyunDeposu> ekraniAc(WidgetTester tester, [void Function(SahteOyunDeposu)? ayarla]) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);

      final depo = izgaraDeposu(ayarla);
      await tester.pumpWidget(ProviderScope(
        overrides: [oyunDeposuProvider.overrideWithValue(depo)],
        child: const MaterialApp(home: IzgaraScreen(zorluk: IzgaraZorlugu.orta)),
      ));
      await tester.pumpAndSettle();
      return depo;
    }

    testWidgets('başlıklar, hak sayısı ve zorluk gösterilir', (tester) async {
      await ekraniAc(tester);

      expect(find.text('ORTA'), findsOneWidget);
      expect(find.text('Galatasaray'), findsOneWidget);
      expect(find.text('Fransa'), findsOneWidget);
      expect(find.text('9 hak kaldı'), findsOneWidget);
      // Milli takım arması yüklenemezse bayrak ikonu çıkar
      expect(find.byIcon(Icons.flag_rounded), findsWidgets);
    });

    testWidgets('listeden seçilen doğru oyuncu tahtaya yerleşir', (tester) async {
      await ekraniAc(tester);

      await tester.enterText(find.byType(TextField), 'ar');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      await tester.tap(find.text('Arda Güler'));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      expect(find.text('8 hak kaldı'), findsOneWidget);
      expect(find.text('1/9 kutu'), findsOneWidget);
      // Sonuç satırında ve tahtadaki kutuda
      expect(find.text('Arda Güler'), findsOneWidget);
      expect(find.textContaining('Real Madrid × Fransa'), findsOneWidget);
    });

    testWidgets('pes etmek onay ister', (tester) async {
      final depo = await ekraniAc(tester);

      await tester.tap(find.text('Pes et'));
      await tester.pumpAndSettle();
      expect(find.text('Pes etmek istiyor musun?'), findsOneWidget);

      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();
      expect(depo.izgaraPesSayisi, 0);
      expect(find.text('9 hak kaldı'), findsOneWidget);
    });

    testWidgets('bitmiş tahtada boş kutular örnek cevaplarla gösterilir', (tester) async {
      await ekraniAc(tester, (d) {
        d.kayit = {'skor': 1, 'durum': 'tamamlandi'};
        d.izgaraTahminListesi = const [IzgaraTahmini(sira: 1, oyuncuIsim: 'Arda Güler', hucre: 4)];
      });

      expect(find.text('1/9'), findsOneWidget);
      expect(find.text('Arda Güler'), findsOneWidget);
      expect(find.text('Örnek Oyuncu 0'), findsOneWidget);
      expect(find.text('Ana menüye dön'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });
  });
}
