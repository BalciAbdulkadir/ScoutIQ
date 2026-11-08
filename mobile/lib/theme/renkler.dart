import 'package:flutter/material.dart';

// Taktik tahtası teması: koyu çuha yeşili tahta, üstünde tebeşir beyazı ve tebeşir sarısı.
// Ekranlar renkleri doğrudan yazmaz, buradan alır.
class Renkler {
  static const Color arkaPlan = Color(0xFF123627); // Tahta
  static const Color arkaPlanAcik = Color(0xFF1B4A37); // Tahtanın üstüne vuran ışık (degrade)
  static const Color yuzey = Color(0xFF163D2D); // Kutucuk, kart
  static const Color yuzeyYuksek = Color(0xFF1C4636); // Kart içindeki kutular, alt sayfalar
  static const Color kenar = Color(0xFF3F6153); // Soluk tebeşir çizgisi
  static const Color logoZemini = Color(0xFFEEF0E6); // Armaların arkasındaki tebeşir beyazı daire

  static const Color metin = Color(0xFFEEF0E6); // Tebeşir beyazı
  static const Color metinIkincil = Color(0xFFACB8AD);
  static const Color metinSoluk = Color(0xFF758A7D);

  static const Color vurgu = Color(0xFFF3D36B); // Tebeşir sarısı: "Oyna", seçimler, yeni yazılan isim

  static const Color basari = Color(0xFF9BE3A8); // Doğru
  static const Color hata = Color(0xFFF19A86); // Yanlış

  // Oyun modlarının vurgusu. Hepsi aynı tebeşir sarısı: modları renk değil kendi tebeşir çizimleri ayırır.
  static const Color kesisim = vurgu;
  static const Color bonservis = vurgu;
  static const Color izgara = vurgu;
  static const Color bingo = vurgu;

  // Zorluk etiketleri
  static const Color kolay = basari;
  static const Color orta = vurgu;
  static const Color zor = hata;
}
