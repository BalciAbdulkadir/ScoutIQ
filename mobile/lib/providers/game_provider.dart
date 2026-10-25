import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/oyuncu_oneri.dart';
import '../services/gunluk_oyun.dart';
import '../services/oyun_deposu.dart';

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
  final List<bool> sonuclar; // Cevaplanan soruların doğru/yanlış sonucu (ilerleme çubuğu ve özet için)
  final List<String> cevaplar; // Cevaplanan sorularda seçilen oyuncular (özet için)
  final Map<int, String> ornekCevaplar; // Oyun bitince sunucudan gelen örnek doğru cevaplar: soru index'i -> oyuncu

  GameState({
    this.sonuclar = const [],
    this.cevaplar = const [],
    this.ornekCevaplar = const {},
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
    List<bool>? sonuclar,
    List<String>? cevaplar,
    Map<int, String>? ornekCevaplar,
  }) {
    return GameState(
      sonuclar: sonuclar ?? this.sonuclar,
      cevaplar: cevaplar ?? this.cevaplar,
      ornekCevaplar: ornekCevaplar ?? this.ornekCevaplar,
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

  late OyunDeposu _depo;

  @override
  GameState build() {
    _depo = ref.read(oyunDeposuProvider);
    // Veriyi build bittikten sonra yüklüyoruz: _initGame state'i hemen değiştirirse (örneğin oturum yoksa)
    // build'in döndürdüğü başlangıç durumu o değişikliğin üzerine yazmasın
    Future.microtask(_initGame);
    return GameState();
  }

  Future<void> _initGame() async {
    try {
      final acilis = await gunlukOyunuAc(_depo, _oyunTipi);
      if (!ref.mounted) return;

      state = switch (acilis) {
        Oynanabilir(:final oyunId, :final sorular, :final tarih) =>
          state.copyWith(status: 'playing', questions: sorular, gameId: oyunId, tarih: tarih),
        ZatenOynandi(:final skor) => state.copyWith(status: 'already_played', score: skor),
        YaridaBirakildi(:final skor) => state.copyWith(status: 'abandoned', score: skor),
        OyunYok() => state.copyWith(status: 'no_game'),
        OturumYok() => state.copyWith(status: 'error', hataMesaji: oturumYokMesaji),
      };
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(status: 'error', hataMesaji: yuklemeHataMesaji);
    }
  }

  // Cevap kutusunun altındaki öneri listesi. Tüm oyuncular arasında arar, doğru cevabı ele vermez.
  Future<List<OyuncuOneri>> oyuncuAra(String metin) => _depo.oyuncuAra(metin);

  // Seçilen oyuncuyu sunucuda kontrol ettirir. Hata olursa mesajını döndürür, başarılıysa null.
  Future<String?> makeGuess(OyuncuOneri oyuncu) async {
    if (state.status != 'playing' || state.questions.isEmpty || state.gonderiliyor) return null;

    final userId = _depo.kullaniciId;
    if (userId == null) return oturumYokMesaji;

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
        sonuclar: [...state.sonuclar, isCorrect],
        cevaplar: [...state.cevaplar, oyuncu.isim],
        // Oyun bittiyse kilit açılmıyor: son soruda ikinci gönderim mümkün olmasın
        gonderiliyor: bitti,
      );
    } catch (e) {
      if (!ref.mounted) return null;
      state = state.copyWith(gonderiliyor: false);
      return gonderimHataMesaji;
    }

    // Bitiş ekranı açıldı; yanlış cevap varsa özette gösterilecek doğru cevapları getiriyoruz
    if (state.status == 'completed' && state.sonuclar.contains(false)) {
      await _ornekCevaplariYukle();
    }
    return null;
  }

  // Örnek doğru cevaplar özete ek bilgidir: gelmezse özet yine gösterilir, hata kullanıcıya yansıtılmaz
  Future<void> _ornekCevaplariYukle() async {
    try {
      final ornekler = await _depo.kesisimOrnekCevaplar(state.gameId!);
      if (!ref.mounted) return;
      state = state.copyWith(ornekCevaplar: ornekler);
    } catch (_) {}
  }
}

final gameProvider = NotifierProvider.autoDispose<GameNotifier, GameState>(() {
  return GameNotifier();
});
