import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/oyuncu_oneri.dart';
import '../services/oyun_deposu.dart';
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
  static const _oturumYokMesaji = 'Oturumun kapanmış görünüyor. Lütfen tekrar giriş yap.';

  late OyunDeposu _depo;

  @override
  GameState build() {
    _depo = ref.read(oyunDeposuProvider);
    // Veriyi build bittikten sonra yüklüyoruz: _initGame state'i hemen değiştirirse (örneğin oturum yoksa)
    // build'in döndürdüğü başlangıç durumu o değişikliğin üzerine yazmasın
    Future.microtask(_initGame);
    return GameState();
  }

  // Oyun günü telefonun saatinden değil sunucudan alınır, veritabanı kuralları da bu tarihe göre çalışır.
  // Sunucuya ulaşılamazsa aynı hesabı yapan yerel fonksiyona düşüyoruz.
  Future<String> _oyunTarihi() async {
    try {
      return await _depo.oyunTarihi();
    } catch (_) {
      return bugununTarihi();
    }
  }

  // Daha önce atılmış kayda göre oyunu kilitler. Yarıda bırakılan oyun da tamamlandı sayılır.
  Future<void> _kayittanKilitle(Map<String, dynamic> kayit, String userId, String tarih) async {
    final skor = (kayit['skor'] as num?)?.toInt() ?? 0;

    if (kayit['durum'] == 'basladi') {
      // Kaydı kapatıyoruz ki yarım kalan oyunun skoru sonradan değiştirilemesin
      try {
        await _depo.yarimKaydiKapat(userId, _oyunTipi, tarih);
      } catch (_) {}
      if (!ref.mounted) return;
      state = state.copyWith(status: 'abandoned', score: skor);
      return;
    }

    state = state.copyWith(status: 'already_played', score: skor);
  }

  Future<void> _initGame() async {
    try {
      final userId = _depo.kullaniciId;
      if (userId == null) {
        state = state.copyWith(status: 'error', hataMesaji: _oturumYokMesaji);
        return;
      }

      final tarih = await _oyunTarihi();
      if (!ref.mounted) return;

      // 1. Kullanıcı bugün bu oyuna başlamış ya da bitirmiş mi?
      final kayit = await _depo.oyunKaydi(userId, _oyunTipi, tarih);
      if (!ref.mounted) return;
      if (kayit != null) {
        await _kayittanKilitle(kayit, userId, tarih);
        return;
      }

      // 2. Bugünün oyununu çek
      final oyun = await _depo.gununOyunu(_oyunTipi, tarih);
      if (!ref.mounted) return;

      final questions = oyun?['soru_verisi'] as List<dynamic>?;
      if (oyun == null || questions == null || questions.isEmpty) {
        state = state.copyWith(status: 'no_game');
        return;
      }

      // 3. Oyun başlarken kaydı atıyoruz: oyun yarıda bırakılırsa bu kayıt tekrar oynamayı engeller
      try {
        await _depo.kayitAc(kullaniciId: userId, oyunId: oyun['id'], oyunTipi: _oyunTipi, tarih: tarih);
      } on KayitZatenVar {
        final mevcut = await _depo.oyunKaydi(userId, _oyunTipi, tarih);
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
        gameId: oyun['id'],
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
  Future<List<OyuncuOneri>> oyuncuAra(String metin) => _depo.oyuncuAra(metin);

  // Seçilen oyuncuyu sunucuda kontrol ettirir. Hata olursa mesajını döndürür, başarılıysa null.
  Future<String?> makeGuess(OyuncuOneri oyuncu) async {
    if (state.status != 'playing' || state.questions.isEmpty || state.gonderiliyor) return null;

    final userId = _depo.kullaniciId;
    if (userId == null) return _oturumYokMesaji;

    state = state.copyWith(gonderiliyor: true);

    try {
      final isCorrect = await _depo.kesisimCevapKontrol(
        oyunId: state.gameId!,
        soruIndex: state.currentIndex,
        oyuncuId: oyuncu.id,
      );
      if (!ref.mounted) return null;

      final newScore = isCorrect ? state.score + _puan : state.score;
      final nextIndex = state.currentIndex + 1;
      final bitti = nextIndex >= state.questions.length;

      // Skoru her cevaptan sonra kaydediyoruz, son soruda kaydı kilitliyoruz
      final yazildi = await _depo.skorYaz(
        kullaniciId: userId,
        oyunTipi: _oyunTipi,
        tarih: state.tarih!,
        skor: newScore,
        bitti: bitti,
      );
      if (!ref.mounted) return null;

      if (!yazildi) {
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
