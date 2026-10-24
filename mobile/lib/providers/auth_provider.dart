import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';

// Servisi tüm uygulamaya sunan provider
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

// Supabase'in anlık oturum durumunu dinleyen stream provider
final authStateProvider = StreamProvider<AuthState>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange;
});
