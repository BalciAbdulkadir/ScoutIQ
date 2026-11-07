import 'package:flutter/material.dart';

// Tebeşirle çizilmiş FootyLore logosu: FOOTY LORE yazısı, O'dan çıkan taktik oku ve topa dönüşen O.
// Zemini şeffaf, tahta zemininin üstüne oturur.
class FootyLoreLogo extends StatelessWidget {
  final double genislik;

  const FootyLoreLogo({super.key, this.genislik = 170});

  // Görselin en / boy oranı (1200 x 262)
  static const enBoyOrani = 1200 / 262;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'FootyLore',
      image: true,
      child: Image.asset(
        'assets/images/footylore_logo.png',
        width: genislik,
        height: genislik / enBoyOrani,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        excludeFromSemantics: true,
      ),
    );
  }
}
