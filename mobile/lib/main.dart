import 'dart:ui';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'providers/auth_provider.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'services/analitik.dart';
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

  // Uygulamayı Riverpod ProviderScope ile sarıp başlatıyoruz ki State yönetimi çalışsın
  runApp(ProviderScope(
    overrides: [
      if (firebaseAcik) analitikProvider.overrideWithValue(FirebaseAnalitik(FirebaseAnalytics.instance)),
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
      home: Consumer(
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
    );
  }
}
