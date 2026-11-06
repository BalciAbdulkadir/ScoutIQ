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
