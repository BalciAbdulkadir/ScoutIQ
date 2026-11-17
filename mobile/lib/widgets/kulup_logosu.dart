import 'package:flutter/material.dart';
import '../theme/renkler.dart';

// Açık renk yuvarlak zemin üstünde kulüp (ya da milli takım) logosu. Logo yoksa, yüklenirken ya da yüklenemezse
// yedek ikon gösterilir. Logolar Transfermarkt'tan link olarak gelir, kopyaları tutulmaz.
class KulupLogosu extends StatelessWidget {
  static const _uygulamaDosyasi = 'asset:';

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

    final url = logoUrl;
    final cacheWidth = (logoBoyutu * MediaQuery.devicePixelRatioOf(context)).round();
    Widget gorsel;
    if (url == null) {
      gorsel = ikon;
    } else if (url.startsWith(_uygulamaDosyasi)) {
      // Artık olmayan ülkelerin bayrakları uygulamanın içinde durur ("asset:assets/bayraklar/...")
      gorsel = Image.asset(
        url.substring(_uygulamaDosyasi.length),
        width: logoBoyutu,
        height: logoBoyutu,
        fit: BoxFit.contain,
        cacheWidth: cacheWidth,
        errorBuilder: (context, hata, iz) => ikon,
      );
    } else {
      gorsel = Image.network(
        url,
        width: logoBoyutu,
        height: logoBoyutu,
        fit: BoxFit.contain,
        // Ekrandaki boyuta göre küçültülerek belleğe alınır
        cacheWidth: cacheWidth,
        // İlk kare gelene kadar ikon gösterilir (loadingBuilder ilk veri gelmeden boş kalıyordu)
        frameBuilder: (context, child, kare, senkron) => senkron || kare != null ? child : ikon,
        errorBuilder: (context, hata, iz) => ikon,
      );
    }

    return Container(
      width: boyut,
      height: boyut,
      alignment: Alignment.center,
      // Zemin açık renk: siyah ya da koyu logolar (Juventus, Newcastle ...) koyu temada kaybolmasın
      decoration: const BoxDecoration(color: Renkler.logoZemini, shape: BoxShape.circle),
      child: gorsel,
    );
  }
}
