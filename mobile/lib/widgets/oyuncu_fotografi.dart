import 'package:flutter/material.dart';
import '../theme/renkler.dart';

// Köşeleri yuvarlatılmış dikey oyuncu fotoğrafı. Fotoğraf yoksa, yüklenirken ya da yüklenemezse baş harfler gösterilir.
// Fotoğraflar Transfermarkt'tan link olarak gelir, kopyaları tutulmaz.
class OyuncuFotografi extends StatelessWidget {
  // Transfermarkt portreleri 300x390 (en/boy 1:1.3). Çerçeve aynı oranda olduğu için fotoğraf kırpılmadan sığar.
  static const double enBoyOrani = 300 / 390;
  // Yuvarlak fotoğrafta portrenin dairenin tepesinden ne kadar aşağıda başladığı (dairenin çapına oranla)
  static const double _yuvarlakKayma = 0.07;

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

  // Daire içinde oyuncu fotoğrafı. Transfermarkt portrelerinde saçın üstü fotoğrafın üst kenarına çok yakın olduğu için
  // fotoğraf dairenin tepesinden başlarsa saç dairenin dar üst kısmında kesilir. Fotoğraf dairenin genişliğinde kalır,
  // biraz aşağı kaydırılır: baş dairenin içine sığar, fotoğrafın kenarları görünmez, çene altı dairenin alt kenarında kesilir.
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
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: boyut * _yuvarlakKayma,
            child: _YuvarlakIcerik(isim: isim, fotoUrl: fotoUrl, en: boyut, harfRengi: harfRengi, daire: boyut),
          ),
        ],
      ),
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

// Yuvarlak fotoğrafın içi: küçültülmüş portre; fotoğraf yoksa ya da yüklenemezse dairenin ortasında baş harfler
class _YuvarlakIcerik extends StatelessWidget {
  final String isim;
  final String? fotoUrl;
  final double en;
  final double daire;
  final Color harfRengi;

  const _YuvarlakIcerik({required this.isim, required this.fotoUrl, required this.en, required this.daire, required this.harfRengi});

  @override
  Widget build(BuildContext context) {
    final yukseklik = en / OyuncuFotografi.enBoyOrani;
    // Baş harfler fotoğrafın değil dairenin ortasında dursun: kutu daireye göre yukarı kaydırılır
    final harfler = Transform.translate(
      offset: Offset(0, -daire * OyuncuFotografi._yuvarlakKayma),
      child: SizedBox(
        width: en,
        height: daire,
        child: Center(
          child: Text(
            OyuncuFotografi.basHarfler(isim),
            style: TextStyle(color: harfRengi, fontWeight: FontWeight.w700, fontSize: daire * 0.36),
          ),
        ),
      ),
    );
    if (fotoUrl == null) return harfler;
    return Image.network(
      fotoUrl!,
      width: en,
      height: yukseklik,
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      cacheWidth: (en * MediaQuery.devicePixelRatioOf(context)).round(),
      frameBuilder: (context, child, kare, senkron) => senkron || kare != null ? child : harfler,
      errorBuilder: (context, hata, iz) => harfler,
    );
  }
}
