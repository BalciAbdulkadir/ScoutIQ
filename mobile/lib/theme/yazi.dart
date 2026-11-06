import 'package:flutter/material.dart';
import 'renkler.dart';

// Yazı tipleri. Gövde metni temadan (Instrument Sans) gelir; başlıklar ve tebeşir yazısı buradan.
class Yazi {
  static const String baslikAilesi = 'BigShoulders';
  static const String tebesirAilesi = 'Kalam';
  static const String govdeAilesi = 'InstrumentSans';

  // Sıkışık, stadyum tabelası gibi başlık. Büyük harfle yazılması beklenir.
  static TextStyle baslik(double boyut, {Color renk = Renkler.metin, FontWeight kalinlik = FontWeight.w800}) =>
      TextStyle(
        fontFamily: baslikAilesi,
        fontSize: boyut,
        fontWeight: kalinlik,
        color: renk,
        height: 1,
        letterSpacing: boyut * 0.03,
      );

  // Küçük büyük harfli etiket (bölüm adı, "YENİ OYUNLARA" gibi)
  static TextStyle etiket({double boyut = 11, Color renk = Renkler.metinIkincil}) => TextStyle(
        fontFamily: baslikAilesi,
        fontSize: boyut,
        fontWeight: FontWeight.w700,
        color: renk,
        letterSpacing: boyut * 0.18,
        height: 1.1,
      );

  // Tahtaya elle yazılmış gibi: oyuncu isimleri, "Oyna", skor damgası
  static TextStyle tebesir(double boyut, {Color renk = Renkler.metin, FontWeight kalinlik = FontWeight.w700}) =>
      TextStyle(fontFamily: tebesirAilesi, fontSize: boyut, fontWeight: kalinlik, color: renk, height: 1.1);

  // Türkçe büyük harf: "Kesişim" -> "KESİŞİM" (Dart'ın toUpperCase'i i'yi I yapar)
  static String buyuk(String metin) => metin.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();

  // Rakamlar hizalı dursun (sayaç, skor)
  static const sabitRakam = [FontFeature.tabularFigures()];
}
