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

// Testin açtığı tahta: kolay, varsayılan olarak süresiz
IzgaraAcilisi acilis = (zorluk: IzgaraZorlugu.kolay, sure: null);

Future<(ProviderContainer, SahteOyunDeposu)> tahtayiAc([void Function(SahteOyunDeposu)? ayarla, int? sure]) async {
  final depo = izgaraDeposu(ayarla);
  final container = ProviderContainer(overrides: [oyunDeposuProvider.overrideWithValue(depo)]);
  addTearDown(container.dispose);

  acilis = (zorluk: IzgaraZorlugu.kolay, sure: sure);
  final provider = izgaraProvider(acilis);
  container.listen(provider, (_, _) {});
  for (var i = 0; i < 100 && container.read(provider).durum == IzgaraDurumu.yukleniyor; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  return (container, depo);
}

IzgaraState durum(ProviderContainer c) => c.read(izgaraProvider(acilis));
IzgaraNotifier notifier(ProviderContainer c) => c.read(izgaraProvider(acilis).notifier);

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
      expect(durum(c).tahminSayisi, 0);
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
      expect(durum(c).tahminSayisi, 2);
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

    test('bugün başka zorlukta Izgara oynandıysa tahta açılmaz', () async {
      final (c, _) = await tahtayiAc((d) => d.baskaIzgaraOynandi = true);

      expect(durum(c).durum, IzgaraDurumu.hata);
      expect(durum(c).hataMesaji, baskaIzgaraMesaji);
    });
  });

  group('Tahminler', () {
    test('doğru oyuncu sunucunun söylediği hücreye yerleşir', () async {
      final (c, _) = await tahtayiAc();

      await notifier(c).tahminEt(dogruOyuncu);

      expect(durum(c).hucreler[4]?.isim, 'Arda Güler');
      expect(durum(c).skor, 1);
      expect(durum(c).tahminSayisi, 1);
      expect(durum(c).sonTahmin?.dogru, isTrue);
    });

    test('yanlış tahmin sayılır, hücre dolmaz', () async {
      final (c, _) = await tahtayiAc();

      await notifier(c).tahminEt(yanlisOyuncu);

      expect(durum(c).hucreler, isEmpty);
      expect(durum(c).tahminSayisi, 1);
      expect(durum(c).sonTahmin?.dogru, isFalse);
    });

    test('aynı oyuncu tekrar yazılırsa tahmin sayılmaz', () async {
      final (c, _) = await tahtayiAc();

      await notifier(c).tahminEt(dogruOyuncu);
      await notifier(c).tahminEt(dogruOyuncu);

      expect(durum(c).tahminSayisi, 1);
      expect(durum(c).sonTahmin?.tekrar, isTrue);
    });

    test('tahmin hakkı sınırı yok: dokuzdan fazla yanlış tahminde oyun sürer', () async {
      final (c, _) = await tahtayiAc((d) {
        d.oneriler = [for (var i = 0; i < 12; i++) OyuncuOneri(id: 'y-$i', isim: 'Yanlış $i')];
      });

      for (var i = 0; i < 12; i++) {
        await notifier(c).tahminEt(OyuncuOneri(id: 'y-$i', isim: 'Yanlış $i'));
      }

      expect(durum(c).durum, IzgaraDurumu.oynaniyor);
      expect(durum(c).tahminSayisi, 12);
    });

    test('dokuz kutu dolunca oyun biter', () async {
      final (c, _) = await tahtayiAc((d) {
        d.oneriler = [for (var i = 0; i < 9; i++) OyuncuOneri(id: 'd-$i', isim: 'Doğru $i')];
        d.izgaraHucreleri = {for (var i = 0; i < 9; i++) 'd-$i': i};
      });

      for (var i = 0; i < 9; i++) {
        await notifier(c).tahminEt(OyuncuOneri(id: 'd-$i', isim: 'Doğru $i'));
      }

      expect(durum(c).durum, IzgaraDurumu.bitti);
      expect(durum(c).skor, 9);
    });

    test('tahmin gönderilemezse hata döner, tahmin sayılmaz', () async {
      final (c, _) = await tahtayiAc((d) => d.izgaraTahminHataVerir = true);

      final hata = await notifier(c).tahminEt(dogruOyuncu);

      expect(hata, contains('gönderilemedi'));
      expect(durum(c).tahminSayisi, 0);
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

  group('Süre', () {
    test('süresiz tahtada sayaç yoktur', () async {
      final (c, depo) = await tahtayiAc();

      expect(durum(c).bitisZamani, isNull);
      expect(depo.izgaraSureToplam, isNull);
    });

    test('yeni tahtada seçilen süre sunucuda başlatılır', () async {
      final (c, depo) = await tahtayiAc(null, 60);

      expect(depo.sureBaslatmaIstekleri, [60]);
      expect(durum(c).sureSaniye, 60);
      final kalan = durum(c).bitisZamani!.difference(DateTime.now()).inSeconds;
      expect(kalan, inInclusiveRange(58, 60));
    });

    test('yarım kalan tahtada yeni süre gönderilmez, sunucudaki kalan süreyle devam edilir', () async {
      final (c, depo) = await tahtayiAc((d) {
        d.kayit = {'skor': 0, 'durum': 'basladi'};
        d.izgaraSureToplam = 90;
        d.izgaraSureKalan = 25;
      }, 30);

      expect(depo.sureBaslatmaIstekleri, [null]);
      expect(durum(c).sureSaniye, 90);
      final kalan = durum(c).bitisZamani!.difference(DateTime.now()).inSeconds;
      expect(kalan, inInclusiveRange(23, 25));
    });

    test('uygulama kapalıyken süre dolduysa tahta açılınca kapatılır', () async {
      final (c, depo) = await tahtayiAc((d) {
        d.kayit = {'skor': 2, 'durum': 'basladi'};
        d.izgaraSureToplam = 30;
        d.izgaraSureKalan = 0;
      });

      expect(durum(c).durum, IzgaraDurumu.bitti);
      expect(durum(c).sureDoldu, isTrue);
      expect(depo.izgaraPesSayisi, 1);
    });

    test('süre sunucudan alınamazsa tahta süresiz açılır', () async {
      final (c, _) = await tahtayiAc((d) => d.izgaraSureHataVerir = true, 60);

      expect(durum(c).durum, IzgaraDurumu.oynaniyor);
      expect(durum(c).bitisZamani, isNull);
    });

    test('sayaç sıfırlanınca oyun o anki skorla biter', () async {
      final (c, depo) = await tahtayiAc(null, 30);
      await notifier(c).tahminEt(dogruOyuncu);

      await notifier(c).sureDoldu();

      expect(durum(c).durum, IzgaraDurumu.bitti);
      expect(durum(c).sureDoldu, isTrue);
      expect(durum(c).skor, 1);
      expect(depo.izgaraPesSayisi, 1);
    });

    test('süre dolduktan sonra gelen tahmini sunucu reddederse oyun biter', () async {
      final (c, depo) = await tahtayiAc(null, 30);
      depo.izgaraSuresiDoldu = true;

      await notifier(c).tahminEt(dogruOyuncu);

      expect(durum(c).durum, IzgaraDurumu.bitti);
      expect(durum(c).sureDoldu, isTrue);
      expect(durum(c).hucreler, isEmpty);
    });
  });

  group('Ekran', () {
    Future<SahteOyunDeposu> ekraniAc(WidgetTester tester, [void Function(SahteOyunDeposu)? ayarla, int? sure]) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);

      final depo = izgaraDeposu(ayarla);
      await tester.pumpWidget(ProviderScope(
        overrides: [oyunDeposuProvider.overrideWithValue(depo)],
        child: MaterialApp(home: IzgaraScreen(zorluk: IzgaraZorlugu.orta, sure: sure)),
      ));
      // Sayaç sürekli güncellendiği için süreli tahtada pumpAndSettle bitmez
      if (sure == null) {
        await tester.pumpAndSettle();
      } else {
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }
      return depo;
    }

    testWidgets('süreli tahtada geri sayım gösterilir', (tester) async {
      await ekraniAc(tester, null, 60);

      expect(find.byIcon(Icons.timer_outlined), findsOneWidget);
      expect(find.textContaining(RegExp(r'^(1:00|0:5\d)$')), findsOneWidget);
      // Sayacın zamanlayıcısı test bitmeden kapansın
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('süresiz tahtada geri sayım yoktur', (tester) async {
      await ekraniAc(tester);

      expect(find.byIcon(Icons.timer_outlined), findsNothing);
    });

    testWidgets('süre dolan tahtanın bitiş ekranında "Süre doldu" yazar', (tester) async {
      await ekraniAc(tester, (d) {
        d.kayit = {'skor': 0, 'durum': 'basladi'};
        d.izgaraSureToplam = 30;
        d.izgaraSureKalan = 0;
      });

      expect(find.text('SÜRE DOLDU'), findsOneWidget);
      expect(find.text('Ana menüye dön'), findsOneWidget);
    });

    testWidgets('başlıklar, ilerleme ve zorluk gösterilir', (tester) async {
      await ekraniAc(tester);

      expect(find.text('ORTA'), findsOneWidget);
      expect(find.text('Galatasaray'), findsOneWidget);
      expect(find.text('Fransa'), findsOneWidget);
      expect(find.text('0 tahmin'), findsOneWidget);
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

      expect(find.text('1 tahmin'), findsOneWidget);
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
      expect(find.text('0 tahmin'), findsOneWidget);
    });

    testWidgets('bitmiş tahtada boş kutular örnek cevaplarla gösterilir', (tester) async {
      await ekraniAc(tester, (d) {
        d.kayit = {'skor': 1, 'durum': 'tamamlandi'};
        d.izgaraTahminListesi = const [IzgaraTahmini(sira: 1, oyuncuIsim: 'Arda Güler', hucre: 4)];
      });

      expect(find.text('1/9'), findsOneWidget);
      expect(find.text('Arda Güler'), findsOneWidget);
      expect(find.text('Örnek Oyuncu 0'), findsOneWidget);
      // Bulunamayan kutulardaki örnek cevaplar da fotoğrafıyla gösterilir: 1 dolu + 8 örnek
      final fotograflar = tester.widgetList<Image>(find.byType(Image)).where((i) {
        final kaynak = i.image is ResizeImage ? (i.image as ResizeImage).imageProvider : i.image;
        return kaynak is NetworkImage && kaynak.url.startsWith('https://foto.test/');
      });
      expect(fotograflar, hasLength(8));
      expect(find.text('Ana menüye dön'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });
  });
}
