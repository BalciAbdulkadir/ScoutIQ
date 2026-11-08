import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/oyun_modu.dart';
import 'package:mobile/widgets/oyun_karti.dart';
import 'package:mobile/widgets/tebesir.dart';

final kesisim = oyunModlari.firstWhere((m) => m.tip == 'kesisim');
final bonservis = oyunModlari.firstWhere((m) => m.tip == 'bonservis');
final izgara = oyunModlari.firstWhere((m) => m.tip == 'izgara');

Future<void> kartiGoster(WidgetTester tester, OyunModu mod, int? skor, {String? zorluk, bool devam = false}) {
  return tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: OyunKarti(mod: mod, bugunkuSkor: skor, oynananZorluk: zorluk, devamEdiyor: devam, onTap: () {}),
    ),
  ));
}

void main() {
  testWidgets('bugün oynanmamış aktif oyunda "Oyna" yazar', (tester) async {
    await kartiGoster(tester, kesisim, null);

    expect(find.text('Oyna'), findsOneWidget);
    expect(find.byType(TebesirDamga), findsNothing);
  });

  testWidgets('bugün oynanmış oyunda "Oyna" yerine tebeşir damgasıyla skor yazar', (tester) async {
    await kartiGoster(tester, kesisim, 8);

    expect(find.text('Oyna'), findsNothing);
    expect(find.text('8/10'), findsOneWidget);
    expect(find.byType(TebesirDamga), findsOneWidget);
  });

  testWidgets('Bonservis skoru 10 üzerinden gösterilir (her doğru 2 puan)', (tester) async {
    await kartiGoster(tester, bonservis, 6);

    expect(find.text('6/10'), findsOneWidget);
  });

  testWidgets('zorluklu oyunlarda K O Z yazar', (tester) async {
    for (final mod in [kesisim, bonservis, izgara]) {
      await kartiGoster(tester, mod, null);
      expect(find.text('TEK MOD'), findsNothing);
      expect(find.text('K'), findsOneWidget);
      expect(find.text('O'), findsOneWidget);
      expect(find.text('Z'), findsOneWidget);
    }
  });

  testWidgets('zorluklu oyun bitince oynanan zorluk ve skor kalır', (tester) async {
    await kartiGoster(tester, izgara, 7, zorluk: 'Orta');

    expect(find.text('7/9'), findsOneWidget);
    expect(find.text('ORTA'), findsOneWidget);
    expect(find.text('K'), findsNothing);
  });

  testWidgets('yarım kalan oyunda "Devam et" ve oynanan zorluk yazar', (tester) async {
    await kartiGoster(tester, izgara, null, zorluk: 'Zor', devam: true);

    expect(find.text('Devam et'), findsOneWidget);
    expect(find.text('ZOR'), findsOneWidget);
  });

  testWidgets('henüz hazır olmayan oyunda "Hazırlanıyor" yazar', (tester) async {
    const hazirlanan = OyunModu(
      tip: 'yeni_mod',
      baslik: 'Yeni Mod',
      aciklama: 'Açıklama',
      ikon: Icons.star,
      renk: Colors.grey,
      durum: OyunDurumu.hazirlaniyor,
    );
    await kartiGoster(tester, hazirlanan, null);

    expect(find.text('Hazırlanıyor'), findsOneWidget);
    expect(find.text('Oyna'), findsNothing);
  });

  test('oynanabilir modlar Kesişim, Bonservis, Izgara ve Bingo', () {
    final aktifler = oyunModlari.where((m) => m.durum == OyunDurumu.aktif).map((m) => m.tip);
    expect(aktifler, ['kesisim', 'bonservis', 'izgara', 'bingo']);
  });

  test('her oyun zorlukludur, her zorluğun ayrı günlük oyunu vardır', () {
    expect(izgara.zorluklu, isTrue);
    expect(izgara.oyunTipleri, ['izgara_kolay', 'izgara_orta', 'izgara_zor']);
    expect(kesisim.zorluklu, isTrue);
    expect(bonservis.oyunTipleri, ['bonservis_kolay', 'bonservis_orta', 'bonservis_zor']);
    expect(kesisim.oyunTipleri, ['kesisim_kolay', 'kesisim_orta', 'kesisim_zor']);
  });

  test('süre seçenekleri süresiz, 30, 60 ve 90 saniyedir', () {
    expect(OyunSuresi.values.map((s) => s.saniye), [null, 30, 60, 90]);
  });
}
