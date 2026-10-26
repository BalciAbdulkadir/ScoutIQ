import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/bonservis_sorusu.dart';
import '../providers/bonservis_provider.dart';
import '../theme/renkler.dart';
import '../widgets/bonservis_oyuncu_karti.dart';
import '../widgets/oyun_mesaj_karti.dart';
import '../widgets/oyun_ortak.dart';

// Bonservis: üstteki oyuncunun toplam bonservisi görünür, alttakinin daha fazla mı daha az mı olduğu tahmin edilir
class BonservisScreen extends ConsumerStatefulWidget {
  const BonservisScreen({super.key});

  // Sonuç gösterildikten sonra sıradaki soruya kendiliğinden geçmeden önceki bekleme
  static const sonucBeklemesi = Duration(milliseconds: 1800);

  @override
  ConsumerState<BonservisScreen> createState() => _BonservisScreenState();
}

class _BonservisScreenState extends ConsumerState<BonservisScreen> {
  static const _maksimumSkor = 5;

  Timer? _devamZamanlayici;

  @override
  void dispose() {
    _devamZamanlayici?.cancel();
    super.dispose();
  }

  Future<void> _tahminEt(bool dahaFazla) async {
    final hata = await ref.read(bonservisProvider.notifier).tahminEt(dahaFazla: dahaFazla);
    if (!mounted) return;

    if (hata != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(hata)));
      return;
    }

    // Bedel açıldı: kullanıcı sonucu görsün, sonra sıradaki soruya geç
    if (ref.read(bonservisProvider).sonCevapDogru != null) {
      _devamZamanlayici?.cancel();
      _devamZamanlayici = Timer(BonservisScreen.sonucBeklemesi, _devamEt);
    }
  }

  void _devamEt() {
    _devamZamanlayici?.cancel();
    if (!mounted) return;
    ref.read(bonservisProvider.notifier).devamEt();
  }

  @override
  Widget build(BuildContext context) {
    final durum = ref.watch(bonservisProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Bonservis')),
      body: SafeArea(child: _govde(durum)),
    );
  }

  Widget _govde(BonservisState durum) {
    switch (durum.durum) {
      case BonservisDurumu.yukleniyor:
        return const Center(child: CircularProgressIndicator(color: Renkler.bonservis));
      case BonservisDurumu.hata:
        return OyunMesajKarti(
          ikon: Icons.wifi_off_rounded,
          baslik: 'Bağlantı sorunu',
          aciklama: durum.hataMesaji ?? 'Lütfen biraz sonra tekrar dene.',
          onTekrarDene: () => ref.invalidate(bonservisProvider),
        );
      case BonservisDurumu.oyunYok:
        return const OyunMesajKarti(
          ikon: Icons.schedule_rounded,
          baslik: 'Bugünün oyunu henüz hazır değil',
          aciklama: 'Biraz sonra tekrar dene.',
        );
      case BonservisDurumu.zatenOynandi:
        return OyunMesajKarti(
          ikon: Icons.check_circle_outline_rounded,
          baslik: 'Bugünkü oyununu oynadın',
          aciklama: 'Skorun: ${durum.skor}/$_maksimumSkor\nYeni oyun gece yarısı açılıyor.',
        );
      case BonservisDurumu.yaridaBirakildi:
        return OyunMesajKarti(
          ikon: Icons.lock_outline_rounded,
          baslik: 'Bugünkü hakkını kullandın',
          aciklama: 'Oyundan çıktığın için oyun tamamlanmış sayıldı.\nSkorun: ${durum.skor}/$_maksimumSkor',
        );
      case BonservisDurumu.bitti:
        return _bitis(durum);
      case BonservisDurumu.oynaniyor:
        return _oyun(durum);
    }
  }

  Widget _oyun(BonservisState durum) {
    final soru = durum.soru!;
    final cevaplandi = durum.sonCevapDogru != null;

    // Kartlar ortada, butonlar altta durur; küçük ekranda içerik sığmazsa sayfa kaydırılır
    return LayoutBuilder(
      builder: (context, kisitlar) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: kisitlar.maxHeight - 28),
          child: IntrinsicHeight(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OyunIlerlemesi(
                  soruSayisi: durum.sorular.length,
                  mevcutSoru: durum.soruIndex,
                  sonuclar: durum.sonuclar,
                  renk: Renkler.bonservis,
                  sagMetin: '${durum.skor} doğru',
                ),
                const SizedBox(height: 24),
                const Spacer(),
                const Text(
                  'Alttaki oyuncunun kariyeri boyunca ödenen toplam bonservis daha fazla mı, daha az mı?',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Renkler.metinIkincil, fontSize: 14, height: 1.4),
                ),
                const SizedBox(height: 16),
                _gecisli(
                  BonservisOyuncuKarti(key: ValueKey('ref-${soru.referans.id}'), oyuncu: soru.referans, bedelGorunur: true),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Center(child: VsRozeti()),
                ),
                _gecisli(
                  BonservisOyuncuKarti(
                    key: ValueKey('rakip-${soru.rakip.id}'),
                    oyuncu: soru.rakip,
                    bedelGorunur: cevaplandi,
                    bedelAnimasyonlu: cevaplandi,
                    dogru: durum.sonCevapDogru,
                  ),
                ),
                const Spacer(),
                const SizedBox(height: 24),
                // Butonlar ve sonuç bandı aynı yükseklikte: cevap verilince kartlar kaymasın
                SizedBox(
                  height: 64,
                  child: cevaplandi
                      ? _SonucBandi(soru: soru, dogru: durum.sonCevapDogru!, sonSoru: durum.sonSoru, onDevam: _devamEt)
                      : _tahminButonlari(durum),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Yeni oyuncu geldiğinde kart hafifçe kayarak girer
  Widget _gecisli(Widget kart) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, animasyon) => SlideTransition(
        position: Tween(begin: const Offset(0.08, 0), end: Offset.zero).animate(animasyon),
        child: FadeTransition(opacity: animasyon, child: child),
      ),
      child: kart,
    );
  }

  Widget _tahminButonlari(BonservisState durum) {
    final aktif = durum.tahminEdilebilir;

    Widget buton({required String metin, required IconData ikon, required bool dahaFazla}) {
      return Expanded(
        child: FilledButton.icon(
          onPressed: aktif ? () => _tahminEt(dahaFazla) : null,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(64),
            backgroundColor: Renkler.yuzeyYuksek,
            foregroundColor: Renkler.metin,
            disabledBackgroundColor: Renkler.yuzey,
            disabledForegroundColor: Renkler.metinSoluk,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Renkler.kenar),
            ),
          ),
          icon: Icon(ikon, size: 20, color: aktif ? Renkler.bonservis : Renkler.metinSoluk),
          label: Text(metin, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
      );
    }

    return Row(
      children: [
        buton(metin: 'Daha az', ikon: Icons.arrow_downward_rounded, dahaFazla: false),
        const SizedBox(width: 12),
        buton(metin: 'Daha fazla', ikon: Icons.arrow_upward_rounded, dahaFazla: true),
      ],
    );
  }

  Widget _bitis(BonservisState durum) {
    return OyunBitisEkrani(
      skor: '${durum.skor}/${durum.sorular.length}',
      skorAciklamasi: 'doğru',
      baslik: bitisBasligi(durum.skor, durum.sorular.length),
      renk: Renkler.bonservis,
      ozetSatirlari: [
        for (var i = 0; i < durum.sonuclar.length; i++) _ozetSatiri(durum.sorular[i], durum.sonuclar[i]),
      ],
    );
  }

  Widget _ozetSatiri(BonservisSorusu soru, bool dogru) {
    return OzetSatiri(
      dogru: dogru,
      baslik: '${soru.referans.isim}  –  ${soru.rakip.isim}',
      altBaslik: '${bonservisMetni(soru.referans.toplamBonservis)}  –  ${bonservisMetni(soru.rakip.toplamBonservis)}',
    );
  }
}

// Tahminden sonra butonların yerine çıkan sonuç
class _SonucBandi extends StatelessWidget {
  final BonservisSorusu soru;
  final bool dogru;
  final bool sonSoru;
  final VoidCallback onDevam;

  const _SonucBandi({required this.soru, required this.dogru, required this.sonSoru, required this.onDevam});

  @override
  Widget build(BuildContext context) {
    final renk = dogru ? Renkler.basari : Renkler.hata;
    final fark = (soru.rakip.toplamBonservis - soru.referans.toplamBonservis).abs();
    final butonMetni = (!dogru || sonSoru) ? 'Sonuçları gör' : 'Devam';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: BoxDecoration(
        color: Renkler.yuzey,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: renk.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(dogru ? Icons.check_circle_rounded : Icons.cancel_rounded, color: renk, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dogru ? 'Doğru' : 'Yanlış',
                  style: TextStyle(color: renk, fontSize: 16, fontWeight: FontWeight.w700),
                ),
                Text(
                  '${soru.pahaliOlan.isim}, ${bonservisMetni(fark)} daha pahalı',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Renkler.metinIkincil, fontSize: 13),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onDevam,
            style: TextButton.styleFrom(foregroundColor: Renkler.metin),
            child: Text(butonMetni, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
