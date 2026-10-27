import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/oyuncu_oneri.dart';
import '../providers/game_provider.dart';
import '../theme/renkler.dart';
import '../widgets/oyun_mesaj_karti.dart';
import '../widgets/oyun_ortak.dart';
import '../widgets/oyuncu_fotografi.dart';

// Kesişim: iki kulübün ikisinde de oynamış bir oyuncuyu bulma oyunu
class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key});

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  static const _maksimumSkor = 10;

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
      _mesajGoster('Cevabını listeden seçmelisin.');
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
          ),
          const SizedBox(height: 20),
          _cevapAlani(state),
          _oneriListesi(),
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

  Widget _cevapAlani(GameState state) {
    final gonderilebilir = _secilenOyuncu != null && !state.gonderiliyor;

    OutlineInputBorder kenarlik(Color renk) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: renk),
        );

    return TextField(
      controller: _guessController,
      enabled: !state.gonderiliyor,
      style: const TextStyle(color: Renkler.metin, fontSize: 16),
      cursorColor: Renkler.kesisim,
      textInputAction: TextInputAction.send,
      textCapitalization: TextCapitalization.words,
      onChanged: _metinDegisti,
      onSubmitted: (_) => _gonder(),
      decoration: InputDecoration(
        hintText: 'Oyuncu ara',
        hintStyle: const TextStyle(color: Renkler.metinSoluk),
        filled: true,
        fillColor: Renkler.yuzey,
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        enabledBorder: kenarlik(_secilenOyuncu != null ? Renkler.kesisim : Renkler.kenar),
        focusedBorder: kenarlik(Renkler.kesisim),
        disabledBorder: kenarlik(Renkler.kenar),
        prefixIcon: _secilenOyuncu != null
            ? const Icon(Icons.check_circle, color: Renkler.kesisim, size: 22)
            : const Icon(Icons.search_rounded, color: Renkler.metinSoluk),
        suffixIcon: state.gonderiliyor
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : IconButton(
                tooltip: 'Gönder',
                icon: Icon(Icons.send, color: gonderilebilir ? Renkler.kesisim : Renkler.metinSoluk),
                onPressed: gonderilebilir ? _gonder : null,
              ),
      ),
    );
  }

  Widget _oneriListesi() {
    if (_araniyor) {
      return const Padding(
        padding: EdgeInsets.only(top: 16),
        child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }

    if (_secilenOyuncu != null || _guessController.text.trim().length < 2) {
      return const SizedBox.shrink();
    }

    if (_oneriler.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 14, left: 4),
        child: Text('Bu isimde oyuncu bulunamadı.', style: TextStyle(color: Renkler.metinSoluk)),
      );
    }

    // Renk Material'da: ListTile dokunma efektini en yakın Material'a çizer, renkli bir kutu onu gizlerdi
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: Renkler.yuzey,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var i = 0; i < _oneriler.length; i++) ...[
              if (i > 0) const Divider(indent: 16, endIndent: 16),
              ListTile(
                dense: true,
                leading: OyuncuFotografi(isim: _oneriler[i].isim, fotoUrl: _oneriler[i].fotoUrl, boyut: 36),
                title: Text(_oneriler[i].isim, style: const TextStyle(color: Renkler.metin, fontSize: 15)),
                trailing: const Icon(Icons.north_west_rounded, size: 16, color: Renkler.metinSoluk),
                onTap: () => _oyuncuSec(_oneriler[i]),
              ),
            ],
          ],
        ),
      ),
    );
  }

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

  const _KulupEslesmesi({required this.kulupA, required this.kulupB});

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
          Expanded(child: _Kulup(isim: kulupA)),
          const VsRozeti(),
          Expanded(child: _Kulup(isim: kulupB)),
        ],
      ),
    );
  }
}

class _Kulup extends StatelessWidget {
  final String isim;

  const _Kulup({required this.isim});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: const BoxDecoration(color: Renkler.yuzeyYuksek, shape: BoxShape.circle),
          child: const Icon(Icons.shield_outlined, color: Renkler.kesisim, size: 28),
        ),
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
