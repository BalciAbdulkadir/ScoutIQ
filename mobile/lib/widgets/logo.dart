import 'package:flutter/material.dart';
import '../theme/renkler.dart';
import '../theme/yazi.dart';

// FOOTY beyaz, LORE tebeşir sarısı
class FootyLoreLogo extends StatelessWidget {
  final double boyut;

  const FootyLoreLogo({super.key, this.boyut = 24});

  @override
  Widget build(BuildContext context) {
    final stil = Yazi.baslik(boyut, kalinlik: FontWeight.w900).copyWith(letterSpacing: boyut * 0.05);
    return Text.rich(
      TextSpan(children: [
        const TextSpan(text: 'FOOTY'),
        TextSpan(text: 'LORE', style: stil.copyWith(color: Renkler.vurgu)),
      ]),
      style: stil,
      semanticsLabel: 'FootyLore',
    );
  }
}

// Tek satır tebeşir logo: FOOTY'nin O'sundan çıkan sarı koşu, LORE'daki O futbol topu.
// Görselin oranı sabit, sadece yükseklik verilir.
class FootyLoreLogoGorseli extends StatelessWidget {
  final double yukseklik;

  const FootyLoreLogoGorseli({super.key, this.yukseklik = 36});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'FootyLore',
      image: true,
      child: Image.asset(
        'assets/logo/footylore_logo.png',
        height: yukseklik,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        excludeFromSemantics: true,
      ),
    );
  }
}
