import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/izgara.dart';
import '../providers/izgara_provider.dart';
import '../theme/renkler.dart';
import '../widgets/kulup_logosu.dart';
import '../widgets/oyun_mesaj_karti.dart';
import '../widgets/oyun_ortak.dart';
import '../widgets/oyuncu_arama.dart';
import '../widgets/oyuncu_fotografi.dart';

// Izgara: satır ve sütun başlığının ikisine de uyan oyuncularla 3x3 tahtayı doldurma oyunu.
// Kullanıcı hücre seçmez; yazdığı oyuncu uyduğu boş hücreye sunucu tarafından yerleştirilir.
class IzgaraScreen extends ConsumerWidget {
  final IzgaraZorlugu zorluk;

  const IzgaraScreen({super.key, required this.zorluk});

  static Color zorlukRengi(IzgaraZorlugu zorluk) => switch (zorluk) {
        IzgaraZorlugu.kolay => Renkler.basari,
        IzgaraZorlugu.orta => Renkler.orta,
        IzgaraZorlugu.zor => Renkler.hata,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(izgaraProvider(zorluk));
    final oynaniyor = state.durum == IzgaraDurumu.oynaniyor;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Izgara'),
            const SizedBox(width: 10),
            OyunEtiketi(metin: zorluk.ad, renk: zorlukRengi(zorluk)),
          ],
        ),
        actions: [
          if (oynaniyor)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: state.gonderiliyor ? null : () => _pesEt(context, ref, state),
                style: TextButton.styleFrom(foregroundColor: Renkler.metinIkincil),
                icon: const Icon(Icons.flag_outlined, size: 18),
                label: const Text('Pes et'),
              ),
            ),
        ],
      ),
      body: SafeArea(child: _govde(context, ref, state)),
    );
  }

  Future<void> _pesEt(BuildContext context, WidgetRef ref, IzgaraState state) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Renkler.yuzey,
        title: const Text('Pes etmek istiyor musun?', style: TextStyle(color: Renkler.metin, fontSize: 18)),
        content: Text(
          'Oyun şu anki skorunla (${state.skor}/9) biter. Bugün bu tahtayı tekrar oynayamazsın.',
          style: const TextStyle(color: Renkler.metinIkincil, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Renkler.hata),
            child: const Text('Pes et'),
          ),
        ],
      ),
    );
    if (onay != true) return;

    final hata = await ref.read(izgaraProvider(zorluk).notifier).pesEt();
    if (hata != null && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(hata)));
    }
  }

  Widget _govde(BuildContext context, WidgetRef ref, IzgaraState state) {
    switch (state.durum) {
      case IzgaraDurumu.yukleniyor:
        return const Center(child: CircularProgressIndicator());
      case IzgaraDurumu.hata:
        return OyunMesajKarti(
          ikon: Icons.wifi_off_rounded,
          baslik: 'Bağlantı sorunu',
          aciklama: state.hataMesaji ?? 'Lütfen biraz sonra tekrar dene.',
          onTekrarDene: () => ref.invalidate(izgaraProvider(zorluk)),
        );
      case IzgaraDurumu.oyunYok:
        return const OyunMesajKarti(
          ikon: Icons.schedule_rounded,
          baslik: 'Bugünün tahtası henüz hazır değil',
          aciklama: 'Biraz sonra tekrar dene.',
        );
      case IzgaraDurumu.oynaniyor:
        return _oyun(ref, state);
      case IzgaraDurumu.bitti:
        return _bitis(context, state);
    }
  }

  Widget _oyun(WidgetRef ref, IzgaraState state) {
    final notifier = ref.read(izgaraProvider(zorluk).notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _HakGostergesi(kalanHak: state.kalanHak, skor: state.skor),
          const SizedBox(height: 20),
          OyuncuArama(
            renk: Renkler.izgara,
            gonderiliyor: state.gonderiliyor,
            ara: notifier.oyuncuAra,
            gonder: notifier.tahminEt,
          ),
          const SizedBox(height: 12),
          _SonTahmin(sonuc: state.sonTahmin, tahta: state.tahta!),
          const SizedBox(height: 16),
          IzgaraTahtasiGorunumu(state: state),
        ],
      ),
    );
  }

  Widget _bitis(BuildContext context, IzgaraState state) {
    final tamDolu = state.skor == izgaraBoyutu * izgaraBoyutu;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        const SizedBox(height: 8),
        Text(
          bitisBasligi(state.skor, izgaraBoyutu * izgaraBoyutu),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Renkler.metin, fontSize: 24, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '${state.skor}/9',
              style: const TextStyle(
                color: Renkler.izgara,
                fontSize: 44,
                fontWeight: FontWeight.w800,
                height: 1,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 8),
            const Text('kutu', style: TextStyle(color: Renkler.metinIkincil, fontSize: 16)),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          tamDolu ? 'Yeni tahta gece yarısı açılıyor.' : 'Boş kutularda örnek doğru cevaplar gösteriliyor.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Renkler.metinSoluk, fontSize: 14),
        ),
        const SizedBox(height: 20),
        IzgaraTahtasiGorunumu(state: state),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('Ana menüye dön', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

// Kalan tahmin hakkı (9 nokta) ve dolu kutu sayısı
class _HakGostergesi extends StatelessWidget {
  final int kalanHak;
  final int skor;

  const _HakGostergesi({required this.kalanHak, required this.skor});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < izgaraHakSayisi; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < kalanHak ? Renkler.izgara : Renkler.kenar,
            ),
          ),
        ],
        const SizedBox(width: 10),
        Text(
          '$kalanHak hak kaldı',
          style: const TextStyle(color: Renkler.metinIkincil, fontSize: 13, fontWeight: FontWeight.w500),
        ),
        const Spacer(),
        Text(
          '$skor/9 kutu',
          style: const TextStyle(color: Renkler.metin, fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

// Son tahminin sonucu: "Doğru · Arda Güler → Galatasaray × Fransa"
class _SonTahmin extends StatelessWidget {
  final IzgaraTahminSonucu? sonuc;
  final IzgaraTahtasi tahta;

  const _SonTahmin({required this.sonuc, required this.tahta});

  @override
  Widget build(BuildContext context) {
    final s = sonuc;
    if (s == null) {
      return const Text(
        'Satır ve sütundaki iki takımda da oynamış oyuncuları bul. Oyuncu uyduğu kutuya kendiliğinden yerleşir.',
        style: TextStyle(color: Renkler.metinSoluk, fontSize: 13, height: 1.4),
      );
    }

    final (ikon, renk, baslik, ayrinti) = switch (s) {
      IzgaraTahminSonucu(tekrar: true) => (
          Icons.info_rounded,
          Renkler.orta,
          'Zaten kullandın',
          '${s.oyuncuIsim} bu tahtada var, hak düşmedi',
        ),
      IzgaraTahminSonucu(dogru: true, hucre: final hucre?) => (
          Icons.check_circle_rounded,
          Renkler.basari,
          'Doğru',
          '${s.oyuncuIsim} → ${tahta.satiri(hucre).isim} × ${tahta.sutunu(hucre).isim}',
        ),
      _ => (
          Icons.cancel_rounded,
          Renkler.hata,
          'Yanlış',
          '${s.oyuncuIsim} boş kutuların hiçbirine uymuyor',
        ),
    };

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: Row(
        key: ValueKey(s),
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

// 3x3 tahta: üstte sütun başlıkları, solda satır başlıkları
class IzgaraTahtasiGorunumu extends StatelessWidget {
  final IzgaraState state;

  const IzgaraTahtasiGorunumu({super.key, required this.state});

  static const _bosluk = 6.0;

  @override
  Widget build(BuildContext context) {
    final tahta = state.tahta!;

    return LayoutBuilder(
      builder: (context, kisitlar) {
        // Başlık sütunu hücrelerden biraz dar; hücreler kare
        final hucre = (kisitlar.maxWidth - 3 * _bosluk) / 3.8;
        final baslikGenisligi = kisitlar.maxWidth - 3 * hucre - 3 * _bosluk;

        Widget satir(Widget bas, List<Widget> hucreler, double yukseklik) => SizedBox(
              height: yukseklik,
              child: Row(
                children: [
                  SizedBox(width: baslikGenisligi, child: bas),
                  for (final h in hucreler) ...[const SizedBox(width: _bosluk), SizedBox(width: hucre, child: h)],
                ],
              ),
            );

        return Column(
          children: [
            satir(
              const SizedBox.shrink(),
              [for (final b in tahta.sutunlar) _Baslik(baslik: b, logoBoyutu: hucre * 0.48)],
              hucre * 0.95,
            ),
            for (var s = 0; s < izgaraBoyutu; s++) ...[
              const SizedBox(height: _bosluk),
              satir(
                _Baslik(baslik: tahta.satirlar[s], logoBoyutu: hucre * 0.48),
                [
                  for (var t = 0; t < izgaraBoyutu; t++)
                    _Hucre(
                      oyuncu: state.hucreler[s * izgaraBoyutu + t],
                      ornekCevap: state.ornekCevaplar[s * izgaraBoyutu + t],
                    ),
                ],
                hucre,
              ),
            ],
          ],
        );
      },
    );
  }
}

// Kulüp ya da milli takım başlığı: logo ve altında isim
class _Baslik extends StatelessWidget {
  final IzgaraBasligi baslik;
  final double logoBoyutu;

  const _Baslik({required this.baslik, required this.logoBoyutu});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        KulupLogosu(
          logoUrl: baslik.logoUrl,
          boyut: logoBoyutu,
          yedekIkon: baslik.milli ? Icons.flag_rounded : Icons.shield_outlined,
        ),
        const SizedBox(height: 6),
        Text(
          baslik.isim,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Renkler.metin, fontSize: 11, fontWeight: FontWeight.w600, height: 1.15),
        ),
      ],
    );
  }
}

// Tahtadaki bir kutu: boş, oyuncuyla dolu ya da (oyun bittiyse) örnek cevaplı
class _Hucre extends StatelessWidget {
  final IzgaraOyuncusu? oyuncu;
  final String? ornekCevap;

  const _Hucre({this.oyuncu, this.ornekCevap});

  @override
  Widget build(BuildContext context) {
    final dolu = oyuncu != null;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: dolu ? Renkler.izgara.withValues(alpha: 0.10) : Renkler.yuzey,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: dolu ? Renkler.izgara.withValues(alpha: 0.7) : Renkler.kenar),
      ),
      child: LayoutBuilder(
        builder: (context, kisitlar) {
          final kenar = kisitlar.maxWidth;
          if (oyuncu != null) return _OyuncuIcerigi(oyuncu: oyuncu!, kenar: kenar);
          if (ornekCevap != null) return _OrnekIcerik(isim: ornekCevap!);
          return const SizedBox.expand();
        },
      ),
    );
  }
}

// Dolu kutu: fotoğraf kırpılmadan üstte, isim altta
class _OyuncuIcerigi extends StatelessWidget {
  final IzgaraOyuncusu oyuncu;
  final double kenar;

  const _OyuncuIcerigi({required this.oyuncu, required this.kenar});

  @override
  Widget build(BuildContext context) {
    // Fotoğraf kutunun üst üçte ikisinde, kırpılmadan; altta iki satır isme yer kalır
    final fotoGenisligi = kenar * 0.62 * OyuncuFotografi.enBoyOrani;

    return TweenAnimationBuilder<double>(
      key: ValueKey(oyuncu.isim),
      tween: Tween(begin: 0.6, end: 1),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutBack,
      builder: (context, olcek, child) => Transform.scale(scale: olcek, child: child),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 5, 4, 4),
        child: Column(
          children: [
            OyuncuFotografi(isim: oyuncu.isim, fotoUrl: oyuncu.fotoUrl, boyut: fotoGenisligi, harfRengi: Renkler.izgara),
            const Spacer(),
            Text(
              oyuncu.isim,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Renkler.metin, fontSize: 10.5, fontWeight: FontWeight.w600, height: 1.1),
            ),
          ],
        ),
      ),
    );
  }
}

// Oyun bitince boş kalan kutu: örnek doğru cevap soluk renkte
class _OrnekIcerik extends StatelessWidget {
  final String isim;

  const _OrnekIcerik({required this.isim});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.lightbulb_outline_rounded, color: Renkler.metinSoluk, size: 16),
          const SizedBox(height: 4),
          Text(
            isim,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Renkler.metinIkincil, fontSize: 10.5, height: 1.15),
          ),
        ],
      ),
    );
  }
}
