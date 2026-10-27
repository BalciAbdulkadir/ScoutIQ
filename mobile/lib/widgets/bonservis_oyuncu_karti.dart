import 'package:flutter/material.dart';
import '../models/bonservis_sorusu.dart';
import '../theme/renkler.dart';
import 'oyuncu_fotografi.dart';

// Bonservis oyunundaki oyuncu kartı. Bedel gizliyse "?" gösterir; açılınca bedel sayarak yükselir.
class BonservisOyuncuKarti extends StatelessWidget {
  final BonservisOyuncusu oyuncu;
  final bool bedelGorunur;
  final bool? dogru; // Doluysa kart sonuca göre yeşil ya da kırmızı kenarlanır
  final bool bedelAnimasyonlu; // Bedel yeni açıldıysa sayarak gösterilir

  const BonservisOyuncuKarti({
    super.key,
    required this.oyuncu,
    required this.bedelGorunur,
    this.dogru,
    this.bedelAnimasyonlu = false,
  });

  @override
  Widget build(BuildContext context) {
    final kenarRengi = switch (dogru) {
      true => Renkler.basari,
      false => Renkler.hata,
      null => Renkler.kenar,
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      decoration: BoxDecoration(
        color: Renkler.yuzey,
        borderRadius: BorderRadius.circular(16),
        // Kenar kalınlığı sabit: sonuç gösterilince kart boyutu değişip yerleşim kaymasın
        border: Border.all(color: kenarRengi, width: 1.5),
      ),
      child: Row(
        children: [
          OyuncuFotografi(isim: oyuncu.isim, fotoUrl: oyuncu.fotoUrl, harfRengi: Renkler.bonservis),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  oyuncu.isim,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Renkler.metin, fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                _bedel(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bedel() {
    const stil = TextStyle(
      fontSize: 26,
      fontWeight: FontWeight.w800,
      fontFeatures: [FontFeature.tabularFigures()],
    );

    if (!bedelGorunur) {
      return Text('? M€', style: stil.copyWith(color: Renkler.metinSoluk));
    }

    final renk = switch (dogru) {
      true => Renkler.basari,
      false => Renkler.hata,
      null => Renkler.bonservis,
    };

    if (!bedelAnimasyonlu) {
      return Text(bonservisMetni(oyuncu.toplamBonservis), style: stil.copyWith(color: renk));
    }

    // Bedel sıfırdan gerçek değerine sayarak yükselir
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: oyuncu.toplamBonservis.toDouble()),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOutCubic,
      builder: (context, deger, _) {
        // Ara değerler tam milyona yuvarlanır, son karede gerçek değer gösterilir
        final gosterilen = deger >= oyuncu.toplamBonservis ? oyuncu.toplamBonservis : (deger / 1000000).round() * 1000000;
        return Text(bonservisMetni(gosterilen), style: stil.copyWith(color: renk));
      },
    );
  }
}
