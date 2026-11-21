import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import '../theme/renkler.dart';

// Köşeleri yuvarlatılmış dikey oyuncu fotoğrafı. Fotoğraf yoksa, yüklenirken ya da yüklenemezse baş harfler gösterilir.
// Fotoğraflar Transfermarkt'tan link olarak gelir, kopyaları tutulmaz.
class OyuncuFotografi extends StatelessWidget {
  // Transfermarkt portreleri 300x390 (en/boy 1:1.3). Çerçeve aynı oranda olduğu için fotoğraf kırpılmadan sığar.
  static const double enBoyOrani = 300 / 390;
  // Yuvarlak fotoğrafta portrenin eni (dairenin çapına oranla) ve dairenin tepesine göre yeri. Transfermarkt'ın büyük
  // portrelerinde yüz fotoğrafın neredeyse tamamını kaplar: portre daire genişliğinde olunca saçın üstü ve çene
  // kesiliyordu. Portre küçültülüp dikeyde ortalanınca başın tamamı daireye girer.
  static const double _yuvarlakOlcek = 0.8;
  static const double _yuvarlakKayma = -0.02;

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

  // Daire içinde oyuncu fotoğrafı. Portre küçültülüp ortalanır, başın tamamı daireye sığar; kenarlarda kalan boşluğu
  // aynı fotoğrafın bulanık hâli doldurur (düz renk zeminde portrenin dikdörtgen kenarları görünüyordu).
  // Fotoğraf yoksa, yüklenirken ya da yüklenemezse dairenin ortasında baş harfler.
  static Widget yuvarlak({
    Key? key,
    required String isim,
    required String? fotoUrl,
    double boyut = 32,
    Color harfRengi = Renkler.metinIkincil,
  }) {
    return Container(
      key: key,
      width: boyut,
      height: boyut,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(color: Renkler.yuzeyYuksek, shape: BoxShape.circle),
      child: _YuvarlakIcerik(isim: isim, fotoUrl: fotoUrl, daire: boyut, harfRengi: harfRengi),
    );
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

// Yuvarlak fotoğrafın içi: baş harfler, üstünde bulanık zemin ve küçültülmüş portre. Fotoğraf gelince baş harfleri örter.
class _YuvarlakIcerik extends StatelessWidget {
  final String isim;
  final String? fotoUrl;
  final double daire;
  final Color harfRengi;

  const _YuvarlakIcerik({required this.isim, required this.fotoUrl, required this.daire, required this.harfRengi});

  @override
  Widget build(BuildContext context) {
    final harfler = Center(
      child: Text(
        OyuncuFotografi.basHarfler(isim),
        style: TextStyle(color: harfRengi, fontWeight: FontWeight.w700, fontSize: daire * 0.36),
      ),
    );
    if (fotoUrl == null) return harfler;

    final en = daire * OyuncuFotografi._yuvarlakOlcek;
    final cacheWidth = (daire * MediaQuery.devicePixelRatioOf(context)).round();
    // İlk kare gelmeden ya da hata olursa boş kalır: alttaki baş harfler görünür
    Widget yuklenince(BuildContext context, Widget child, int? kare, bool senkron) =>
        senkron || kare != null ? child : const SizedBox.shrink();
    Widget bos(BuildContext context, Object hata, StackTrace? iz) => const SizedBox.shrink();

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: harfler),
        // Bulanık zemin: daireden taşacak kadar büyük, kenarlarda bulanıklık saydamlaşmasın
        Positioned(
          left: -daire * 0.2,
          top: -daire * 0.2,
          width: daire * 1.4,
          height: daire * 1.4,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: daire * 0.12, sigmaY: daire * 0.12),
            child: Image.network(
              fotoUrl!,
              fit: BoxFit.cover,
              cacheWidth: cacheWidth,
              frameBuilder: yuklenince,
              errorBuilder: bos,
            ),
          ),
        ),
        Positioned(
          left: (daire - en) / 2,
          top: daire * OyuncuFotografi._yuvarlakKayma,
          width: en,
          height: en / OyuncuFotografi.enBoyOrani,
          child: Image.network(
            fotoUrl!,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            cacheWidth: cacheWidth,
            frameBuilder: yuklenince,
            errorBuilder: bos,
          ),
        ),
      ],
    );
  }
}
