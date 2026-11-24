import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/oyuncu_oneri.dart';
import 'package:mobile/models/top10.dart';
import 'package:mobile/providers/top10_provider.dart';
import 'package:mobile/screens/top10_screen.dart';
import 'package:mobile/services/oyun_deposu.dart';
import 'package:mobile/services/paylasim.dart';
import 'package:mobile/widgets/izgara_zorluk_secimi.dart';
import 'package:mobile/models/oyun_modu.dart';
import 'package:mobile/widgets/tebesir.dart';

import 'yardimcilar/sahte_oyun_deposu.dart';

final ornekSoru = {
  'sablon': 'T1',
  'baslik': "Galatasaray'ın en pahalı 10 transferi",
  'alt_baslik': "2000'den bugüne · Kasım 2026 itibarıyla",
  'satirlar': [
    for (var i = 1; i <= 10; i++) {'sira': i, 'ulke': 'Spain', 'bayrak': null},
  ],
};

const arda = OyuncuOneri(id: 'o-1', isim: 'Arda Güler');
const mesut = OyuncuOneri(id: 'o-2', isim: 'Mesut Özil');

SahteOyunDeposu top10Deposu() => SahteOyunDeposu()
  ..oyun = {'id': 'top10-1', 'soru_verisi': ornekSoru}
  ..oneriler = [
    arda,
    mesut,
    for (var i = 1; i <= 10; i++) OyuncuOneri(id: 'liste-$i', isim: 'Liste Oyuncusu $i'),
  ];

Future<(ProviderContainer, SahteOyunDeposu)> oyunuAc([void Function(SahteOyunDeposu)? ayarla]) async {
  final depo = top10Deposu();
  ayarla?.call(depo);

  final container = ProviderContainer(overrides: [oyunDeposuProvider.overrideWithValue(depo)]);
  addTearDown(container.dispose);
  final provider = top10Provider(const Top10Acilis());
  container.listen(provider, (_, _) {});
  for (var i = 0; i < 100 && container.read(provider).durum == Top10Durumu.yukleniyor; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  return (container, depo);
}

Top10State durum(ProviderContainer c) => c.read(top10Provider(const Top10Acilis()));
Top10Notifier notifier(ProviderContainer c) => c.read(top10Provider(const Top10Acilis()).notifier);

void main() {
  group('Soru', () {
    test('soru verisinden başlık, dönem ve 10 satır okunur', () {
      final soru = Top10Sorusu.oku(ornekSoru)!;

      expect(soru.baslik, "Galatasaray'ın en pahalı 10 transferi");
      expect(soru.altBaslik, contains('2000'));
      expect(soru.satirlar.map((s) => s.sira), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
    });

    test('eksik soru okunmaz', () {
      expect(Top10Sorusu.oku({'baslik': 'x', 'satirlar': []}), isNull);
      expect(Top10Sorusu.oku(null), isNull);
    });
  });

  group('Oyun', () {
    test('yeni oyunda kayıt açılır ve liste boş başlar', () async {
      final (c, depo) = await oyunuAc();

      expect(durum(c).durum, Top10Durumu.oynaniyor);
      expect(depo.acilanKayitTipleri, ['top10']);
      expect(durum(c).skor, 0);
    });

    test('doğru oyuncu kendi sırasına yerleşir ve değeri görünür', () async {
      final (c, _) = await oyunuAc();

      await notifier(c).tahminEt(arda);

      expect(durum(c).bulunanlar[3]?.isim, 'Arda Güler');
      expect(durum(c).bulunanlar[3]?.deger, '30 M€');
      expect(durum(c).skor, 1);
      expect(durum(c).sonTahmin?.dogru, isTrue);
    });

    test('oyun 3 canla başlar', () async {
      final (c, _) = await oyunuAc();

      expect(durum(c).kalanCan, 3);
    });

    test('yanlış tahmin bir can götürür, oyun sürer', () async {
      final (c, _) = await oyunuAc();

      await notifier(c).tahminEt(mesut);

      expect(durum(c).durum, Top10Durumu.oynaniyor);
      expect(durum(c).skor, 0);
      expect(durum(c).kalanCan, 2);
      expect(durum(c).sonTahmin?.dogru, isFalse);
      expect(durum(c).denenenler, contains('Mesut Özil'));
    });

    test('doğru tahmin can götürmez', () async {
      final (c, _) = await oyunuAc();

      await notifier(c).tahminEt(arda);

      expect(durum(c).kalanCan, 3);
    });

    test('daha önce denenen oyuncu tekrar sayılmaz, can da götürmez', () async {
      final (c, depo) = await oyunuAc();

      await notifier(c).tahminEt(mesut);
      await notifier(c).tahminEt(mesut);

      expect(durum(c).sonTahmin?.tekrar, isTrue);
      expect(depo.top10TahminListesi, hasLength(1));
      expect(durum(c).kalanCan, 2);
    });

    test('üçüncü yanlış tahminde oyun o anki skorla biter ve liste açılır', () async {
      final (c, depo) = await oyunuAc((d) => d.oneriler = [
            ...d.oneriler,
            const OyuncuOneri(id: 'o-3', isim: 'Hakan Şükür'),
            const OyuncuOneri(id: 'o-4', isim: 'Emre Belözoğlu'),
          ]);

      await notifier(c).tahminEt(arda);
      await notifier(c).tahminEt(mesut);
      await notifier(c).tahminEt(const OyuncuOneri(id: 'o-3', isim: 'Hakan Şükür'));
      expect(durum(c).durum, Top10Durumu.oynaniyor);
      await notifier(c).tahminEt(const OyuncuOneri(id: 'o-4', isim: 'Emre Belözoğlu'));

      expect(durum(c).durum, Top10Durumu.bitti);
      expect(durum(c).kalanCan, 0);
      expect(durum(c).skor, 1);
      expect(depo.kayit?['durum'], 'tamamlandi');
      expect(durum(c).cevaplar, hasLength(10));
    });

    test('yarım kalan oyunda canlar yanlış tahminlerden hesaplanır', () async {
      final (c, _) = await oyunuAc((d) {
        d.kayit = {'skor': 0, 'durum': 'basladi'};
        d.top10TahminListesi = [
          const Top10Tahmini(oyuncuIsim: 'Mesut Özil'),
          const Top10Tahmini(oyuncuIsim: 'Hakan Şükür'),
        ];
      });

      expect(durum(c).durum, Top10Durumu.oynaniyor);
      expect(durum(c).kalanCan, 1);
    });

    test('10 oyuncu bulununca oyun biter', () async {
      final (c, _) = await oyunuAc();

      await notifier(c).tahminEt(arda);
      for (var i = 1; i <= 10; i++) {
        if (i != 3) await notifier(c).tahminEt(OyuncuOneri(id: 'liste-$i', isim: 'Liste Oyuncusu $i'));
      }

      expect(durum(c).durum, Top10Durumu.bitti);
      expect(durum(c).skor, 10);
    });

    test('pes edince oyun biter ve bütün liste açılır', () async {
      final (c, depo) = await oyunuAc();
      await notifier(c).tahminEt(arda);

      await notifier(c).pesEt();

      expect(durum(c).durum, Top10Durumu.bitti);
      expect(depo.top10PesSayisi, 1);
      expect(durum(c).cevaplar, hasLength(10));
      expect(durum(c).skor, 1);
    });

    test('yarım kalan oyun kaldığı yerden devam eder', () async {
      final (c, depo) = await oyunuAc((d) {
        d.kayit = {'skor': 1, 'durum': 'basladi'};
        d.top10TahminListesi = [
          const Top10Tahmini(oyuncuIsim: 'Arda Güler', sira: 3),
          const Top10Tahmini(oyuncuIsim: 'Mesut Özil'),
        ];
      });

      expect(durum(c).durum, Top10Durumu.oynaniyor);
      expect(depo.kayitAcSayisi, 0);
      expect(durum(c).bulunanlar.keys, [3]);
      expect(durum(c).bulunanlar[3]?.deger, '30 M€');
      expect(durum(c).denenenler, {'Arda Güler', 'Mesut Özil'});
    });

    test('bitmiş oyun sonucuyla açılır', () async {
      final (c, _) = await oyunuAc((d) {
        d.kayit = {'skor': 1, 'durum': 'tamamlandi'};
        d.top10TahminListesi = [const Top10Tahmini(oyuncuIsim: 'Arda Güler', sira: 3)];
      });

      expect(durum(c).durum, Top10Durumu.bitti);
      expect(durum(c).cevaplar, hasLength(10));
      expect(durum(c).bulunanlar.keys, [3]);
    });

    test('günün sorusu yoksa oyunYok', () async {
      final (c, _) = await oyunuAc((d) => d.oyun = null);

      expect(durum(c).durum, Top10Durumu.oyunYok);
    });

    test('tahmin gönderilemezse hata mesajı döner, oyun sürer', () async {
      final (c, _) = await oyunuAc((d) => d.top10TahminHataVerir = true);

      final hata = await notifier(c).tahminEt(arda);

      expect(hata, isNotNull);
      expect(durum(c).durum, Top10Durumu.oynaniyor);
      expect(durum(c).gonderiliyor, isFalse);
    });
  });

  group('Ekran', () {
    Future<SahteOyunDeposu> ekraniAc(WidgetTester tester, [void Function(SahteOyunDeposu)? ayarla]) async {
      final depo = top10Deposu();
      ayarla?.call(depo);
      await tester.pumpWidget(ProviderScope(
        overrides: [oyunDeposuProvider.overrideWithValue(depo)],
        child: const MaterialApp(home: Top10Screen()),
      ));
      await tester.pumpAndSettle();
      return depo;
    }

    testWidgets('başlık, dönem ve 10 numaralı satır görünür', (tester) async {
      await ekraniAc(tester);

      expect(find.text("Galatasaray'ın en pahalı 10 transferi"), findsOneWidget);
      expect(find.textContaining('2000'), findsOneWidget);
      for (var i = 1; i <= 10; i++) {
        expect(find.text('$i'), findsOneWidget);
      }
      expect(find.text('0/10'), findsOneWidget);
    });

    testWidgets('bitmiş oyunda bulunamayanlar da gösterilir', (tester) async {
      await ekraniAc(tester, (d) {
        d.kayit = {'skor': 1, 'durum': 'tamamlandi'};
        d.top10TahminListesi = [const Top10Tahmini(oyuncuIsim: 'Arda Güler', sira: 3)];
      });

      expect(find.text('1/10'), findsOneWidget);
      expect(find.text('Arda Güler'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Liste Oyuncusu 10'), 200);
      expect(find.text('Liste Oyuncusu 10'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Ana menüye dön'), 200);
      expect(find.text('Ana menüye dön'), findsOneWidget);
    });

    testWidgets('canlar kırmızı kalplerle gösterilir, giden can boş kalp olur', (tester) async {
      await ekraniAc(tester, (d) {
        d.kayit = {'skor': 0, 'durum': 'basladi'};
        d.top10TahminListesi = [const Top10Tahmini(oyuncuIsim: 'Mesut Özil')];
      });

      // Canlar listenin altında, yazma alanının üstünde
      await tester.scrollUntilVisible(find.byType(Top10Canlari), 200);
      final canlar = tester.getTopLeft(find.byType(Top10Canlari)).dy;
      expect(canlar, greaterThan(tester.getTopLeft(find.text('10')).dy));
      expect(canlar, lessThan(tester.getTopLeft(find.byType(TextField)).dy));
      expect(find.byIcon(Icons.favorite_rounded), findsNWidgets(2));
      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
      expect(find.bySemanticsLabel('2 can kaldı'), findsOneWidget);
    });

    testWidgets('pes et onay sorar, vazgeçince oyun sürer', (tester) async {
      final depo = await ekraniAc(tester);

      await tester.tap(find.text('Pes et'));
      await tester.pumpAndSettle();
      expect(find.text('Pes etmek istiyor musun?'), findsOneWidget);

      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();
      expect(depo.top10PesSayisi, 0);
      expect(find.text('0/10'), findsOneWidget);
    });

    testWidgets('küçük ekranda taşma olmaz', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await ekraniAc(tester, (d) {
        d.kayit = {'skor': 1, 'durum': 'tamamlandi'};
        d.top10TahminListesi = [const Top10Tahmini(oyuncuIsim: 'Arda Güler', sira: 3)];
      });

      expect(tester.takeException(), isNull);
    });
  });

  group('Cansız mod (045)', () {
    const cansizAcilis = Top10Acilis(cansiz: true);

    Future<(ProviderContainer, SahteOyunDeposu)> cansizAc([void Function(SahteOyunDeposu)? ayarla]) async {
      final depo = top10Deposu()
        ..oneriler = [
          ...top10Deposu().oneriler,
          for (var i = 1; i <= 4; i++) OyuncuOneri(id: 'yok-$i', isim: 'Listede Yok $i'),
        ];
      ayarla?.call(depo);
      final container = ProviderContainer(overrides: [oyunDeposuProvider.overrideWithValue(depo)]);
      addTearDown(container.dispose);
      container.listen(top10Provider(cansizAcilis), (_, _) {});
      for (var i = 0; i < 100 && container.read(top10Provider(cansizAcilis)).durum == Top10Durumu.yukleniyor; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      return (container, depo);
    }

    test('yeni oyun cansız açılır', () async {
      final (c, depo) = await cansizAc();

      expect(depo.acilisIstekleri.single.cansiz, isTrue);
      expect(c.read(top10Provider(cansizAcilis)).cansiz, isTrue);
    });

    test('yanlış tahminler oyunu bitirmez', () async {
      final (c, _) = await cansizAc();
      final n = c.read(top10Provider(cansizAcilis).notifier);

      for (var i = 1; i <= 4; i++) {
        await n.tahminEt(OyuncuOneri(id: 'yok-$i', isim: 'Listede Yok $i'));
      }

      final s = c.read(top10Provider(cansizAcilis));
      expect(s.durum, Top10Durumu.oynaniyor);
      expect(s.canBitti, isFalse);
      expect(s.sonTahmin?.kalanCan, isNull);
    });

    test('bugün canlı açılmış oyunda cansız seçimi yok sayılır', () async {
      final (c, _) = await cansizAc((d) => d.kayit = {'skor': 0, 'durum': 'basladi'});

      expect(c.read(top10Provider(cansizAcilis)).cansiz, isFalse);
    });

    test('canlı açılış cansız istemez', () async {
      final (_, depo) = await oyunuAc();

      expect(depo.acilisIstekleri.single.cansiz, isFalse);
    });

    testWidgets('ekranda kalp yerine cansız yazar', (tester) async {
      final depo = top10Deposu();
      await tester.pumpWidget(ProviderScope(
        overrides: [oyunDeposuProvider.overrideWithValue(depo)],
        child: const MaterialApp(home: Top10Screen(cansiz: true)),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(Top10Canlari), findsNothing);
      await tester.scrollUntilVisible(find.textContaining('CANSIZ'), 200);
      expect(find.textContaining('CANSIZ'), findsOneWidget);
    });

    testWidgets('kurallardan sonra 3 can ya da cansız seçilir', (tester) async {
      final top10 = oyunModlari.firstWhere((m) => m.tip == 'top10');
      ZorlukSureSecimi? secim;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => secim = await showModalBottomSheet<ZorlukSureSecimi>(
              context: context,
              isScrollControlled: true,
              builder: (_) => ZorlukSureSecimSayfasi(
                oyunAdi: top10.baslik,
                oyun: 'top10',
                cizim: TebesirCizimi.top10,
                sureler: top10.sureSecenekleri,
                onizleme: top10.onizleme,
                canSecimi: true,
              ),
            ),
            child: const Text('aç'),
          ),
        ),
      ));
      await tester.tap(find.text('aç'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('ANLADIM · MOD SEÇ'));
      await tester.pumpAndSettle();
      expect(find.text('3 CAN'), findsOneWidget);
      await tester.tap(find.text('CANSIZ'));
      await tester.pumpAndSettle();

      expect(secim?.cansiz, isTrue);
    });

    test('paylaşımda cansız oyunun kalp satırı yazmaz', () {
      final metin = top10Paylasimi(bulunanSiralar: {1, 2}, kalanCan: 3, cansiz: true);

      expect(metin, isNot(contains('❤️')));
      expect(metin, contains('2/10'));
    });
  });
}
