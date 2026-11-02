import 'package:flutter/material.dart';

// Uygulama genelindeki siyah/yeşil karanlık tema renkleri.
// Ekranlar renkleri doğrudan yazmaz, buradan alır.
class Renkler {
  static const Color arkaPlan = Color(0xFF0A1711);
  static const Color yuzey = Color(0xFF11241A); // Kartlar
  static const Color yuzeyYuksek = Color(0xFF173023); // Kart içindeki kutular, giriş alanları
  static const Color kenar = Color(0xFF213B2D);
  static const Color logoZemini = Color(0xFFEEF2EF); // Kulüp logolarının arkasındaki açık daire

  static const Color metin = Color(0xFFF1F5F2);
  static const Color metinIkincil = Color(0xFFA7B8AE);
  static const Color metinSoluk = Color(0xFF6E8277);

  static const Color basari = Color(0xFF4ADE80);
  static const Color hata = Color(0xFFF87171);

  // Oyun modlarının kendi renkleri
  static const Color kesisim = Color(0xFF4ADE80);
  static const Color bonservis = Color(0xFF38BDF8);
  static const Color izgara = Color(0xFFA78BFA);

  // Zorluk etiketleri
  static const Color orta = Color(0xFFFBBF24);
}
