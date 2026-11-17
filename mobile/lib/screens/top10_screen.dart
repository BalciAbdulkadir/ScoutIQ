import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/oyuncu_oneri.dart';
import '../models/top10.dart';
import '../providers/top10_provider.dart';
import '../theme/renkler.dart';
import '../theme/yazi.dart';
import '../widgets/kulup_logosu.dart';
import '../widgets/oyun_mesaj_karti.dart';
import '../widgets/oyun_ortak.dart';
import '../widgets/oyuncu_arama.dart';
import '../widgets/oyuncu_fotografi.dart';
import '../widgets/tebesir.dart';

// Top 10: başlıktaki listenin 10 oyuncusunu bulma oyunu. Her satırda oyuncunun uyruğunun bayrağı ipucu olarak açıktır.
// Kullanıcı sıra seçmez; listedeki oyuncu kendi sırasındaki satıra sunucu tarafından yerleştirilir.
class Top10Screen extends ConsumerWidget {
  // Günlük oyunun tipi. Top 10'un zorluk modu yoktur: 'top10'
  final String oyunTipi;
  // Top 10'da süre yoktur; ana menünün ortak açılışı için tutulur
  final int? sure;

  const Top10Screen({super.key, this.oyunTipi = 'top10', this.sure});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(top10Provider(oyunTipi));
    final oynaniyor = state.durum == Top10Durumu.oynaniyor;

    return Scaffold(
      appBar: AppBar(
        title: const Text('TOP 10'),
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

  Future<void> _pesEt(BuildContext context, WidgetRef ref, Top10State state) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pes etmek istiyor musun?'),
        content: Text('Oyun şu anki skorunla (${state.skor}/$top10Boyu) biter. Bugün Top 10\'u tekrar oynayamazsın.'),
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

    final hata = await ref.read(top10Provider(oyunTipi).notifier).pesEt();
    if (hata != null && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(hata)));
    }
  }

  Widget _govde(BuildContext context, WidgetRef ref, Top10State state) {
    switch (state.durum) {
      case Top10Durumu.yukleniyor:
        return const Center(child: CircularProgressIndicator());
      case Top10Durumu.hata:
        return OyunMesajKarti(
          ikon: Icons.wifi_off_rounded,
          baslik: 'Bağlantı sorunu',
          aciklama: state.hataMesaji ?? 'Lütfen biraz sonra tekrar dene.',
          onTekrarDene: () => ref.invalidate(top10Provider(oyunTipi)),
        );
      case Top10Durumu.oyunYok:
        return const OyunMesajKarti(
          ikon: Icons.schedule_rounded,
          baslik: 'Bugünün listesi henüz hazır değil',
          aciklama: 'Biraz sonra tekrar dene.',
        );
      case Top10Durumu.oynaniyor:
        return _oyun(context, ref, state);
      case Top10Durumu.bitti:
        return _bitis(context, state);
    }
  }

  Widget _oyun(BuildContext context, WidgetRef ref, Top10State state) {
    final notifier = ref.read(top10Provider(oyunTipi).notifier);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        _Baslik(soru: state.soru!),
        const SizedBox(height: 14),
        Row(
          children: [
            TebesirCentikleri(toplam: top10Boyu, biten: state.skor),
            const Spacer(),
            Text('${state.skor}/$top10Boyu', style: Yazi.tebesir(16)),
          ],
        ),
        const SizedBox(height: 16),
        Top10Listesi(state: state),
        // Canlar listeyle yazma alanının arasında; yazma alanı listenin altında
        const SizedBox(height: 14),
        Top10Canlari(kalan: state.kalanCan),
        const SizedBox(height: 6),
        OyuncuArama(
          renk: Renkler.top10,
          gonderiliyor: state.gonderiliyor,
          ara: notifier.oyuncuAra,
          gonder: (oyuncu) => _tahminEt(ref, oyuncu),
          kullanilanlar: state.denenenler,
          kullanildiEtiketi: 'denendi',
        ),
        const SizedBox(height: 12),
        _SonTahmin(sonuc: state.sonTahmin),
      ],
    );
  }

  // Tahmini gönderir: daha önce denenmiş oyuncu sayılmaz, alan sessizce temizlenir
  Future<TahminSonucu> _tahminEt(WidgetRef ref, OyuncuOneri oyuncu) async {
    final hata = await ref.read(top10Provider(oyunTipi).notifier).tahminEt(oyuncu);
    if (hata != null) throw TahminHatasi(hata);

    return switch (ref.read(top10Provider(oyunTipi)).sonTahmin) {
      Top10TahminSonucu(tekrar: true) || null => TahminSonucu.notr,
      Top10TahminSonucu(dogru: true) => TahminSonucu.dogru,
      _ => TahminSonucu.yanlis,
    };
  }

  Widget _bitis(BuildContext context, Top10State state) {
    final tam = state.skor == top10Boyu;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        const SizedBox(height: 8),
        Text(
          Yazi.buyuk(bitisBasligi(state.skor, top10Boyu)),
          textAlign: TextAlign.center,
          style: Yazi.baslik(34, kalinlik: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        // Dar ekranda büyük skor yazısı sığmazsa küçülür
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('${state.skor}/$top10Boyu', style: Yazi.tebesir(52, renk: Renkler.vurgu)),
              const SizedBox(width: 8),
              Text('oyuncu', style: Yazi.tebesir(18, renk: Renkler.metinIkincil, kalinlik: FontWeight.w400)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          tam
              ? 'Yeni liste gece yarısı açılıyor.'
              : '${state.kalanCan == 0 ? 'Canların bitti. ' : ''}Bulamadığın oyuncular kırmızıyla gösteriliyor.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Renkler.metinSoluk, fontSize: 14),
        ),
        const SizedBox(height: 20),
        _Baslik(soru: state.soru!),
        const SizedBox(height: 14),
        Top10Listesi(state: state),
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

// Listenin başlığı ve verinin dönemi
class _Baslik extends StatelessWidget {
  final Top10Sorusu soru;

  const _Baslik({required this.soru});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(soru.baslik, style: Yazi.baslik(22, kalinlik: FontWeight.w800).copyWith(height: 1.2)),
        if (soru.altBaslik != null) ...[
          const SizedBox(height: 4),
          Text(soru.altBaslik!, style: const TextStyle(color: Renkler.metinSoluk, fontSize: 12.5)),
        ],
      ],
    );
  }
}

// Kalan canlar: dolu kırmızı kalpler, giden can boş kalp. Can gidince kalp kısa bir an küçülüp boşalır.
class Top10Canlari extends StatelessWidget {
  final int kalan;

  const Top10Canlari({super.key, required this.kalan});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$kalan can kaldı',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < top10Can; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, animasyon) => ScaleTransition(scale: animasyon, child: child),
                child: Icon(
                  i < kalan ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  key: ValueKey(i < kalan),
                  color: i < kalan ? Renkler.can : Renkler.can.withValues(alpha: 0.4),
                  size: 30,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// Son tahminin sonucu: "Doğru · Arda Güler → 3. sıra"
class _SonTahmin extends StatelessWidget {
  final Top10TahminSonucu? sonuc;

  const _SonTahmin({required this.sonuc});

  @override
  Widget build(BuildContext context) {
    final s = sonuc;
    if (s == null) {
      return const Text(
        'Listedeki oyuncuları bul. Her satırda oyuncunun uyruğunun bayrağı var; bulduğun oyuncu kendi sırasına yerleşir. '
        'Listede olmayan oyuncu bir can götürür.',
        style: TextStyle(color: Renkler.metinSoluk, fontSize: 13, height: 1.4),
      );
    }

    final (ikon, renk, baslik, ayrinti) = switch (s) {
      Top10TahminSonucu(tekrar: true) => (Icons.info_rounded, Renkler.orta, 'Zaten denedin', '${s.oyuncuIsim} daha önce denendi'),
      Top10TahminSonucu(dogru: true, sira: final sira?) => (Icons.check_circle_rounded, Renkler.basari, 'Doğru', '${s.oyuncuIsim} → $sira. sıra'),
      _ => (Icons.cancel_rounded, Renkler.hata, 'Listede değil', '${s.oyuncuIsim} bu listede yok · bir can gitti'),
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

// 1'den 10'a satırlar: sıra, bayrak ve (bulunduysa ya da oyun bittiyse) oyuncu ve değeri
class Top10Listesi extends StatelessWidget {
  final Top10State state;

  const Top10Listesi({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final bitti = state.durum == Top10Durumu.bitti;
    return Column(
      children: [
        for (final satir in state.soru!.satirlar) ...[
          _Satir(
            satir: satir,
            oyuncu: state.bulunanlar[satir.sira] ?? (bitti ? state.cevaplar[satir.sira] : null),
            bulundu: state.bulunanlar.containsKey(satir.sira),
            yeni: !bitti && state.sonTahmin?.dogru == true && state.sonTahmin?.sira == satir.sira,
          ),
          const SizedBox(height: 6),
        ],
      ],
    );
  }
}

class _Satir extends StatelessWidget {
  final Top10Satiri satir;
  final Top10Oyuncusu? oyuncu; // Bulunan oyuncu ya da oyun bitince açılan cevap
  final bool bulundu; // false ve oyuncu doluysa: kullanıcının bulamadığı, oyun bitince açılan oyuncu
  final bool yeni; // Son doğru tahminle dolan satır: kısa bir an sarı parlar

  const _Satir({required this.satir, this.oyuncu, required this.bulundu, this.yeni = false});

  @override
  Widget build(BuildContext context) {
    final o = oyuncu;
    final renk = o == null ? Renkler.kenar : (bulundu ? Renkler.basari : Renkler.hata);

    return TweenAnimationBuilder<double>(
      key: ValueKey((o?.isim, yeni)),
      tween: Tween(begin: yeni ? 1 : 0, end: 0),
      duration: const Duration(milliseconds: 1400),
      curve: Curves.easeInCubic,
      builder: (context, parlama, child) => Container(
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: o == null ? null : Color.lerp(renk.withValues(alpha: 0.10), Renkler.vurgu.withValues(alpha: 0.2), parlama),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Color.lerp(renk.withValues(alpha: o == null ? 1 : 0.6), Renkler.vurgu, parlama)!, width: 1.4),
        ),
        child: child,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text('${satir.sira}', style: Yazi.tebesir(20, renk: o == null ? Renkler.metinSoluk : renk)),
          ),
          KulupLogosu(logoUrl: satir.bayrakUrl, boyut: 30, yedekIkon: Icons.flag_rounded),
          const SizedBox(width: 10),
          if (o != null) ...[
            OyuncuFotografi(isim: o.isim, fotoUrl: o.fotoUrl, boyut: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                o.isim,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: bulundu ? Renkler.metin : Renkler.metinIkincil,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (o.deger != null) ...[
              const SizedBox(width: 8),
              Text(o.deger!, style: Yazi.tebesir(15, renk: Renkler.metinIkincil, kalinlik: FontWeight.w400)),
            ],
          ] else
            const Spacer(),
        ],
      ),
    );
  }
}
