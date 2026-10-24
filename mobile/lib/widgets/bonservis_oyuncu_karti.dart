import 'package:flutter/material.dart';
import '../models/bonservis_sorusu.dart';
import '../theme/renkler.dart';

// Bonservis oyunundaki oyuncu kartı. Bedel gizliyse "?" gösterir; açılınca bedel sayarak yükselir.
class BonservisOyuncuKarti extends StatelessWidget {
  final BonservisOyuncusu oyuncu;
  final bool bedelGorunur;
  final bool? dogru; // Doluysa kart sonuca göre yeşil ya da kırmızı yanar
  final bool bedelAnimasyonlu; // Bedel yeni açıldıysa sayarak gösterilir

  const BonservisOyuncuKarti({
    super.key,
    required this.oyuncu,
    required this.bedelGorunur,
    this.dogru,
    this.bedelAnimasyonlu = false,
  });

  static const _avatarRenkleri = [
    Color(0xFF26A69A),
    Color(0xFF5C6BC0),
    Color(0xFFEF6C00),
    Color(0xFFAB47BC),
    Color(0xFF29B6F6),
    Color(0xFF9CCC65),
  ];

  static String basHarfler(String isim) {
    final parcalar = isim.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parcalar.isEmpty) return '?';
    final ilk = parcalar.first.characters.first;
    final son = parcalar.length > 1 ? parcalar.last.characters.first : '';
    return (ilk + son).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final kenarRengi = switch (dogru) {
      true => Colors.greenAccent,
      false => Colors.redAccent,
      null => Renkler.kartKenar,
    };
    final avatarRengi = _avatarRenkleri[oyuncu.isim.hashCode.abs() % _avatarRenkleri.length];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Renkler.kart,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kenarRengi, width: dogru == null ? 1.5 : 2.5),
        boxShadow: [
          if (dogru != null)
            BoxShadow(color: kenarRengi.withValues(alpha: 0.25), blurRadius: 16, spreadRadius: 1),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: avatarRengi.withValues(alpha: 0.25),
            child: Text(
              basHarfler(oyuncu.isim),
              style: TextStyle(color: avatarRengi, fontWeight: FontWeight.w900, fontSize: 20),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  oyuncu.isim,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text('Toplam bonservis', style: TextStyle(color: Renkler.soluk, fontSize: 12)),
                const SizedBox(height: 2),
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
      fontSize: 28,
      fontWeight: FontWeight.w900,
      fontFeatures: [FontFeature.tabularFigures()],
    );

    if (!bedelGorunur) {
      return Text('? M€', style: stil.copyWith(color: Colors.white38));
    }

    final renk = switch (dogru) {
      true => Colors.greenAccent,
      false => Colors.redAccent,
      null => Colors.lightBlueAccent,
    };

    if (!bedelAnimasyonlu) {
      return Text(bonservisMetni(oyuncu.toplamBonservis), style: stil.copyWith(color: renk));
    }

    // Bedel sıfırdan gerçek değerine sayarak yükselir
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: oyuncu.toplamBonservis.toDouble()),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, deger, _) {
        // Ara değerler tam milyona yuvarlanır, son karede gerçek değer gösterilir
        final gosterilen = deger >= oyuncu.toplamBonservis ? oyuncu.toplamBonservis : (deger / 1000000).round() * 1000000;
        return Text(bonservisMetni(gosterilen), style: stil.copyWith(color: renk));
      },
    );
  }
}
