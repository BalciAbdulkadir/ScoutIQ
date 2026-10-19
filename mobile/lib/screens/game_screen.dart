import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/game_provider.dart';

class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key});

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  final TextEditingController _guessController = TextEditingController();

  @override
  void dispose() {
    _guessController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gameState = ref.watch(gameProvider);
    final gameNotifier = ref.read(gameProvider.notifier);

    return Scaffold(
      backgroundColor: const Color(0xFF0A1C12),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Kesişim', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _buildBody(gameState, gameNotifier),
    );
  }

  Widget _buildBody(GameState state, GameNotifier notifier) {
    if (state.status == 'loading') {
      return const Center(child: CircularProgressIndicator(color: Colors.greenAccent));
    }

    if (state.status == 'no_game') {
      return _buildMessageCard('Bugün için oyun bulunamadı.', 'Yarın tekrar gel veya veritabanını kontrol et.');
    }

    if (state.status == 'already_played') {
      return _buildMessageCard('Bugünkü Hakkını Doldurdun!', 'Skorun: ${state.score} / 10\nYarın yeni eşleşmelerle görüşmek üzere.');
    }

    if (state.status == 'completed') {
      return _buildMessageCard('Oyun Tamamlandı!', 'Günlük Skorun: ${state.score} / 10\nTebrikler!');
    }

    // Oynama Ekranı (playing)
    final currentQuestion = state.questions[state.currentIndex];
    final clubA = currentQuestion['kulup_a'] ?? 'Bilinmiyor';
    final clubB = currentQuestion['kulup_b'] ?? 'Bilinmiyor';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Soru: ${state.currentIndex + 1} / ${state.questions.length}',
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
              Text(
                'Skor: ${state.score}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.greenAccent),
              ),
            ],
          ),
          const SizedBox(height: 40),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildClubCard(clubA),
              const Text('X', style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: Colors.grey)),
              _buildClubCard(clubB),
            ],
          ),
          
          const SizedBox(height: 60),
          
          TextField(
            controller: _guessController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Ortak oyuncuyu yazın...',
              hintStyle: const TextStyle(color: Colors.grey),
              filled: true,
              fillColor: const Color(0xFF132B1E),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide.none,
              ),
              suffixIcon: IconButton(
                icon: const Icon(Icons.send, color: Colors.greenAccent),
                onPressed: () {
                  if (_guessController.text.isNotEmpty) {
                    notifier.makeGuess(_guessController.text);
                    _guessController.clear();
                  }
                },
              ),
            ),
            onSubmitted: (value) {
              if (value.isNotEmpty) {
                notifier.makeGuess(value);
                _guessController.clear();
              }
            },
          ),
          
          const SizedBox(height: 30),
          
          if (state.lastGuessStatus != null)
            Text(
              state.lastGuessStatus == 'correct' ? 'Önceki Soru: Doğru (+2)' : 'Önceki Soru: Yanlış',
              style: TextStyle(
                fontSize: 16,
                color: state.lastGuessStatus == 'correct' ? Colors.greenAccent : Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildClubCard(String clubName) {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Center(
        child: Text(
          clubName.length > 15 ? '${clubName.substring(0, 12)}...' : clubName,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildMessageCard(String title, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.sports_score, size: 80, color: Colors.greenAccent),
            const SizedBox(height: 20),
            Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 10),
            Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: Colors.white70)),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent),
              child: const Text('Ana Menüye Dön', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            )
          ],
        ),
      ),
    );
  }
}
