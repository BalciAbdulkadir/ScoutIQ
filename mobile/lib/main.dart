import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'providers/auth_provider.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';

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

  // Uygulamayı Riverpod ProviderScope ile sarıp başlatıyoruz ki State yönetimi çalışsın
  runApp(const ProviderScope(child: ScoutIQApp()));
}

class ScoutIQApp extends StatelessWidget {
  const ScoutIQApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ScoutIQ',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green.shade800,
          brightness: Brightness.dark, // Futbol temasına karanlık mod yakışır
        ),
        useMaterial3: true,
      ),
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
