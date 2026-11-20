import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<AuthResponse?> signInWithGoogle() async {
    // DİKKAT: Google Cloud Console'dan alacağın Web Client ID buraya gelecek!
    // Aksi takdirde butona basınca hiçbir şey olmaz veya hata fırlatır.
    const webClientId = '127593072442-q08tcvk37n4dd1o56fdehvu4lm5sdrsv.apps.googleusercontent.com'; 

    final GoogleSignIn googleSignIn = GoogleSignIn(
      serverClientId: webClientId,
    );
    
    final googleUser = await googleSignIn.signIn();
    if (googleUser == null) {
      throw 'Giriş iptal edildi.';
    }

    final googleAuth = await googleUser.authentication;
    final accessToken = googleAuth.accessToken;
    final idToken = googleAuth.idToken;

    if (accessToken == null || idToken == null) {
      throw 'Google giriş bilgileri alınamadı.';
    }

    return _supabase.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: accessToken,
    );
  }

  Future<void> signOut() async {
    final GoogleSignIn googleSignIn = GoogleSignIn();
    await googleSignIn.signOut();
    await _supabase.auth.signOut();
  }

  // Hesabı ve bütün oyun geçmişini sunucuda siler (hesabimi_sil, 033_hesabimi_sil.sql), sonra oturumu kapatır.
  // Sunucudaki silme başarısız olursa hata fırlatır ve oturum açık kalır.
  Future<void> hesabimiSil() async {
    await _supabase.rpc('hesabimi_sil');

    // Hesap silindi: Google'ın uygulamaya verdiği izin de geri alınır, bir sonraki girişte hesap yeniden seçilir.
    // Bunlar başarısız olsa da hesap silinmiştir; oturum cihazda mutlaka kapatılır.
    final googleSignIn = GoogleSignIn();
    try {
      await googleSignIn.disconnect();
    } catch (_) {
      try {
        await googleSignIn.signOut();
      } catch (_) {}
    }
    // Kullanıcı sunucuda artık yok: oturum sadece cihazda kapatılır
    await _supabase.auth.signOut(scope: SignOutScope.local);
  }
}
