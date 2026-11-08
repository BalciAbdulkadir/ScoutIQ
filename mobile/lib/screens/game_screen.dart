import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/game_provider.dart';
import '../services/gunluk_oyun.dart' show GunlukOyunSecimi;
import '../theme/renkler.dart';
import '../theme/yazi.dart';
import '../widgets/kulup_logosu.dart';
import '../widgets/oyun_mesaj_karti.dart';
import '../widgets/oyun_ortak.dart';
import '../widgets/oyuncu_arama.dart';
import '../widgets/tebesir.dart';

// Kesişim: iki kulübün ikisinde de oynamış bir oyuncuyu bulma oyunu
class GameScreen extends ConsumerStatefulWidget {
  // Oynanan zorluğun günlük oyunu: kesisim_kolay, kesisim_orta ya da kesisim_zor
  final String oyunTipi;
  final int? sure; // Seçilen süre, saniye; null: süresiz

  const GameScreen({super.key, required this.oyunTipi, this.sure});

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  GunlukOyunSecimi get _secim => (oyunTipi: widget.oyunTipi, sure: widget.sure);

  static const _maksimumSkor = 10;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gameProvider(_secim));

    return Scaffold(
      appBar: AppBar(title: const Text('KESİŞİM')),
      body: TahtaZemini(child: SafeArea(child: _govde(state))),
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
          onTekrarDene: () => ref.invalidate(gameProvider(_secim)),
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
            sayac: state.bitisZamani == null
                ? null
                : SureSayaci(
                    bitisZamani: state.bitisZamani!,
                    onBitti: ref.read(gameProvider(_secim).notifier).sureDoldu,
                  ),
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              if (zorluk != null) ...[OyunEtiketi(metin: zorluk.$1, renk: zorluk.$2), const SizedBox(width: 10)],
              const Expanded(
                child: Text(
                  'İki takımda da forma giymiş bir oyuncu bul',
                  style: TextStyle(color: Renkler.metinIkincil, fontSize: 14, height: 1.3),
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
            ara: ref.read(gameProvider(_secim).notifier).oyuncuAra,
            gonder: ref.read(gameProvider(_secim).notifier).makeGuess,
          ),
          const SizedBox(height: 16),
          _oncekiSonuc(state),
        ],
      ),
    );
  }

  (String, Color)? _zorluk(String? zorluk) => switch (zorluk) {
        'kolay' => ('Kolay', Renkler.kolay),
        'orta' => ('Orta', Renkler.orta),
        'zor' => ('Zor', Renkler.zor),
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
          Text(dogru ? 'Doğru' : 'Yanlış', style: Yazi.tebesir(16, renk: renk)),
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
      baslik: state.sureDoldu ? 'Süre doldu' : bitisBasligi(dogruSayisi, state.questions.length),
      renk: Renkler.kesisim,
      ozetSatirlari: [
        for (var i = 0; i < state.questions.length; i++)
          OzetSatiri(
            dogru: i < state.sonuclar.length ? state.sonuclar[i] : null,
            baslik: '${state.questions[i]['kulup_a']}  ×  ${state.questions[i]['kulup_b']}',
            altBaslik: i < state.cevaplar.length ? 'Cevabın: ${state.cevaplar[i]}' : 'Cevaplanmadı',
            // Doğru cevap yanlış bilinen ve süre dolduğu için cevaplanmayan sorularda gösterilir
            dogruCevap: (i < state.sonuclar.length && state.sonuclar[i]) ? null : state.ornekCevaplar[i],
          ),
      ],
    );
  }
}

// İki kulüp tahtada kesişen iki tebeşir dairesinin içinde; ortak oyuncu kesişimde aranır.
// Logolar dairelerin tam merkezinde, kulüp adları dairelerin altında, her biri kendi dairesine ortalı.
class _KulupEslesmesi extends StatelessWidget {
  final String kulupA;
  final String kulupB;
  final String? logoA;
  final String? logoB;

  const _KulupEslesmesi({required this.kulupA, required this.kulupB, this.logoA, this.logoB});

  // Yarıçap genişlikle büyür ama geniş ekranda (tablet) sınırlıdır; merkezler arası mesafe yarıçaptan biraz
  // kısa tutulur ki daireler ortada kesişsin
  static const _yaricapOrani = 0.26;
  static const _enBuyukYaricap = 100.0;
  static const _merkezUzakligiOrani = 0.88;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, kisitlar) {
        final genislik = kisitlar.maxWidth;
        final yaricap = (genislik * _yaricapOrani).clamp(0.0, _enBuyukYaricap);
        final ortaX = genislik / 2;
        final solX = ortaX - yaricap * _merkezUzakligiOrani;
        final sagX = ortaX + yaricap * _merkezUzakligiOrani;
        final logoBoyutu = (yaricap * 0.78).clamp(48.0, 76.0);
        // Çizginin kalınlığı kesilmesin diye dairelerin üstünde ve altında küçük pay
        const pay = 2.0;
        final merkezY = yaricap + pay;

        Widget logo(String? url, double merkezX) => Positioned(
              left: merkezX - logoBoyutu / 2,
              top: merkezY - logoBoyutu / 2,
              child: KulupLogosu(logoUrl: url, boyut: logoBoyutu, ikonRengi: Renkler.arkaPlan),
            );

        // Ad kutusu dairenin merkezine ortalı, iki kutu birbirine taşmaz
        final adGenisligi = (sagX - solX) - 8;
        Widget ad(String isim, double merkezX) => Positioned(
              left: merkezX - adGenisligi / 2,
              width: adGenisligi,
              top: 0,
              child: Text(
                isim,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Yazi.baslik(18, kalinlik: FontWeight.w800).copyWith(height: 1.05),
              ),
            );

        return Column(
          children: [
            SizedBox(
              width: genislik,
              height: 2 * merkezY,
              child: CustomPaint(
                painter: _VennCizeri(solX: solX, sagX: sagX, merkezY: merkezY, yaricap: yaricap),
                child: Stack(children: [logo(logoA, solX), logo(logoB, sagX)]),
              ),
            ),
            const SizedBox(height: 12),
            // İki satırlık isme yer: kısa isimde de yükseklik değişmez, alttaki içerik kaymaz
            SizedBox(
              width: genislik,
              height: 18 * 1.05 * 2 + 4,
              child: Stack(children: [ad(kulupA, solX), ad(kulupB, sagX)]),
            ),
          ],
        );
      },
    );
  }
}

class _VennCizeri extends CustomPainter {
  final double solX;
  final double sagX;
  final double merkezY;
  final double yaricap;

  const _VennCizeri({required this.solX, required this.sagX, required this.merkezY, required this.yaricap});

  @override
  void paint(Canvas canvas, Size size) {
    final kalem = Paint()
      ..color = Renkler.kenar
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    canvas.drawCircle(Offset(solX, merkezY), yaricap, kalem);
    canvas.drawCircle(Offset(sagX, merkezY), yaricap, kalem);

    // Kesişimde sarı kesik çizgi: oyuncunun yazılacağı yer
    final sari = Paint()
      ..color = Renkler.vurgu
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final ortaX = (solX + sagX) / 2;
    final yari = (yaricap * yaricap - (ortaX - solX) * (ortaX - solX));
    if (yari > 0) {
      final h = math.sqrt(yari) * 0.8;
      for (var y = merkezY - h; y < merkezY + h; y += 7) {
        canvas.drawLine(Offset(ortaX, y), Offset(ortaX, math.min(y + 3, merkezY + h)), sari);
      }
    }
  }

  @override
  bool shouldRepaint(_VennCizeri eski) =>
      eski.solX != solX || eski.sagX != sagX || eski.merkezY != merkezY || eski.yaricap != yaricap;
}
