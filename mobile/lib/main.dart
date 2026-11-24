import 'dart:ui';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'providers/auth_provider.dart';
import 'screens/guncelleme_screen.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'services/analitik.dart';
import 'services/hata_kaydi.dart';
import 'services/hatirlatma.dart';
import 'services/puanlama.dart';
import 'theme/tema.dart';

// Supabase proje kimlik bilgileri
const String supabaseUrl = 'https://lixufwybouylmaxeigpy.supabase.co';
const String supabaseAnonKey = 'sb_publishable_xhDtRHqO7jGZ_foxKyUYAw_73Li9Pim';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Supabase'i başlatıyoruz
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

  final firebaseAcik = await _firebaseBaslat();
  final Analitik analitik = firebaseAcik ? FirebaseAnalitik(FirebaseAnalytics.instance) : const BosAnalitik();
  // Oyun açılırken ya da hamlede gelen beklenmeyen hatalar Crashlytics'e ölümcül olmayan hata olarak gider
  final HataKaydi hataKaydi = firebaseAcik ? CrashlyticsHataKaydi(FirebaseCrashlytics.instance) : const BosHataKaydi();

  // Akşam hatırlatması. Bildirime dokunularak açılınca analitiğe bildirim_acildi gider.
  // Eklenti açılamazsa uygulama hatırlatmasız çalışır.
  Hatirlatma? hatirlatma;
  try {
    final yerel = YerelHatirlatma(FlutterLocalNotificationsPlugin());
    await yerel.baslat(acildi: analitik.bildirimAcildi);
    hatirlatma = yerel;
  } catch (_) {}

  // Uygulamayı Riverpod ProviderScope ile sarıp başlatıyoruz ki State yönetimi çalışsın
  runApp(ProviderScope(
    overrides: [
      analitikProvider.overrideWithValue(analitik),
      hataKaydiProvider.overrideWithValue(hataKaydi),
      if (hatirlatma != null) hatirlatmaProvider.overrideWithValue(hatirlatma),
      puanlamaProvider.overrideWithValue(PuanlamaIstegi(YerelPuanlamaDeposu(), const PlayPuanlamaPenceresi())),
    ],
    child: const FootyLoreApp(),
  ));
}

// Firebase'i açar: çökmeler Crashlytics'e gider (debug derlemede gitmez). Ayar dosyası (google-services.json)
// yoksa ya da açılamazsa uygulama Firebase'siz çalışır, analitik olaylar gönderilmez. Firebase açıldıysa true.
Future<bool> _firebaseBaslat() async {
  try {
    await Firebase.initializeApp();
  } catch (_) {
    return false;
  }

  final crashlytics = FirebaseCrashlytics.instance;
  await crashlytics.setCrashlyticsCollectionEnabled(!kDebugMode);
  if (!kDebugMode) {
    // Flutter'ın yakaladığı hatalar ve Flutter dışında (zamanlayıcı, platform kanalı) kalan hatalar
    FlutterError.onError = crashlytics.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (hata, iz) {
      crashlytics.recordError(hata, iz, fatal: true);
      return true;
    };
  }
  return true;
}

class FootyLoreApp extends StatelessWidget {
  const FootyLoreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FootyLore',
      debugShowCheckedModeBanner: false,
      theme: uygulamaTemasi(),
      // Önce sürüm kontrolü (zorunlu güncelleme), sonra giriş
      home: SurumKapisi(
        child: Consumer(
          builder: (context, ref, child) {
            final authState = ref.watch(authStateProvider);

            return authState.when(
              data: (data) {
                final session = data.session;
                if (session != null) {
                  // Giriş başarılıysa Hub (HomeScreen) ekranına gidiyoruz!
                  return const HomeScreen();
                }
                return const LoginScreen();
              },
              loading: () => const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              ),
              error: (error, stack) => Scaffold(
                body: Center(child: Text('Hata: $error')),
              ),
            );
          },
        ),
      ),
    );
  }
}
