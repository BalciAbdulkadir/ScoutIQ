import 'dart:async';

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
  final int? sure; // Yeni başlanan tahtanın süresi (saniye); yarım kalan tahtada sunucudaki süre kullanılır

  const IzgaraScreen({super.key, required this.zorluk, this.sure});

  IzgaraAcilisi get _acilis => (zorluk: zorluk, sure: sure);

  static Color zorlukRengi(IzgaraZorlugu zorluk) => switch (zorluk) {
        IzgaraZorlugu.kolay => Renkler.basari,
        IzgaraZorlugu.orta => Renkler.orta,
        IzgaraZorlugu.zor => Renkler.hata,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(izgaraProvider(_acilis));
    final oynaniyor = state.durum == IzgaraDurumu.oynaniyor;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            // Dar ekranlarda "Pes et" butonuna yer kalsın diye isim kısalabilir
            const Flexible(child: Text('Izgara', overflow: TextOverflow.ellipsis)),
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

    final hata = await ref.read(izgaraProvider(_acilis).notifier).pesEt();
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
          onTekrarDene: () => ref.invalidate(izgaraProvider(_acilis)),
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
    final notifier = ref.read(izgaraProvider(_acilis).notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Ilerleme(tahminSayisi: state.tahminSayisi, skor: state.skor),
          if (state.bitisZamani != null) ...[
            const SizedBox(height: 14),
            _GeriSayim(
              bitisZamani: state.bitisZamani!,
              toplamSaniye: state.sureSaniye ?? 90,
              onBitti: notifier.sureDoldu,
            ),
          ],
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
          state.sureDoldu ? 'Süre doldu' : bitisBasligi(state.skor, izgaraBoyutu * izgaraBoyutu),
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

// Süreli tahtada kalan süre: sayı ve azalan çubuk. Son 10 saniyede kırmızıya döner.
// Süre cihaz saatine göre sayılır; asıl kontrol sunucudadır, bu sayaç sadece gösterir ve süre dolunca haber verir.
class _GeriSayim extends StatefulWidget {
  final DateTime bitisZamani;
  final int toplamSaniye;
  final VoidCallback onBitti;

  const _GeriSayim({required this.bitisZamani, required this.toplamSaniye, required this.onBitti});

  @override
  State<_GeriSayim> createState() => _GeriSayimState();
}

class _GeriSayimState extends State<_GeriSayim> {
  Timer? _zamanlayici;
  late Duration _kalan = _hesapla();

  Duration _hesapla() {
    final kalan = widget.bitisZamani.difference(DateTime.now());
    return kalan.isNegative ? Duration.zero : kalan;
  }

  @override
  void initState() {
    super.initState();
    // Çubuk akıcı azalsın diye saniyede birkaç kez güncellenir
    _zamanlayici = Timer.periodic(const Duration(milliseconds: 200), (_) {
      setState(() => _kalan = _hesapla());
      // Tahmin gönderilirken süre dolarsa bildirim reddedilir; sayaç sıfırda kaldıkça tekrar denenir
      if (_kalan == Duration.zero) widget.onBitti();
    });
  }

  @override
  void dispose() {
    _zamanlayici?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final saniye = (_kalan.inMilliseconds / 1000).ceil();
    final azKaldi = saniye <= 10;
    final renk = azKaldi ? Renkler.hata : Renkler.izgara;
    final oran = widget.toplamSaniye == 0 ? 0.0 : (_kalan.inMilliseconds / (widget.toplamSaniye * 1000)).clamp(0.0, 1.0);

    return Row(
      children: [
        Icon(Icons.timer_outlined, color: renk, size: 18),
        const SizedBox(width: 8),
        SizedBox(
          width: 44,
          child: Text(
            '${saniye ~/ 60}:${(saniye % 60).toString().padLeft(2, '0')}',
            style: TextStyle(
              color: renk,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: oran,
              minHeight: 6,
              color: renk,
              backgroundColor: Renkler.kenar,
            ),
          ),
        ),
      ],
    );
  }
}

// Dolu kutular (9 nokta) ve yapılan tahmin sayısı
class _Ilerleme extends StatelessWidget {
  final int tahminSayisi;
  final int skor;

  const _Ilerleme({required this.tahminSayisi, required this.skor});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < izgaraBoyutu * izgaraBoyutu; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < skor ? Renkler.izgara : Renkler.kenar,
            ),
          ),
        ],
        const SizedBox(width: 10),
        Text(
          '$skor/9 kutu',
          style: const TextStyle(color: Renkler.metin, fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const Spacer(),
        Text(
          '$tahminSayisi tahmin',
          style: const TextStyle(color: Renkler.metinIkincil, fontSize: 13, fontWeight: FontWeight.w500),
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
          '${s.oyuncuIsim} bu tahtada zaten var',
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
  final IzgaraOyuncusu? ornekCevap; // Oyun bitince boş kalan kutuda gösterilen doğru cevap

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
          if (ornekCevap != null) return _OyuncuIcerigi(oyuncu: ornekCevap!, kenar: kenar, ornek: true);
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
  final bool ornek; // Kullanıcının bulamadığı örnek cevap: soluk gösterilir

  const _OyuncuIcerigi({required this.oyuncu, required this.kenar, this.ornek = false});

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
            Opacity(
              opacity: ornek ? 0.55 : 1,
              child: OyuncuFotografi(
                isim: oyuncu.isim,
                fotoUrl: oyuncu.fotoUrl,
                boyut: fotoGenisligi,
                harfRengi: ornek ? Renkler.metinSoluk : Renkler.izgara,
              ),
            ),
            const Spacer(),
            Text(
              oyuncu.isim,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: ornek ? Renkler.metinIkincil : Renkler.metin,
                fontSize: 10.5,
                fontWeight: ornek ? FontWeight.w500 : FontWeight.w600,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
