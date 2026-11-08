import 'package:flutter/material.dart';
import '../theme/renkler.dart';
import '../widgets/tebesir.dart';

enum OyunDurumu { aktif, hazirlaniyor, yakinda }

class OyunModu {
  final String? tip; // Supabase'deki oyun_tipi değeri. Veritabanında henüz karşılığı olmayan modlar için null.
  final String baslik;
  final String aciklama;
  final IconData ikon;
  final TebesirCizimi? cizim; // Ana menüdeki tebeşir çizimi; boşsa ikon kullanılır
  final Color renk;
  final OyunDurumu durum;
  final int? maksimumSkor;
  // Doluysa mod birden fazla ayrı günlük oyundan oluşur: kolay, orta ve zor (ör. kesisim_kolay, kesisim_orta, kesisim_zor)
  final List<String>? altTipler;
  // Zorluk seçim sayfasında her zorluğun altında yazan açıklama, altTipler ile aynı sırada
  final List<String>? zorlukAciklamalari;
  // Oyun başlarken seçilebilen süreler
  final List<OyunSuresi> sureSecenekleri;

  const OyunModu({
    this.tip,
    required this.baslik,
    required this.aciklama,
    required this.ikon,
    this.cizim,
    required this.renk,
    required this.durum,
    this.maksimumSkor,
    this.altTipler,
    this.zorlukAciklamalari,
    this.sureSecenekleri = OyunSuresi.values,
  });

  // Bu modun veritabanındaki günlük oyun tipleri
  List<String> get oyunTipleri => altTipler ?? [?tip];

  // Zorluk seçilerek oynanan mod. Bu modlarda günde yalnızca bir zorluk oynanır.
  bool get zorluklu => altTipler != null;
}

// Zorluklu oyunlarda altTipler sırasıyla zorlukların adı
const zorlukAdlari = ['Kolay', 'Orta', 'Zor'];

// Kesişim ve Bonservis'te zorluk, soruların oyuncu kademesinden gelir (backend: Oyunlar/Zorluk.cs)
const _oyuncuZorluklari = [
  'Sadece ünlü oyuncular',
  'Yarısı ünlü, yarısı bilinen oyuncular',
  'Ünlü, bilinen ve az bilinen oyuncular',
];

// Oyun başlarken seçilen süre. Oyunların çoğunda dört seçenek de vardır; Bingo'da 30 saniye yoktur.
enum OyunSuresi {
  suresiz(null, 'Süresiz'),
  saniye30(30, '30 sn'),
  saniye60(60, '60 sn'),
  saniye90(90, '90 sn');

  final int? saniye; // null: süre sınırı yok
  final String ad;

  const OyunSuresi(this.saniye, this.ad);
}

// Hub'da gösterilen modlar: Kesişim, Bonservis, Izgara ve Bingo.
const List<OyunModu> oyunModlari = [
  OyunModu(
    tip: 'kesisim',
    baslik: 'Kesişim',
    aciklama: 'İki kulübün ortak oyuncusunu bul.',
    ikon: Icons.join_inner,
    cizim: TebesirCizimi.kesisim,
    renk: Renkler.kesisim,
    durum: OyunDurumu.aktif,
    maksimumSkor: 10,
    altTipler: ['kesisim_kolay', 'kesisim_orta', 'kesisim_zor'],
    zorlukAciklamalari: _oyuncuZorluklari,
  ),
  OyunModu(
    tip: 'bonservis',
    baslik: 'Bonservis',
    aciklama: 'Toplam bonservis daha mı az, daha mı fazla?',
    ikon: Icons.euro,
    cizim: TebesirCizimi.bonservis,
    renk: Renkler.bonservis,
    durum: OyunDurumu.aktif,
    maksimumSkor: 10, // 5 soru, her doğru 2 puan
    altTipler: ['bonservis_kolay', 'bonservis_orta', 'bonservis_zor'],
    zorlukAciklamalari: _oyuncuZorluklari,
  ),
  OyunModu(
    tip: 'izgara',
    baslik: 'Izgara',
    aciklama: 'Satır ve sütundaki takımlara uyan oyuncuları bul.',
    ikon: Icons.grid_view_rounded,
    cizim: TebesirCizimi.izgara,
    renk: Renkler.izgara,
    durum: OyunDurumu.aktif,
    maksimumSkor: 9,
    // Her zorluk ayrı bir tahta; kullanıcı günde bunlardan yalnızca birini seçip oynar
    altTipler: ['izgara_kolay', 'izgara_orta', 'izgara_zor'],
    // Zorluk açıklamaları IzgaraZorlugu'nda
  ),
  OyunModu(
    tip: 'bingo',
    baslik: 'Bingo',
    aciklama: 'Gelen oyuncuyu uyduğu kutuya koy, kartı doldur.',
    ikon: Icons.apps_rounded,
    cizim: TebesirCizimi.bingo,
    renk: Renkler.bingo,
    durum: OyunDurumu.aktif,
    maksimumSkor: 12,
    // Zorluk modu yoktur: 12 kutulu tek kart, destede ünlü ve bilinen oyuncular. Kart her zaman doldurulabilir.
    sureSecenekleri: [OyunSuresi.suresiz, OyunSuresi.saniye60, OyunSuresi.saniye90],
  ),
];
