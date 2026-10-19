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
}
