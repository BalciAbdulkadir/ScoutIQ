import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/bingo.dart';
import '../providers/bingo_provider.dart';
import '../services/gunluk_oyun.dart';
import '../theme/renkler.dart';
import '../theme/yazi.dart';
import '../widgets/kulup_logosu.dart';
import '../widgets/oyun_mesaj_karti.dart';
import '../widgets/oyun_ortak.dart';
import '../widgets/oyuncu_fotografi.dart';
import '../widgets/tebesir.dart';

// Bingo: destedeki oyuncular sırayla gelir; kullanıcı her oyuncuyu uyduğu kutuya koyar ya da pas geçer.
// Yanlış kutuya konan oyuncu gitmez, başka kutu denenebilir; oyuncu sadece pas geçilince gider. Amaç 12 kutuyu doldurmak.
class BingoScreen extends ConsumerWidget {
  // Günlük oyunun tipi. Bingo'nun zorluk modu yoktur: 'bingo'
  final String oyunTipi;
  // Ana menüde seçilen süre (saniye; null: süresiz). Sadece yeni başlanan oyunda kullanılır.
  final int? sure;

  const BingoScreen({super.key, this.oyunTipi = 'bingo', this.sure});

  GunlukOyunSecimi get _secim => (oyunTipi: oyunTipi, sure: sure);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(bingoProvider(_secim));
    final oynaniyor = state.durum == BingoDurumu.oynaniyor;

    return Scaffold(
      appBar: AppBar(
        title: const Text('BİNGO'),
        actions: [
          if (oynaniyor)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: state.gonderiliyor ? null : () => _pesEt(context, ref, state),
                style: TextButton.styleFrom(
                  foregroundColor: Renkler.metinIkincil,
                  textStyle: Yazi.tebesir(16, kalinlik: FontWeight.w400),
                ),
                icon: const Icon(Icons.flag_outlined, size: 18),
                label: const Text('Pes et'),
              ),
            ),
        ],
      ),
      body: TahtaZemini(child: SafeArea(child: _govde(context, ref, state))),
    );
  }

  Future<void> _pesEt(BuildContext context, WidgetRef ref, BingoState state) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pes etmek istiyor musun?'),
        content: Text('Oyun şu anki skorunla (${state.skor}/${state.kart!.hucreSayisi}) biter. Bugün Bingo\'yu tekrar oynayamazsın.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(foregroundColor: Renkler.metinIkincil),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Renkler.hata),
            child: const Text('Pes et'),
          ),
        ],
      ),
    );
    if (onay != true) return;

    final hata = await ref.read(bingoProvider(_secim).notifier).pesEt();
    if (hata != null && context.mounted) _mesajGoster(context, hata);
  }

  void _mesajGoster(BuildContext context, String mesaj) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mesaj)));
  }

  Widget _govde(BuildContext context, WidgetRef ref, BingoState state) {
    switch (state.durum) {
      case BingoDurumu.yukleniyor:
        return const Center(child: CircularProgressIndicator());
      case BingoDurumu.hata when state.hataMesaji == baskaZorlukMesaji:
        return const OyunMesajKarti(
          ikon: Icons.lock_clock_rounded,
          baslik: 'Bugünkü hakkını kullandın',
          aciklama: baskaZorlukMesaji,
        );
      case BingoDurumu.hata:
        return OyunMesajKarti(
          ikon: Icons.wifi_off_rounded,
          baslik: 'Bağlantı sorunu',
          aciklama: state.hataMesaji ?? 'Lütfen biraz sonra tekrar dene.',
          onTekrarDene: () => ref.invalidate(bingoProvider(_secim)),
        );
      case BingoDurumu.oyunYok:
        return const OyunMesajKarti(
          ikon: Icons.schedule_rounded,
          baslik: 'Bugünün kartı henüz hazır değil',
          aciklama: 'Biraz sonra tekrar dene.',
        );
      case BingoDurumu.oynaniyor:
        return _oyun(context, ref, state);
      case BingoDurumu.bitti:
        return _bitis(context, state);
    }
  }

  Widget _oyun(BuildContext context, WidgetRef ref, BingoState state) {
    final notifier = ref.read(bingoProvider(_secim).notifier);
    final oyuncu = state.siradaki;

    Future<void> hamle(Future<String?> islem) async {
      final hata = await islem;
      if (hata != null && context.mounted) _mesajGoster(context, hata);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  '${state.kalanOyuncu} oyuncu kaldı',
                  overflow: TextOverflow.ellipsis,
                  style: Yazi.tebesir(15, renk: Renkler.metinIkincil, kalinlik: FontWeight.w400),
                ),
              ),
              const Spacer(),
              if (state.bitisZamani != null) ...[
                SureSayaci(bitisZamani: state.bitisZamani!, onBitti: notifier.sureDoldu),
                const SizedBox(width: 12),
              ],
              Text('${state.skor}/${state.kart!.hucreSayisi} kutu', style: Yazi.tebesir(16)),
            ],
          ),
          const SizedBox(height: 14),
          if (oyuncu != null)
            _SiradakiOyuncu(
              oyuncu: oyuncu,
              gonderiliyor: state.gonderiliyor,
              onPas: () => hamle(notifier.pasGec()),
            ),
          const SizedBox(height: 10),
          _SonHamle(hamle: state.sonHamle, kart: state.kart!),
          const SizedBox(height: 14),
          BingoKartiGorunumu(
            state: state,
            onKutu: state.gonderiliyor ? null : (h) => hamle(notifier.yerlestir(h)),
          ),
        ],
      ),
    );
  }

  Widget _bitis(BuildContext context, BingoState state) {
    final kutuSayisi = state.kart!.hucreSayisi;
    final tamDolu = state.skor == kutuSayisi;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const SizedBox(height: 8),
        Text(
          Yazi.buyuk(state.sureDoldu ? 'Süre doldu' : (tamDolu ? 'Bingo!' : bitisBasligi(state.skor, kutuSayisi))),
          textAlign: TextAlign.center,
          style: Yazi.baslik(34, kalinlik: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('${state.skor}/$kutuSayisi', style: Yazi.tebesir(52, renk: Renkler.vurgu)),
            const SizedBox(width: 8),
            Text('kutu', style: Yazi.tebesir(18, renk: Renkler.metinIkincil, kalinlik: FontWeight.w400)),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          tamDolu ? 'Yeni kart gece yarısı açılıyor.' : 'Boş kutularda desteden uyan bir oyuncu gösteriliyor.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Renkler.metinSoluk, fontSize: 14),
        ),
        const SizedBox(height: 20),
        BingoKartiGorunumu(state: state),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          child: const Text('Ana menüye dön'),
        ),
      ],
    );
  }
}

// Sırası gelen oyuncu: fotoğraf, isim ve pas butonu
class _SiradakiOyuncu extends StatelessWidget {
  final BingoOyuncusu oyuncu;
  final bool gonderiliyor;
  final VoidCallback onPas;

  const _SiradakiOyuncu({required this.oyuncu, required this.gonderiliyor, required this.onPas});

  @override
  Widget build(BuildContext context) {
    return TebesirKutusu(
      kenarRengi: Renkler.vurgu,
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(
        children: [
          OyuncuFotografi(isim: oyuncu.isim, fotoUrl: oyuncu.fotoUrl, boyut: 52),
          const SizedBox(width: 12),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: Column(
                key: ValueKey(oyuncu.isim),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(oyuncu.isim, style: Yazi.tebesir(22), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  const Text('Uyduğu kutuya dokun', style: TextStyle(color: Renkler.metinSoluk, fontSize: 13)),
                ],
              ),
            ),
          ),
          TextButton(
            onPressed: gonderiliyor ? null : onPas,
            style: TextButton.styleFrom(foregroundColor: Renkler.metinIkincil, textStyle: Yazi.tebesir(17)),
            child: const Text('Pas'),
          ),
        ],
      ),
    );
  }
}

// Son hamlenin sonucu: "Doğru · Arda Güler → Galatasaray"
class _SonHamle extends StatelessWidget {
  final SonBingoHamlesi? hamle;
  final BingoKarti kart;

  const _SonHamle({required this.hamle, required this.kart});

  @override
  Widget build(BuildContext context) {
    final h = hamle;
    if (h == null) {
      return const Text(
        'Gelen oyuncuyu uyduğu kategorinin kutusuna koy. Yanlış kutuda oyuncu gitmez, başka kutu deneyebilirsin. '
        'Uyan kutu yoksa pas geç.',
        style: TextStyle(color: Renkler.metinSoluk, fontSize: 13, height: 1.4),
      );
    }

    final (ikon, renk, baslik, ayrinti) = switch (h) {
      (hucre: null, dogru: _, oyuncu: _) => (Icons.skip_next_rounded, Renkler.metinIkincil, 'Pas', '${h.oyuncu.isim} geçildi'),
      (dogru: true, hucre: final hucre?, oyuncu: _) => (
          Icons.check_circle_rounded,
          Renkler.basari,
          'Doğru',
          '${h.oyuncu.isim} → ${kart.hucreler[hucre].isim}',
        ),
      (hucre: final hucre?, dogru: false, oyuncu: _) => (
          Icons.cancel_rounded,
          Renkler.hata,
          'Yanlış',
          '${h.oyuncu.isim} ${kart.hucreler[hucre].isim} kutusuna uymuyor, başka kutu dene',
        ),
    };

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: Row(
        key: ValueKey(h),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ikon, color: renk, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: baslik, style: TextStyle(color: renk, fontWeight: FontWeight.w700)),
                TextSpan(text: '  ·  $ayrinti', style: const TextStyle(color: Renkler.metinIkincil)),
              ]),
              style: const TextStyle(fontSize: 14, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}

// Kart: 4 satır, 3 sütun (eski kartlarda 4x4). onKutu doluysa boş kutulara dokunulabilir.
class BingoKartiGorunumu extends StatelessWidget {
  final BingoState state;
  final void Function(int hucre)? onKutu;

  const BingoKartiGorunumu({super.key, required this.state, this.onKutu});

  static const _bosluk = 6.0;

  @override
  Widget build(BuildContext context) {
    final kart = state.kart!;

    return LayoutBuilder(
      builder: (context, kisitlar) {
        final sutun = kart.sutunSayisi;
        final kenar = (kisitlar.maxWidth - (sutun - 1) * _bosluk) / sutun;
        // Üç sütunda kutular geniş olduğu için biraz basık tutulur, kart ekrana sığsın
        final yukseklik = kenar * (sutun == 3 ? 0.88 : 1.1);
        return Column(
          children: [
            for (var s = 0; s < kart.satirSayisi; s++) ...[
              if (s > 0) const SizedBox(height: _bosluk),
              Row(
                children: [
                  for (var t = 0; t < sutun; t++) ...[
                    if (t > 0) const SizedBox(width: _bosluk),
                    SizedBox(
                      width: kenar,
                      height: yukseklik,
                      child: _Kutu(
                        kategori: kart.hucreler[s * sutun + t],
                        oyuncu: state.hucreler[s * sutun + t],
                        ornekCevap: state.ornekCevaplar[s * sutun + t],
                        yanlis: state.yanlisKutu == s * sutun + t,
                        onTap: onKutu == null || state.hucreler.containsKey(s * sutun + t)
                            ? null
                            : () => onKutu!(s * sutun + t),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

// Karttaki bir kutu: boşken kategori, dolunca oyuncu; oyun bittiyse boş kutuda soluk örnek cevap
class _Kutu extends StatelessWidget {
  final BingoKategorisi kategori;
  final BingoOyuncusu? oyuncu;
  final BingoOyuncusu? ornekCevap;
  final bool yanlis; // Sıradaki oyuncu az önce bu kutuya yanlış kondu
  final VoidCallback? onTap;

  const _Kutu({required this.kategori, this.oyuncu, this.ornekCevap, this.yanlis = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final dolu = oyuncu != null;

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            color: dolu
                ? Renkler.basari.withValues(alpha: 0.10)
                : (yanlis ? Renkler.hata.withValues(alpha: 0.10) : null),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: dolu ? Renkler.basari : (yanlis ? Renkler.hata : Renkler.kenar), width: 1.5),
          ),
          padding: const EdgeInsets.all(4),
          child: LayoutBuilder(
            builder: (context, kisitlar) {
              final kenar = kisitlar.maxWidth;
              if (oyuncu != null) return _OyuncuIcerigi(oyuncu: oyuncu!, kategori: kategori, kenar: kenar);
              if (ornekCevap != null) return _OyuncuIcerigi(oyuncu: ornekCevap!, kategori: kategori, kenar: kenar, ornek: true);
              return _KategoriIcerigi(kategori: kategori, kenar: kenar);
            },
          ),
        ),
      ),
    );
  }
}

class _KategoriIcerigi extends StatelessWidget {
  final BingoKategorisi kategori;
  final double kenar;

  const _KategoriIcerigi({required this.kategori, required this.kenar});

  @override
  Widget build(BuildContext context) {
    // Kulüp logosu, bayrak, lig ya da kupa logosu; logosu olmayan kategoride (ör. Ballon d'Or) türünün simgesi
    final simge = KulupLogosu(
      logoUrl: kategori.logoUrl,
      boyut: kenar * 0.38,
      yedekIkon: switch (kategori.tip) {
        BingoKategoriTipi.kulup => Icons.shield_outlined,
        BingoKategoriTipi.milli => Icons.flag_rounded,
        BingoKategoriTipi.lig => Icons.stadium_rounded,
        BingoKategoriTipi.basari => Icons.emoji_events_rounded,
      },
    );

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        simge,
        const SizedBox(height: 4),
        Flexible(
          child: Text(
            kategori.isim,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Yazi.baslik(11.5, kalinlik: FontWeight.w700).copyWith(height: 1.05),
          ),
        ),
        Text(
          kategori.aciklama,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Renkler.metinSoluk, fontSize: 9.5),
        ),
      ],
    );
  }
}

// Dolu kutu: oyuncunun fotoğrafı ve ismi, altında kategori
class _OyuncuIcerigi extends StatelessWidget {
  final BingoOyuncusu oyuncu;
  final BingoKategorisi kategori;
  final double kenar;
  final bool ornek; // Kullanıcının dolduramadığı kutuda örnek cevap: soluk gösterilir

  const _OyuncuIcerigi({required this.oyuncu, required this.kategori, required this.kenar, this.ornek = false});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(oyuncu.isim),
      tween: Tween(begin: 0.6, end: 1),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutBack,
      builder: (context, olcek, child) => Transform.scale(scale: olcek, child: child),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Opacity(
            opacity: ornek ? 0.55 : 1,
            child: OyuncuFotografi(
              isim: oyuncu.isim,
              fotoUrl: oyuncu.fotoUrl,
              boyut: kenar * 0.42 * OyuncuFotografi.enBoyOrani,
              harfRengi: ornek ? Renkler.metinSoluk : Renkler.vurgu,
            ),
          ),
          const SizedBox(height: 3),
          Flexible(
            child: Text(
              oyuncu.isim,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Yazi.tebesir(
                11.5,
                renk: ornek ? Renkler.metinSoluk : Renkler.metin,
                kalinlik: ornek ? FontWeight.w400 : FontWeight.w700,
              ).copyWith(height: 1.0),
            ),
          ),
          Text(
            kategori.isim,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Renkler.metinSoluk, fontSize: 9),
          ),
        ],
      ),
    );
  }
}
