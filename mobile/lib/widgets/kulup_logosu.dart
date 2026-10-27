import 'package:flutter/material.dart';
import '../theme/renkler.dart';

// Yuvarlak zemin üstünde kulüp logosu. Logo yoksa, yüklenirken ya da yüklenemezse kalkan ikonu gösterilir.
// Logolar Transfermarkt'tan link olarak gelir, kopyaları tutulmaz.
class KulupLogosu extends StatelessWidget {
  final String? logoUrl;
  final double boyut;
  final Color ikonRengi;

  const KulupLogosu({
    super.key,
    required this.logoUrl,
    this.boyut = 56,
    this.ikonRengi = Renkler.metinIkincil,
  });

  @override
  Widget build(BuildContext context) {
    final ikon = Icon(Icons.shield_outlined, color: ikonRengi, size: boyut / 2);
    // Logolar şeffaf zeminli: kesilmesin diye yuvarlağın içine boşlukla sığdırılır
    final logoBoyutu = boyut * 0.7;

    return Container(
      width: boyut,
      height: boyut,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: Renkler.yuzeyYuksek, shape: BoxShape.circle),
      child: logoUrl == null
          ? ikon
          : Image.network(
              logoUrl!,
              width: logoBoyutu,
              height: logoBoyutu,
              fit: BoxFit.contain,
              // Ekrandaki boyuta göre küçültülerek belleğe alınır
              cacheWidth: (logoBoyutu * MediaQuery.devicePixelRatioOf(context)).round(),
              loadingBuilder: (context, child, ilerleme) => ilerleme == null ? child : ikon,
              errorBuilder: (context, hata, iz) => ikon,
            ),
    );
  }
}
