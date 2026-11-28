import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/izgara.dart';
import '../models/oyuncu_oneri.dart';
import '../providers/izgara_provider.dart';
import '../theme/renkler.dart';
import '../theme/yazi.dart';
import '../widgets/puan_karti.dart';
import '../widgets/kulup_logosu.dart';
import '../widgets/oyun_mesaj_karti.dart';
import '../widgets/oyun_ortak.dart';
import '../widgets/oyuncu_arama.dart';
import '../widgets/oyuncu_fotografi.dart';
import '../widgets/tebesir.dart';
import '../widgets/oyun_kurallari.dart';
import '../services/analitik.dart';
import '../services/paylasim.dart';
import '../widgets/paylas_dugmesi.dart';

// Izgara: satır ve sütun başlığının ikisine de uyan oyuncularla 3x3 tahtayı doldurma oyunu.
// Kullanıcı hücre seçmez; yazdığı oyuncu uyduğu boş hücreye sunucu tarafından yerleştirilir.
class IzgaraScreen extends ConsumerWidget {
  final IzgaraZorlugu zorluk;
  // Ana menüde zorluktan sonra seçilen süre (saniye; null: süresiz). Sadece yeni başlanan tahtada kullanılır:
  // başlangıç zamanı sunucuda tutulur, yarım kalan tahta kalan süresiyle açılır, süre dolunca tahta o anki skorla biter.
  final int? sure;

  const IzgaraScreen({super.key, required this.zorluk, this.sure});

  IzgaraAcilisi get _acilis => (zorluk: zorluk, sure: sure);

  static Color zorlukRengi(IzgaraZorlugu zorluk) => switch (zorluk) {
        IzgaraZorlugu.kolay => Renkler.kolay,
        IzgaraZorlugu.orta => Renkler.orta,
        IzgaraZorlugu.zor => Renkler.zor,
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
            const Flexible(child: Text('IZGARA', overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 10),
            OyunEtiketi(metin: zorluk.ad, renk: zorlukRengi(zorluk)),
          ],
        ),
        actions: [
          const KurallarDugmesi(oyun: 'izgara'),
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

  Future<void> _pesEt(BuildContext context, WidgetRef ref, IzgaraState state) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pes etmek istiyor musun?'),
        content: Text('Oyun şu anki skorunla (${state.skor}/9) biter. Bugün Izgara\'yı tekrar oynayamazsın.'),
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
      case IzgaraDurumu.hata when state.hataMesaji == baskaIzgaraMesaji:
        return const OyunMesajKarti(
          ikon: Icons.lock_clock_rounded,
          baslik: 'Bugünkü hakkını kullandın',
          aciklama: baskaIzgaraMesaji,
        );
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
        return _oyun(context, ref, state);
      case IzgaraDurumu.bitti:
        return _bitis(context, state);
    }
  }

  Widget _oyun(BuildContext context, WidgetRef ref, IzgaraState state) {
    final notifier = ref.read(izgaraProvider(_acilis).notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Ilerleme(
            tahminSayisi: state.tahminSayisi,
            skor: state.skor,
            sayac: state.bitisZamani == null
                ? null
                : SureSayaci(bitisZamani: state.bitisZamani!, onBitti: notifier.sureDoldu),
          ),
          const SizedBox(height: 16),
          IzgaraTahtasiGorunumu(state: state, kutuSec: (hucre) => _kutuSec(context, ref, hucre)),
          // Yazma alanı tahtanın altında; odaklanınca alan ekranın üstüne kayar, öneriler klavyenin üstünde kalır
          const SizedBox(height: 20),
          OyuncuArama(
            renk: Renkler.izgara,
            gonderiliyor: state.gonderiliyor,
            ara: notifier.oyuncuAra,
            gonder: (oyuncu) => _tahminEt(ref, oyuncu),
            kullanilanlar: {for (final o in state.hucreler.values) o.isim},
          ),
          const SizedBox(height: 12),
          if (state.kutuSecimi case final secim?)
            _KutuSecimi(oyuncuIsim: secim.oyuncu.isim, onVazgec: notifier.kutuSecimindenVazgec)
          else
            _SonTahmin(sonuc: state.sonTahmin, tahta: state.tahta!),
        ],
      ),
    );
  }

  // Tahmini gönderir: tahtada zaten olan oyuncu sayılmaz, alan sessizce temizlenir
  Future<TahminSonucu> _tahminEt(WidgetRef ref, OyuncuOneri oyuncu) async {
    final hata = await ref.read(izgaraProvider(_acilis).notifier).tahminEt(oyuncu);
    if (hata != null) throw TahminHatasi(hata);

    // Oyuncu birden fazla kutuya uyuyor: kutu seçimi bekleniyor, doğru/yanlış animasyonu oynamaz
    final state = ref.read(izgaraProvider(_acilis));
    if (state.kutuSecimi != null) return TahminSonucu.notr;
    return switch (state.sonTahmin) {
      IzgaraTahminSonucu(tekrar: true) || IzgaraTahminSonucu(sureDoldu: true) || null => TahminSonucu.notr,
      IzgaraTahminSonucu(dogru: true) => TahminSonucu.dogru,
      _ => TahminSonucu.yanlis,
    };
  }

  // Kutu seçiminde vurgulanan kutuya dokunuldu
  Future<void> _kutuSec(BuildContext context, WidgetRef ref, int hucre) async {
    final hata = await ref.read(izgaraProvider(_acilis).notifier).kutuSec(hucre);
    if (hata != null && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(hata)));
    }
  }

  Widget _bitis(BuildContext context, IzgaraState state) {
    final tamDolu = state.skor == izgaraBoyutu * izgaraBoyutu;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        const SizedBox(height: 8),
        Text(
          Yazi.buyuk(state.sureDoldu ? 'Süre doldu' : bitisBasligi(state.skor, izgaraBoyutu * izgaraBoyutu)),
          textAlign: TextAlign.center,
          style: Yazi.baslik(34, kalinlik: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('${state.skor}/9', style: Yazi.tebesir(52, renk: Renkler.vurgu)),
            const SizedBox(width: 8),
            Text('kutu', style: Yazi.tebesir(18, renk: Renkler.metinIkincil, kalinlik: FontWeight.w400)),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          tamDolu ? 'Yeni tahta gece yarısı açılıyor.' : 'Boş kutularda örnek doğru cevaplar gösteriliyor.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Renkler.metinSoluk, fontSize: 14),
        ),
        const SizedBox(height: 16),
        PuanKarti(oyunTipi: _acilis.zorluk.oyunTipi),
        const SizedBox(height: 20),
        IzgaraTahtasiGorunumu(state: state),
        const SizedBox(height: 28),
        PaylasDugmesi(
          oyun: 'izgara',
          oyunTipi: _acilis.zorluk.oyunTipi,
          metin: (seri, puan) => izgaraPaylasimi(
            doluHucreler: state.hucreler.keys.toSet(),
            zorluk: oyunVeZorluk(_acilis.zorluk.oyunTipi).zorluk,
            sure: _acilis.sure,
            seri: seri,
            puan: puan,
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          child: const Text('Ana menüye dön'),
        ),
      ],
    );
  }
}

// Dolu kutular (9 tebeşir çentiği), yapılan tahmin sayısı ve varsa süre sayacı. Tahmin hakkı sınırı yoktur.
class _Ilerleme extends StatelessWidget {
  final int tahminSayisi;
  final int skor;
  final Widget? sayac;

  const _Ilerleme({required this.tahminSayisi, required this.skor, this.sayac});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        TebesirCentikleri(toplam: izgaraBoyutu * izgaraBoyutu, biten: skor),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            '$tahminSayisi tahmin',
            overflow: TextOverflow.ellipsis,
            style: Yazi.tebesir(15, renk: Renkler.metinIkincil, kalinlik: FontWeight.w400),
          ),
        ),
        const Spacer(),
        if (sayac != null) ...[sayac!, const SizedBox(width: 12)],
        Text('$skor/9 kutu', style: Yazi.tebesir(16)),
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
        'Satır ve sütundaki iki takımda da oynamış oyuncuları bul. Oyuncu tek kutuya uyuyorsa oraya kendiliğinden '
        'yerleşir; birden fazla kutuya uyuyorsa hangisine koyacağını sen seçersin.',
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

// Kutu seçimi beklenirken yazma alanının altındaki satır: açıklama ve "Vazgeç"
class _KutuSecimi extends StatelessWidget {
  final String oyuncuIsim;
  final VoidCallback onVazgec;

  const _KutuSecimi({required this.oyuncuIsim, required this.onVazgec});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.touch_app_rounded, color: Renkler.vurgu, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'Kutuyu seç', style: TextStyle(color: Renkler.vurgu, fontWeight: FontWeight.w700)),
              TextSpan(
                text: '  ·  $oyuncuIsim birden fazla kutuya uyuyor. Koymak istediğin sarı kutuya dokun.',
                style: const TextStyle(color: Renkler.metinIkincil),
              ),
            ]),
            style: const TextStyle(fontSize: 14, height: 1.3),
          ),
        ),
        const SizedBox(width: 4),
        TextButton(
          onPressed: onVazgec,
          style: TextButton.styleFrom(
            foregroundColor: Renkler.metinIkincil,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('Vazgeç'),
        ),
      ],
    );
  }
}

// 3x3 tahta: üstte sütun başlıkları, solda satır başlıkları.
// Kutu seçimi beklenirken (state.kutuSecimi) oyuncunun uyduğu kutular vurgulanır, dokununca kutuSec çağrılır.
class IzgaraTahtasiGorunumu extends StatelessWidget {
  final IzgaraState state;
  final ValueChanged<int>? kutuSec;

  const IzgaraTahtasiGorunumu({super.key, required this.state, this.kutuSec});

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
                      secilebilir: state.durum == IzgaraDurumu.oynaniyor &&
                          (state.kutuSecimi?.hucreler.contains(s * izgaraBoyutu + t) ?? false),
                      onSec: kutuSec == null || state.gonderiliyor ? null : () => kutuSec!(s * izgaraBoyutu + t),
                      oyuncu: state.hucreler[s * izgaraBoyutu + t],
                      ornekCevap: state.ornekCevaplar[s * izgaraBoyutu + t],
                      yeni: state.durum == IzgaraDurumu.oynaniyor &&
                          state.sonTahmin?.dogru == true &&
                          state.sonTahmin?.hucre == s * izgaraBoyutu + t,
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
          style: Yazi.baslik(12, kalinlik: FontWeight.w700, renk: Renkler.metinIkincil).copyWith(height: 1.1),
        ),
      ],
    );
  }
}

// Tahtadaki bir kutu: boş, oyuncuyla dolu ya da (oyun bittiyse) örnek cevaplı
class _Hucre extends StatelessWidget {
  final IzgaraOyuncusu? oyuncu;
  final IzgaraOyuncusu? ornekCevap; // Oyun bitince boş kalan kutuda gösterilen doğru cevap

  final bool yeni; // Son doğru tahminle dolan kutu: kısa bir an sarı parlar ki oyuncu nereye yerleştiği görülsün
  // Kutu seçiminde oyuncunun uyduğu kutu: sarı kalın çerçeve, hafif sarı dolgu, ortada "+"; dokununca onSec
  final bool secilebilir;
  final VoidCallback? onSec;

  const _Hucre({this.oyuncu, this.ornekCevap, this.yeni = false, this.secilebilir = false, this.onSec});

  @override
  Widget build(BuildContext context) {
    final dolu = oyuncu != null;
    if (secilebilir && !dolu) {
      return Semantics(
        button: true,
        label: 'Oyuncuyu bu kutuya koy',
        child: GestureDetector(
          onTap: onSec,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            decoration: BoxDecoration(
              color: Renkler.vurgu.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Renkler.vurgu, width: 3),
              boxShadow: [BoxShadow(color: Renkler.vurgu.withValues(alpha: 0.35), blurRadius: 10)],
            ),
            child: const Center(child: Icon(Icons.add_rounded, color: Renkler.vurgu, size: 30)),
          ),
        ),
      );
    }

    return TweenAnimationBuilder<double>(
      key: ValueKey((oyuncu?.isim, yeni)),
      tween: Tween(begin: yeni ? 1 : 0, end: 0),
      duration: const Duration(milliseconds: 1400),
      curve: Curves.easeInCubic,
      builder: (context, parlama, child) => AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        // Tahtaya tebeşirle çizilmiş kare: boşken soluk, dolunca tebeşir beyazı
        decoration: BoxDecoration(
          color: dolu ? Color.lerp(Renkler.metin.withValues(alpha: 0.05), Renkler.vurgu.withValues(alpha: 0.18), parlama) : null,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: dolu ? Color.lerp(Renkler.metinIkincil, Renkler.vurgu, parlama)! : Renkler.kenar,
            width: 1.5 + parlama,
          ),
          boxShadow: parlama > 0
              ? [BoxShadow(color: Renkler.vurgu.withValues(alpha: 0.45 * parlama), blurRadius: 14 * parlama)]
              : null,
        ),
        child: child,
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
                harfRengi: ornek ? Renkler.metinSoluk : Renkler.vurgu,
              ),
            ),
            const Spacer(),
            Text(
              oyuncu.isim,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              // Bulunan isim tahtaya elle yazılmış gibi; örnek cevap soluk
              style: Yazi.tebesir(
                12,
                renk: ornek ? Renkler.metinSoluk : Renkler.metin,
                kalinlik: ornek ? FontWeight.w400 : FontWeight.w700,
              ).copyWith(height: 1.0),
            ),
          ],
        ),
      ),
    );
  }
}
