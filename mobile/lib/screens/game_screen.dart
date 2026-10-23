import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/oyuncu_oneri.dart';
import '../providers/game_provider.dart';

class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key});

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  final TextEditingController _guessController = TextEditingController();

  // Öneri listesi: cevap sadece bu listeden seçilebilir
  List<OyuncuOneri> _oneriler = [];
  OyuncuOneri? _secilenOyuncu;
  bool _araniyor = false;
  Timer? _aramaZamanlayici;
  int _aramaNo = 0; // Geç gelen eski arama sonuçlarının yenilerinin üstüne yazılmasını engeller

  @override
  void dispose() {
    _aramaZamanlayici?.cancel();
    _guessController.dispose();
    super.dispose();
  }

  void _metinDegisti(String metin) {
    // Seçimden sonra metin değiştirilirse seçim geçersiz olur
    if (_secilenOyuncu != null && metin != _secilenOyuncu!.isim) {
      setState(() => _secilenOyuncu = null);
    }

    _aramaZamanlayici?.cancel();
    final arama = metin.trim();
    if (arama.length < 2 || _secilenOyuncu != null) {
      setState(() {
        _oneriler = [];
        _araniyor = false;
      });
      return;
    }

    setState(() => _araniyor = true);
    // Her tuşta sunucuya gitmemek için yazmanın bitmesini kısaca bekliyoruz
    _aramaZamanlayici = Timer(const Duration(milliseconds: 300), () => _ara(arama));
  }

  Future<void> _ara(String arama) async {
    final buArama = ++_aramaNo;
    try {
      final sonuc = await ref.read(gameProvider.notifier).oyuncuAra(arama);
      if (!mounted || buArama != _aramaNo) return;
      setState(() {
        _oneriler = sonuc;
        _araniyor = false;
      });
    } catch (_) {
      if (!mounted || buArama != _aramaNo) return;
      setState(() {
        _oneriler = [];
        _araniyor = false;
      });
    }
  }

  void _oyuncuSec(OyuncuOneri oyuncu) {
    _aramaZamanlayici?.cancel();
    _aramaNo++;
    _guessController.value = TextEditingValue(
      text: oyuncu.isim,
      selection: TextSelection.collapsed(offset: oyuncu.isim.length),
    );
    setState(() {
      _secilenOyuncu = oyuncu;
      _oneriler = [];
      _araniyor = false;
    });
  }

  Future<void> _gonder() async {
    final secilen = _secilenOyuncu;
    if (secilen == null) {
      _mesajGoster('Cevabını aşağıdaki listeden seçmelisin.');
      return;
    }

    final hata = await ref.read(gameProvider.notifier).makeGuess(secilen);
    if (!mounted) return;

    if (hata != null) {
      _mesajGoster(hata);
      return;
    }

    _guessController.clear();
    setState(() {
      _secilenOyuncu = null;
      _oneriler = [];
    });
  }

  void _mesajGoster(String mesaj) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mesaj)));
  }

  @override
  Widget build(BuildContext context) {
    final gameState = ref.watch(gameProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0A1C12),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Kesişim', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _buildBody(gameState),
    );
  }

  Widget _buildBody(GameState state) {
    if (state.status == 'loading') {
      return const Center(child: CircularProgressIndicator(color: Colors.greenAccent));
    }

    if (state.status == 'error') {
      return _buildMessageCard('Bir sorun oluştu', state.hataMesaji ?? 'Lütfen daha sonra tekrar dene.');
    }

    if (state.status == 'no_game') {
      return _buildMessageCard('Bugün için oyun bulunamadı.', 'Yarın tekrar gel veya veritabanını kontrol et.');
    }

    if (state.status == 'already_played') {
      return _buildMessageCard('Bugünkü Hakkını Doldurdun!', 'Skorun: ${state.score} / 10\nYarın yeni eşleşmelerle görüşmek üzere.');
    }

    if (state.status == 'abandoned') {
      return _buildMessageCard(
        'Bugünkü Hakkını Kullandın',
        'Oyunu yarıda bıraktığın için tamamlanmış sayıldı.\nSkorun: ${state.score} / 10\nYarın yeni eşleşmelerle görüşmek üzere.',
      );
    }

    if (state.status == 'completed') {
      return _buildMessageCard('Oyun Tamamlandı!', 'Günlük Skorun: ${state.score} / 10\nTebrikler!');
    }

    // Oynama Ekranı (playing)
    final currentQuestion = state.questions[state.currentIndex];
    final clubA = currentQuestion['kulup_a'] ?? 'Bilinmiyor';
    final clubB = currentQuestion['kulup_b'] ?? 'Bilinmiyor';
    final gonderilebilir = _secilenOyuncu != null && !state.gonderiliyor;

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
            enabled: !state.gonderiliyor,
            style: const TextStyle(color: Colors.white),
            textInputAction: TextInputAction.send,
            onChanged: _metinDegisti,
            onSubmitted: (_) => _gonder(),
            decoration: InputDecoration(
              hintText: 'Ortak oyuncuyu yazıp listeden seç...',
              hintStyle: const TextStyle(color: Colors.grey),
              filled: true,
              fillColor: const Color(0xFF132B1E),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide.none,
              ),
              prefixIcon: _secilenOyuncu != null
                  ? const Icon(Icons.check_circle, color: Colors.greenAccent)
                  : const Icon(Icons.search, color: Colors.grey),
              suffixIcon: state.gonderiliyor
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.greenAccent),
                      ),
                    )
                  : IconButton(
                      icon: Icon(Icons.send, color: gonderilebilir ? Colors.greenAccent : Colors.grey),
                      onPressed: gonderilebilir ? _gonder : null,
                    ),
            ),
          ),

          _buildOneriListesi(),

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

  Widget _buildOneriListesi() {
    if (_araniyor) {
      return const Padding(
        padding: EdgeInsets.only(top: 16),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.greenAccent),
        ),
      );
    }

    if (_secilenOyuncu != null || _guessController.text.trim().length < 2) {
      return const SizedBox.shrink();
    }

    if (_oneriler.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 12),
        child: Text('Bu isimde oyuncu bulunamadı.', style: TextStyle(color: Colors.white54)),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF132B1E),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        children: [
          for (final oyuncu in _oneriler)
            ListTile(
              dense: true,
              leading: const Icon(Icons.person, color: Colors.white54),
              title: Text(oyuncu.isim, style: const TextStyle(color: Colors.white, fontSize: 15)),
              onTap: () => _oyuncuSec(oyuncu),
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
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
            ),
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
