import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/oyuncu_oneri.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/providers/game_provider.dart';
import 'package:mobile/providers/hub_provider.dart';
import 'package:mobile/screens/profil_screen.dart';
import 'package:mobile/services/hatirlatma.dart';
import 'package:mobile/services/oyun_deposu.dart';
import 'package:mobile/services/oyun_sonu.dart';
import 'package:mobile/services/puanlama.dart';
import 'package:mobile/theme/tema.dart';
import 'package:timezone/data/latest.dart' as tz_veri;
import 'package:timezone/timezone.dart' as tz;

import 'home_screen_test.dart' show anaMenuyuAc, ekraniKapat;
import 'profil_test.dart' show SahteAuthService;
import 'yardimcilar/sahte_hatirlatma.dart';
import 'yardimcilar/sahte_oyun_deposu.dart';

void main() {
  tz_veri.initializeTimeZones();
  final istanbul = tz.getLocation('Europe/Istanbul');
  tz.TZDateTime saat(int gun, int saat, [int dakika = 0]) => tz.TZDateTime(istanbul, 2026, 11, gun, saat, dakika);

  group('Hatırlatma planı', () {
    test('bugün oynanmadıysa ve saat 20.00 olmadıysa bugünden başlayıp 7 gün, seri bugünün bildiriminde yazar', () {
      final plan = hatirlatmaPlani(simdi: saat(19, 14), seri: 6, bugunBitirdi: false);

      expect(plan, hasLength(7));
      expect(plan.first.zaman, saat(19, 20));
      expect(plan.first.id, 20261119);
      expect(plan.first.metin, 'Bugünün bulmacaları seni bekliyor 🔥 6 günlük serini kaçırma');
      expect(plan[1].metin, 'Bugünün bulmacaları seni bekliyor 🔥');
      expect(plan.last.zaman, saat(25, 20));
      expect(plan.every((h) => h.zaman.hour == 20 && h.zaman.minute == 0), isTrue);
    });

    test('bugün bir oyun bitirildiyse bugünün bildirimi kurulmaz, seri yarınkinde yazar', () {
      final plan = hatirlatmaPlani(simdi: saat(19, 14), seri: 6, bugunBitirdi: true);

      expect(plan, hasLength(6));
      expect(plan.first.zaman, saat(20, 20));
      expect(plan.first.metin, contains('6 günlük serini'));
      expect(plan[1].metin, isNot(contains('serini')));
    });

    test('saat 20.00 geçtiyse bugünün bildirimi kurulmaz', () {
      final plan = hatirlatmaPlani(simdi: saat(19, 20, 30), seri: 3, bugunBitirdi: false);

      expect(plan.first.zaman, saat(20, 20));
      expect(plan.map((h) => h.metin), everyElement(isNot(contains('serini'))));
    });

    test('seri yoksa genel metin yazar; ay sonunu doğru geçer', () {
      final plan = hatirlatmaPlani(simdi: tz.TZDateTime(istanbul, 2026, 11, 28, 9), seri: 0, bugunBitirdi: false);

      expect(plan.first.metin, 'Bugünün bulmacaları seni bekliyor 🔥');
      expect(plan.map((h) => h.id), [20261128, 20261129, 20261130, 20261201, 20261202, 20261203, 20261204]);
    });
  });

  group('Oyun bitince', () {
    test('bugünün hatırlatması silinir, bildirim izni ilk oyunda bir kez istenir', () async {
      final h = SahteHatirlatma();
      final sonu = OyunSonu(h, PuanlamaIstegi(BellekPuanlamaDeposu(), const BosPuanlamaPenceresi()));

      await sonu.oyunBitti(gunlukOyunTipi: 'kesisim_orta', skor: 6);
      await sonu.oyunBitti(gunlukOyunTipi: 'bingo', skor: 9);

      expect(h.bugunIptalSayisi, 2);
      expect(h.izinIstekSayisi, 1);
    });

    test('hatırlatma kapalıysa izin istenmez', () async {
      final h = SahteHatirlatma()..acik = false;

      await OyunSonu(h, PuanlamaIstegi(BellekPuanlamaDeposu(), const BosPuanlamaPenceresi())).oyunBitti(gunlukOyunTipi: 'top10', skor: 4);

      expect(h.izinIstekSayisi, 0);
    });

    test('oyun oynanırken bitince oyun sonu çalışır; açılışta değil', () async {
      final h = SahteHatirlatma();
      final c = ProviderContainer(overrides: [
        oyunDeposuProvider.overrideWithValue(SahteOyunDeposu()),
        hatirlatmaProvider.overrideWithValue(h),
      ]);
      addTearDown(c.dispose);
      const secim = (oyunTipi: 'kesisim_kolay', sure: null);
      c.listen(gameProvider(secim), (_, _) {});
      for (var i = 0; i < 100 && c.read(gameProvider(secim)).status == 'loading'; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(h.bugunIptalSayisi, 0);
      expect(h.izinIstekSayisi, 0);

      for (var i = 0; i < 5; i++) {
        await c.read(gameProvider(secim).notifier).makeGuess(const OyuncuOneri(id: 'o-1', isim: 'Arda Güler'));
      }
      await Future<void>.delayed(Duration.zero);

      expect(h.bugunIptalSayisi, 1);
      expect(h.izinIstekSayisi, 1);
    });
  });

  group('Ana menü', () {
    testWidgets('seri ana menünün üstünde yazmaz, oyunun kutucuğunda yazar; hatırlatmalar genel seriyle kurulur',
        (tester) async {
      final h = SahteHatirlatma();
      await anaMenuyuAc(tester, oynananlar: {'kesisim_orta': 6}, ekOverridelar: [
        seriProvider.overrideWith((ref) async => 6),
        seriOyunlarProvider.overrideWith((ref) async => {'kesisim': 4}),
        hatirlatmaProvider.overrideWithValue(h),
      ]);
      await tester.pump();

      expect(find.text('🔥 6 gün'), findsNothing);
      expect(find.text('🔥 4'), findsOneWidget);
      expect(h.planlar.last, (seri: 6, bugunBitirdi: true));
      await ekraniKapat(tester);
    });

    testWidgets('serisi olmayan oyunda seri yazmaz', (tester) async {
      await anaMenuyuAc(tester, ekOverridelar: [seriOyunlarProvider.overrideWith((ref) async => {})]);
      await tester.pump();

      expect(find.textContaining('🔥'), findsNothing);
      await ekraniKapat(tester);
    });
  });

  testWidgets('hesap sayfasında günlük hatırlatma kapatılıp açılabilir', (tester) async {
    final h = SahteHatirlatma();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(SahteAuthService()),
        kullaniciProvider.overrideWithValue(const KullaniciBilgisi(ad: 'Celal Test')),
        hatirlatmaProvider.overrideWithValue(h),
      ],
      child: MaterialApp(theme: uygulamaTemasi(), home: const ProfilScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Günlük hatırlatma'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isTrue);

    await tester.tap(find.text('Günlük hatırlatma'));
    await tester.pumpAndSettle();
    expect(h.acik, isFalse);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isFalse);

    await tester.tap(find.text('Günlük hatırlatma'));
    await tester.pumpAndSettle();
    expect(h.acik, isTrue);
    expect(h.izinIstekSayisi, 1);
  });
}
