import 'package:flutter/material.dart';
import '../theme/renkler.dart';

// Köşeleri yuvarlatılmış dikey oyuncu fotoğrafı. Fotoğraf yoksa, yüklenirken ya da yüklenemezse baş harfler gösterilir.
// Fotoğraflar Transfermarkt'tan link olarak gelir, kopyaları tutulmaz.
class OyuncuFotografi extends StatelessWidget {
  // Transfermarkt portreleri 300x390 (en/boy 1:1.3). Çerçeve aynı oranda olduğu için fotoğraf kırpılmadan sığar.
  static const double enBoyOrani = 300 / 390;

  final String isim;
  final String? fotoUrl;
  // Çerçevenin genişliği; yüksekliği orana göre hesaplanır
  final double boyut;
  final Color harfRengi;

  const OyuncuFotografi({
    super.key,
    required this.isim,
    required this.fotoUrl,
    this.boyut = 52,
    this.harfRengi = Renkler.metinIkincil,
  });

  static String basHarfler(String isim) {
    final parcalar = isim.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parcalar.isEmpty) return '?';
    final ilk = parcalar.first.characters.first;
    final son = parcalar.length > 1 ? parcalar.last.characters.first : '';
    return (ilk + son).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final yukseklik = boyut / enBoyOrani;
    final kose = BorderRadius.circular(boyut * 0.18);
    final harfler = Center(
      child: Text(
        basHarfler(isim),
        style: TextStyle(color: harfRengi, fontWeight: FontWeight.w700, fontSize: boyut * 0.33),
      ),
    );

    return Container(
      width: boyut,
      height: yukseklik,
      clipBehavior: Clip.antiAlias,
      // Açık arka planlı fotoğraflar koyu zeminde dağılmasın diye ince bir çerçeve
      foregroundDecoration: BoxDecoration(borderRadius: kose, border: Border.all(color: Renkler.kenar)),
      decoration: BoxDecoration(color: Renkler.yuzeyYuksek, borderRadius: kose),
      child: fotoUrl == null
          ? harfler
          : Image.network(
              fotoUrl!,
              width: boyut,
              height: yukseklik,
              // Oran aynı olduğu için cover bir şey kesmez; farklı boyutta gelen nadir fotoğrafları da boşluksuz doldurur
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              // Ekrandaki boyuta göre küçültülerek belleğe alınır
              cacheWidth: (boyut * MediaQuery.devicePixelRatioOf(context)).round(),
              // İlk kare gelene kadar baş harfler gösterilir (loadingBuilder ilk veri gelmeden boş kalıyordu)
              frameBuilder: (context, child, kare, senkron) => senkron || kare != null ? child : harfler,
              errorBuilder: (context, hata, iz) => harfler,
            ),
    );
  }
}
