import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/game_provider.dart';
import '../theme/renkler.dart';
import '../widgets/kulup_logosu.dart';
import '../widgets/oyun_mesaj_karti.dart';
import '../widgets/oyun_ortak.dart';
import '../widgets/oyuncu_arama.dart';

// Kesişim: iki kulübün ikisinde de oynamış bir oyuncuyu bulma oyunu
class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key});

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  static const _maksimumSkor = 10;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gameProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Kesişim')),
      body: SafeArea(child: _govde(state)),
    );
  }

  Widget _govde(GameState state) {
    switch (state.status) {
      case 'loading':
        return const Center(child: CircularProgressIndicator());
      case 'error':
        return OyunMesajKarti(
          ikon: Icons.wifi_off_rounded,
          baslik: 'Bağlantı sorunu',
          aciklama: state.hataMesaji ?? 'Lütfen biraz sonra tekrar dene.',
          onTekrarDene: () => ref.invalidate(gameProvider),
        );
      case 'no_game':
        return const OyunMesajKarti(
          ikon: Icons.schedule_rounded,
          baslik: 'Bugünün oyunu henüz hazır değil',
          aciklama: 'Biraz sonra tekrar dene.',
        );
      case 'already_played':
        return OyunMesajKarti(
          ikon: Icons.check_circle_outline_rounded,
          baslik: 'Bugünkü oyununu oynadın',
          aciklama: 'Skorun: ${state.score}/$_maksimumSkor\nYeni oyun gece yarısı açılıyor.',
        );
      case 'abandoned':
        return OyunMesajKarti(
          ikon: Icons.lock_outline_rounded,
          baslik: 'Bugünkü hakkını kullandın',
          aciklama: 'Oyundan çıktığın için oyun tamamlanmış sayıldı.\nSkorun: ${state.score}/$_maksimumSkor',
        );
      case 'completed':
        return _bitis(state);
      default:
        return _oyun(state);
    }
  }

  Widget _oyun(GameState state) {
    final soru = state.questions[state.currentIndex] as Map<String, dynamic>;
    final zorluk = _zorluk(soru['zorluk'] as String?);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OyunIlerlemesi(
            soruSayisi: state.questions.length,
            mevcutSoru: state.currentIndex,
            sonuclar: state.sonuclar,
            renk: Renkler.kesisim,
            sagMetin: '${state.score} puan',
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              if (zorluk != null) ...[OyunEtiketi(metin: zorluk.$1, renk: zorluk.$2), const SizedBox(width: 10)],
              const Expanded(
                child: Text(
                  'İki takımda da forma giymiş bir oyuncu bul',
                  style: TextStyle(color: Renkler.metinIkincil, fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _KulupEslesmesi(
            kulupA: soru['kulup_a'] as String? ?? '—',
            kulupB: soru['kulup_b'] as String? ?? '—',
            logoA: soru['kulup_a_logo'] as String?,
            logoB: soru['kulup_b_logo'] as String?,
          ),
          const SizedBox(height: 20),
          OyuncuArama(
            renk: Renkler.kesisim,
            gonderiliyor: state.gonderiliyor,
            ara: ref.read(gameProvider.notifier).oyuncuAra,
            gonder: ref.read(gameProvider.notifier).makeGuess,
          ),
          const SizedBox(height: 16),
          _oncekiSonuc(state),
        ],
      ),
    );
  }

  (String, Color)? _zorluk(String? zorluk) => switch (zorluk) {
        'kolay' => ('Kolay', Renkler.basari),
        'orta' => ('Orta', const Color(0xFFFBBF24)),
        'zor' => ('Zor', Renkler.hata),
        _ => null,
      };

  // Bir önceki sorunun sonucu: "Doğru · Arda Güler"
  Widget _oncekiSonuc(GameState state) {
    if (state.sonuclar.isEmpty) return const SizedBox.shrink();

    final dogru = state.sonuclar.last;
    final renk = dogru ? Renkler.basari : Renkler.hata;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: Row(
        key: ValueKey(state.sonuclar.length),
        children: [
          Icon(dogru ? Icons.check_circle_rounded : Icons.cancel_rounded, color: renk, size: 18),
          const SizedBox(width: 8),
          Text(
            dogru ? 'Doğru' : 'Yanlış',
            style: TextStyle(color: renk, fontWeight: FontWeight.w700, fontSize: 14),
          ),
          Expanded(
            child: Text(
              '  ·  ${state.cevaplar.last}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Renkler.metinIkincil, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bitis(GameState state) {
    final dogruSayisi = state.sonuclar.where((s) => s).length;

    return OyunBitisEkrani(
      skor: '${state.score}/$_maksimumSkor',
      skorAciklamasi: 'puan',
      baslik: bitisBasligi(dogruSayisi, state.questions.length),
      renk: Renkler.kesisim,
      ozetSatirlari: [
        for (var i = 0; i < state.questions.length; i++)
          OzetSatiri(
            dogru: i < state.sonuclar.length ? state.sonuclar[i] : null,
            baslik: '${state.questions[i]['kulup_a']}  ×  ${state.questions[i]['kulup_b']}',
            altBaslik: i < state.cevaplar.length ? 'Cevabın: ${state.cevaplar[i]}' : null,
            // Doğru cevap sadece yanlış bilinen sorularda gösterilir
            dogruCevap: (i < state.sonuclar.length && !state.sonuclar[i]) ? state.ornekCevaplar[i] : null,
          ),
      ],
    );
  }
}

// İki kulüp tek kartta, aralarında VS rozeti
class _KulupEslesmesi extends StatelessWidget {
  final String kulupA;
  final String kulupB;
  final String? logoA;
  final String? logoB;

  const _KulupEslesmesi({required this.kulupA, required this.kulupB, this.logoA, this.logoB});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      decoration: BoxDecoration(
        color: Renkler.yuzey,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Renkler.kenar),
      ),
      child: Row(
        children: [
          Expanded(child: _Kulup(isim: kulupA, logoUrl: logoA)),
          const VsRozeti(),
          Expanded(child: _Kulup(isim: kulupB, logoUrl: logoB)),
        ],
      ),
    );
  }
}

class _Kulup extends StatelessWidget {
  final String isim;
  final String? logoUrl;

  const _Kulup({required this.isim, this.logoUrl});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        KulupLogosu(logoUrl: logoUrl, ikonRengi: Renkler.kesisim),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            isim,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Renkler.metin, fontSize: 15, fontWeight: FontWeight.w700, height: 1.25),
          ),
        ),
      ],
    );
  }
}
