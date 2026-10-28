import 'package:flutter/material.dart';
import '../theme/renkler.dart';

// Açık renk yuvarlak zemin üstünde kulüp (ya da milli takım) logosu. Logo yoksa, yüklenirken ya da yüklenemezse
// yedek ikon gösterilir. Logolar Transfermarkt'tan link olarak gelir, kopyaları tutulmaz.
class KulupLogosu extends StatelessWidget {
  final String? logoUrl;
  final double boyut;
  final Color ikonRengi;
  final IconData yedekIkon;

  const KulupLogosu({
    super.key,
    required this.logoUrl,
    this.boyut = 56,
    this.ikonRengi = Renkler.metinSoluk,
    this.yedekIkon = Icons.shield_outlined,
  });

  @override
  Widget build(BuildContext context) {
    final ikon = Icon(yedekIkon, color: ikonRengi, size: boyut / 2);
    // Logolar şeffaf zeminli: kesilmesin diye yuvarlağın içine boşlukla sığdırılır
    final logoBoyutu = boyut * 0.68;

    return Container(
      width: boyut,
      height: boyut,
      alignment: Alignment.center,
      // Zemin açık renk: siyah ya da koyu logolar (Juventus, Newcastle ...) koyu temada kaybolmasın
      decoration: const BoxDecoration(color: Renkler.logoZemini, shape: BoxShape.circle),
      child: logoUrl == null
          ? ikon
          : Image.network(
              logoUrl!,
              width: logoBoyutu,
              height: logoBoyutu,
              fit: BoxFit.contain,
              // Ekrandaki boyuta göre küçültülerek belleğe alınır
              cacheWidth: (logoBoyutu * MediaQuery.devicePixelRatioOf(context)).round(),
              // İlk kare gelene kadar ikon gösterilir (loadingBuilder ilk veri gelmeden boş kalıyordu)
              frameBuilder: (context, child, kare, senkron) => senkron || kare != null ? child : ikon,
              errorBuilder: (context, hata, iz) => ikon,
            ),
    );
  }
}
