import 'package:flutter/material.dart';
import '../theme/renkler.dart';

// Yuvarlak oyuncu fotoğrafı. Fotoğraf yoksa, yüklenirken ya da yüklenemezse baş harfler gösterilir.
// Fotoğraflar Transfermarkt'tan link olarak gelir, kopyaları tutulmaz.
class OyuncuFotografi extends StatelessWidget {
  final String isim;
  final String? fotoUrl;
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
    final harfler = Center(
      child: Text(
        basHarfler(isim),
        style: TextStyle(color: harfRengi, fontWeight: FontWeight.w700, fontSize: boyut * 0.33),
      ),
    );

    return Container(
      width: boyut,
      height: boyut,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(color: Renkler.yuzeyYuksek, shape: BoxShape.circle),
      child: fotoUrl == null
          ? harfler
          : Image.network(
              fotoUrl!,
              fit: BoxFit.cover,
              // Transfermarkt portreleri dikey: yüz üstte kaldığı için üstten hizalanır
              alignment: Alignment.topCenter,
              // Ekrandaki boyuta göre küçültülerek belleğe alınır
              cacheWidth: (boyut * MediaQuery.devicePixelRatioOf(context)).round(),
              loadingBuilder: (context, child, ilerleme) => ilerleme == null ? child : harfler,
              errorBuilder: (context, hata, iz) => harfler,
            ),
    );
  }
}
