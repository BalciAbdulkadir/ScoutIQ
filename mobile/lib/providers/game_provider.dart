import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/oyuncu_oneri.dart';
import 'hub_provider.dart';

class GameState {
  final String status; // 'loading', 'playing', 'completed', 'already_played', 'abandoned', 'no_game', 'error'
  final List<dynamic> questions;
  final int currentIndex;
  final int score;
  final String? lastGuessStatus;
  final String? gameId; // Oynanan oyunun Supabase ID'si
  final String? tarih; // Oyun günü (Türkiye saatine göre), kayıtlar bu tarihle atılır
  final bool gonderiliyor; // Cevap sunucuda kontrol edilirken ikinci gönderimi engeller
  final String? hataMesaji; // status 'error' iken gösterilir

  GameState({
    this.status = 'loading',
    this.questions = const [],
    this.currentIndex = 0,
    this.score = 0,
    this.lastGuessStatus,
    this.gameId,
    this.tarih,
    this.gonderiliyor = false,
    this.hataMesaji,
  });

  GameState copyWith({
    String? status,
    List<dynamic>? questions,
    int? currentIndex,
    int? score,
    String? lastGuessStatus,
    String? gameId,
    String? tarih,
    bool? gonderiliyor,
    String? hataMesaji,
  }) {
    return GameState(
      status: status ?? this.status,
      questions: questions ?? this.questions,
      currentIndex: currentIndex ?? this.currentIndex,
      score: score ?? this.score,
      lastGuessStatus: lastGuessStatus ?? this.lastGuessStatus,
      gameId: gameId ?? this.gameId,
      tarih: tarih ?? this.tarih,
      gonderiliyor: gonderiliyor ?? this.gonderiliyor,
      hataMesaji: hataMesaji ?? this.hataMesaji,
    );
  }
}

class GameNotifier extends Notifier<GameState> {
  static const _oyunTipi = 'kesisim';
  static const _puan = 2;

  final _supabase = Supabase.instance.client;

  @override
  GameState build() {
    // İlk kurulumda asenkron olarak veriyi başlatıyoruz
    _initGame();
    return GameState();
  }

  // Oyun günü telefonun saatinden değil sunucudan alınır, veritabanı kuralları da bu tarihe göre çalışır.
  // Sunucuya ulaşılamazsa aynı hesabı yapan yerel fonksiyona düşüyoruz.
  Future<String> _oyunTarihi() async {
    try {
      final tarih = await _supabase.rpc('bugunun_tarihi');
      if (tarih is String && tarih.isNotEmpty) return tarih;
    } catch (_) {}
    return bugununTarihi();
  }

  Future<Map<String, dynamic>?> _oyunKaydi(String userId, String tarih) {
    return _supabase
        .from('kullanici_oyun_gecmisi')
        .select('skor, durum')
        .eq('kullanici_id', userId)
        .eq('oyun_tipi', _oyunTipi)
        .eq('tarih', tarih)
        .maybeSingle();
  }

  // Daha önce atılmış kayda göre oyunu kilitler. Yarıda bırakılan oyun da tamamlandı sayılır.
  Future<void> _kayittanKilitle(Map<String, dynamic> kayit, String userId, String tarih) async {
    final skor = (kayit['skor'] as num?)?.toInt() ?? 0;

    if (kayit['durum'] == 'basladi') {
      // Kaydı kapatıyoruz ki yarım kalan oyunun skoru sonradan değiştirilemesin
      try {
        await _supabase
            .from('kullanici_oyun_gecmisi')
            .update({'durum': 'tamamlandi'})
            .eq('kullanici_id', userId)
            .eq('oyun_tipi', _oyunTipi)
            .eq('tarih', tarih)
            .eq('durum', 'basladi');
      } catch (_) {}
      if (!ref.mounted) return;
      state = state.copyWith(status: 'abandoned', score: skor);
      return;
    }

    state = state.copyWith(status: 'already_played', score: skor);
  }

  Future<void> _initGame() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        state = state.copyWith(status: 'error', hataMesaji: 'Oturumun kapanmış görünüyor. Lütfen tekrar giriş yap.');
        return;
      }

      final tarih = await _oyunTarihi();
      if (!ref.mounted) return;

      // 1. Kullanıcı bugün bu oyuna başlamış ya da bitirmiş mi?
      final kayit = await _oyunKaydi(userId, tarih);
      if (!ref.mounted) return;
      if (kayit != null) {
        await _kayittanKilitle(kayit, userId, tarih);
        return;
      }

      // 2. Bugünün oyununu çek
      final gameResponse = await _supabase
          .from('gunluk_oyunlar')
          .select()
          .eq('oyun_tipi', _oyunTipi)
          .eq('tarih', tarih)
          .limit(1)
          .maybeSingle();
      if (!ref.mounted) return;

      final questions = gameResponse?['soru_verisi'] as List<dynamic>?;
      if (gameResponse == null || questions == null || questions.isEmpty) {
        state = state.copyWith(status: 'no_game');
        return;
      }

      // 3. Oyun başlarken kaydı atıyoruz: oyun yarıda bırakılırsa bu kayıt tekrar oynamayı engeller
      try {
        await _supabase.from('kullanici_oyun_gecmisi').insert({
          'kullanici_id': userId,
          'oyun_id': gameResponse['id'],
          'oyun_tipi': _oyunTipi,
          'tarih': tarih,
          'skor': 0,
          'durum': 'basladi',
        });
      } on PostgrestException catch (e) {
        // 23505: aynı gün için kayıt zaten var (örneğin başka bir cihazda başlanmış)
        if (e.code != '23505') rethrow;
        final mevcut = await _oyunKaydi(userId, tarih);
        if (!ref.mounted) return;
        if (mevcut != null) {
          await _kayittanKilitle(mevcut, userId, tarih);
          return;
        }
        rethrow;
      }
      if (!ref.mounted) return;

      state = state.copyWith(
        status: 'playing',
        questions: questions,
        gameId: gameResponse['id'],
        tarih: tarih,
      );
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(
        status: 'error',
        hataMesaji: 'Oyun yüklenemedi. İnternet bağlantını kontrol edip tekrar dene.',
      );
    }
  }

  // Cevap kutusunun altındaki öneri listesi. Tüm oyuncular arasında arar, doğru cevabı ele vermez.
  Future<List<OyuncuOneri>> oyuncuAra(String metin) async {
    final sonuc = await _supabase.rpc('oyuncu_ara', params: {'p_arama': metin});
    return (sonuc as List<dynamic>)
        .map((satir) => OyuncuOneri.fromJson(satir as Map<String, dynamic>))
        .toList();
  }

  // Seçilen oyuncuyu sunucuda kontrol ettirir. Hata olursa mesajını döndürür, başarılıysa null.
  Future<String?> makeGuess(OyuncuOneri oyuncu) async {
    if (state.status != 'playing' || state.questions.isEmpty || state.gonderiliyor) return null;

    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return 'Oturumun kapanmış görünüyor. Lütfen tekrar giriş yap.';

    state = state.copyWith(gonderiliyor: true);

    try {
      final dogruMu = await _supabase.rpc('kesisim_cevap_kontrol', params: {
        'p_oyun_id': state.gameId,
        'p_soru_index': state.currentIndex,
        'p_oyuncu_id': oyuncu.id,
      });
      if (!ref.mounted) return null;

      final isCorrect = dogruMu == true;
      final newScore = isCorrect ? state.score + _puan : state.score;
      final nextIndex = state.currentIndex + 1;
      final bitti = nextIndex >= state.questions.length;

      // Skoru her cevaptan sonra kaydediyoruz, son soruda kaydı kilitliyoruz
      final guncellenen = await _supabase
          .from('kullanici_oyun_gecmisi')
          .update({'skor': newScore, 'durum': bitti ? 'tamamlandi' : 'basladi'})
          .eq('kullanici_id', userId)
          .eq('oyun_tipi', _oyunTipi)
          .eq('tarih', state.tarih!)
          .eq('durum', 'basladi')
          .select('skor');
      if (!ref.mounted) return null;

      if (guncellenen.isEmpty) {
        // Kayıt başka bir yerden kapatılmış: oyun artık oynanamaz
        state = state.copyWith(status: 'already_played', gonderiliyor: false);
        return null;
      }

      state = state.copyWith(
        status: bitti ? 'completed' : 'playing',
        currentIndex: bitti ? state.currentIndex : nextIndex,
        score: newScore,
        lastGuessStatus: isCorrect ? 'correct' : 'wrong',
        // Oyun bittiyse kilit açılmıyor: son soruda ikinci gönderim mümkün olmasın
        gonderiliyor: bitti,
      );
      return null;
    } catch (e) {
      if (!ref.mounted) return null;
      state = state.copyWith(gonderiliyor: false);
      return 'Cevap gönderilemedi. İnternet bağlantını kontrol edip tekrar dene.';
    }
  }
}

final gameProvider = NotifierProvider.autoDispose<GameNotifier, GameState>(() {
  return GameNotifier();
});
