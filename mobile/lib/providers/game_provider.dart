import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class GameState {
  final String status; // 'loading', 'playing', 'completed', 'already_played', 'no_game'
  final List<dynamic> questions;
  final int currentIndex;
  final int score;
  final String? lastGuessStatus; 
  final String? gameId; // Oynanan oyunun Supabase ID'si

  GameState({
    this.status = 'loading',
    this.questions = const [],
    this.currentIndex = 0,
    this.score = 0,
    this.lastGuessStatus,
    this.gameId,
  });

  GameState copyWith({
    String? status,
    List<dynamic>? questions,
    int? currentIndex,
    int? score,
    String? lastGuessStatus,
    String? gameId,
  }) {
    return GameState(
      status: status ?? this.status,
      questions: questions ?? this.questions,
      currentIndex: currentIndex ?? this.currentIndex,
      score: score ?? this.score,
      lastGuessStatus: lastGuessStatus, // null gelebilsin diye bilerek ?? koymadık
      gameId: gameId ?? this.gameId,
    );
  }
}

class GameNotifier extends Notifier<GameState> {
  final _supabase = Supabase.instance.client;

  @override
  GameState build() {
    // İlk kurulumda asenkron olarak veriyi başlatıyoruz
    _initGame();
    return GameState();
  }

  Future<void> _initGame() async {
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final userId = _supabase.auth.currentUser?.id;

      if (userId == null) throw 'Kullanıcı bulunamadı';

      // 1. Kullanıcı bugün bu oyunu oynamış mı kontrolü
      final historyResponse = await _supabase
          .from('kullanici_oyun_gecmisi')
          .select()
          .eq('kullanici_id', userId)
          .eq('oyun_tipi', 'kesisim')
          .eq('tarih', today)
          .maybeSingle();

      if (historyResponse != null) {
        state = state.copyWith(status: 'already_played', score: historyResponse['skor']);
        return;
      }

      // 2. Bugünün oyununu çek
      final gameResponse = await _supabase
          .from('gunluk_oyunlar')
          .select()
          .eq('oyun_tipi', 'kesisim')
          .eq('tarih', today)
          .maybeSingle();

      if (gameResponse == null || gameResponse['soru_verisi'] == null) {
        state = state.copyWith(status: 'no_game');
        return;
      }

      final questions = gameResponse['soru_verisi'] as List<dynamic>;
      
      if (questions.isEmpty) {
        state = state.copyWith(status: 'no_game');
        return;
      }

      state = state.copyWith(
        status: 'playing',
        questions: questions,
        gameId: gameResponse['id'],
      );
    } catch (e) {
      state = state.copyWith(status: 'no_game');
    }
  }

  Future<void> makeGuess(String playerName) async {
    if (state.status != 'playing' || state.questions.isEmpty) return;

    final guess = playerName.trim().toLowerCase();
    
    // TODO: Gerçek doğrulamayı (Supabase RPC) buraya bağlayacağız. 
    // Şimdilik sistemin 5 soru akışını test etmek için her inputu doğru kabul edip 2 puan verelim.
    bool isCorrect = guess.isNotEmpty; 
    
    final newScore = isCorrect ? state.score + 2 : state.score;
    final nextIndex = state.currentIndex + 1;

    if (nextIndex >= state.questions.length) {
      // Oyun bitti, skoru kaydet ve kilitle
      await _saveResult(newScore);
      state = state.copyWith(
        status: 'completed',
        score: newScore,
        lastGuessStatus: isCorrect ? 'correct' : 'wrong',
      );
    } else {
      // Sonraki soruya geç
      state = state.copyWith(
        currentIndex: nextIndex,
        score: newScore,
        lastGuessStatus: isCorrect ? 'correct' : 'wrong',
      );
    }
  }

  Future<void> _saveResult(int finalScore) async {
    final userId = _supabase.auth.currentUser?.id;
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    if (userId != null && state.gameId != null) {
      await _supabase.from('kullanici_oyun_gecmisi').insert({
        'kullanici_id': userId,
        'oyun_id': state.gameId,
        'oyun_tipi': 'kesisim',
        'tarih': today,
        'skor': finalScore,
        'durum': 'tamamlandi'
      });
    }
  }
}

final gameProvider = NotifierProvider.autoDispose<GameNotifier, GameState>(() {
  return GameNotifier();
});
