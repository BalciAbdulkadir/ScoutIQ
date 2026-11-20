import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/models/puan.dart';
import 'package:mobile/providers/hub_provider.dart';
import 'package:mobile/screens/profil_screen.dart';
import 'package:mobile/services/auth_service.dart';
import 'package:mobile/services/oyun_deposu.dart';
import 'package:mobile/theme/tema.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthResponse;

import 'yardimcilar/sahte_oyun_deposu.dart';

// Supabase ve Google'a gitmeyen sahte servis: çağrıları sayar, istenirse hata verir
class SahteAuthService implements AuthService {
  int cikisSayisi = 0;
  int silmeSayisi = 0;
  bool silmeHataVerir = false;

  @override
  Future<AuthResponse?> signInWithGoogle() async => null;

  @override
  Future<void> signOut() async => cikisSayisi++;

  @override
  Future<void> hesabimiSil() async {
    if (silmeHataVerir) throw Exception('bağlantı yok');
    silmeSayisi++;
  }
}

Future<SahteAuthService> profiliAc(WidgetTester tester, {bool silmeHataVerir = false, List<Override> ek = const []}) async {
  final servis = SahteAuthService()..silmeHataVerir = silmeHataVerir;
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authServiceProvider.overrideWithValue(servis),
      kullaniciProvider.overrideWithValue(const KullaniciBilgisi(ad: 'Celal Test', eposta: 'test@ornek.com')),
      ...ek,
    ],
    // Ana sayfanın üstüne açılır: çıkış ve silmeden sonra ana sayfaya dönülmeli
    child: MaterialApp(
      theme: uygulamaTemasi(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const ProfilScreen())),
              child: const Text('ana sayfa'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('ana sayfa'));
  await tester.pumpAndSettle();
  return servis;
}

Future<void> dokun(WidgetTester tester, String metin) async {
  await tester.tap(find.text(metin).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('hesap sayfasında e-posta, gizlilik politikası, çıkış ve hesap silme var', (tester) async {
    await profiliAc(tester);

    expect(find.text('Celal Test'), findsOneWidget);
    expect(find.text('test@ornek.com'), findsOneWidget);
    expect(find.text('Gizlilik politikası'), findsOneWidget);
    expect(find.text('Çıkış yap'), findsOneWidget);
    expect(find.text('Hesabımı sil'), findsOneWidget);
    expect(gizlilikPolitikasiAdresi, startsWith('https://'));
  });

  testWidgets('çıkış onay sorar, vazgeçince oturum açık kalır', (tester) async {
    final servis = await profiliAc(tester);

    await dokun(tester, 'Çıkış yap');
    expect(find.text('Çıkış yapılsın mı?'), findsOneWidget);
    await dokun(tester, 'Vazgeç');

    expect(servis.cikisSayisi, 0);
    expect(find.byType(ProfilScreen), findsOneWidget);
  });

  testWidgets('çıkış onaylanınca oturum kapanır ve hesap sayfası kapanır', (tester) async {
    final servis = await profiliAc(tester);

    await dokun(tester, 'Çıkış yap');
    await dokun(tester, 'Çıkış yap');

    expect(servis.cikisSayisi, 1);
    expect(find.byType(ProfilScreen), findsNothing);
  });

  testWidgets('hesap silme iki kez onay ister, ilk adımda vazgeçince silinmez', (tester) async {
    final servis = await profiliAc(tester);

    await dokun(tester, 'Hesabımı sil');
    expect(find.text('Hesabın silinsin mi?'), findsOneWidget);
    expect(find.text('Tüm oyun geçmişin silinecek, geri alınamaz.'), findsOneWidget);
    await dokun(tester, 'Vazgeç');

    expect(servis.silmeSayisi, 0);
    expect(find.byType(ProfilScreen), findsOneWidget);
  });

  testWidgets('ikinci onayda vazgeçince hesap silinmez', (tester) async {
    final servis = await profiliAc(tester);

    await dokun(tester, 'Hesabımı sil');
    await dokun(tester, 'Devam');
    expect(find.text('Emin misin?'), findsOneWidget);
    await dokun(tester, 'Vazgeç');

    expect(servis.silmeSayisi, 0);
    expect(find.byType(ProfilScreen), findsOneWidget);
  });

  testWidgets('iki onaydan sonra hesap silinir ve hesap sayfası kapanır', (tester) async {
    final servis = await profiliAc(tester);

    await dokun(tester, 'Hesabımı sil');
    await dokun(tester, 'Devam');
    await dokun(tester, 'Hesabımı sil');

    expect(servis.silmeSayisi, 1);
    expect(find.byType(ProfilScreen), findsNothing);
  });

  testWidgets('silme başarısız olursa hata gösterilir, sayfa açık kalır', (tester) async {
    final servis = await profiliAc(tester, silmeHataVerir: true);

    await dokun(tester, 'Hesabımı sil');
    await dokun(tester, 'Devam');
    await dokun(tester, 'Hesabımı sil');

    expect(servis.silmeSayisi, 0);
    expect(find.textContaining('Hesap silinemedi'), findsOneWidget);
    expect(find.byType(ProfilScreen), findsOneWidget);
  });

  testWidgets('küçük ekranda taşma olmaz', (tester) async {
    tester.view.physicalSize = const Size(320, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await profiliAc(tester);

    expect(tester.takeException(), isNull);
  });

  testWidgets('takma ad satırı sıralamada görünen adı gösterir ve takma ad sayfasını açar', (tester) async {
    final depo = SahteOyunDeposu();
    await profiliAc(tester, ek: [oyunDeposuProvider.overrideWithValue(depo)]);

    expect(find.text('Takma ad'), findsOneWidget);
    expect(find.text('Oyuncu 3FA9 · sıralamada bu ad görünüyor'), findsOneWidget);
    await tester.tap(find.text('Takma ad'));
    await tester.pumpAndSettle();
    expect(find.text('TAKMA ADIN'), findsOneWidget);
  });

  testWidgets('7 gün dolmadıysa takma ad sayfası açılmaz, ne zaman değişebileceği yazar', (tester) async {
    final depo = SahteOyunDeposu()
      ..profil = Profil(takmaAd: 'kanarya_10', varsayilan: false, degistirilebilirTarih: DateTime(2099, 11, 28));
    await profiliAc(tester, ek: [oyunDeposuProvider.overrideWithValue(depo)]);

    await tester.tap(find.text('Takma ad'));
    await tester.pumpAndSettle();
    expect(find.text('TAKMA ADIN'), findsNothing);
    expect(find.text('Takma adını 28 Kasım tarihinde değiştirebilirsin.'), findsOneWidget);
  });
}
