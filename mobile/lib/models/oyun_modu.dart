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
  // Doluysa mod birden fazla ayrı günlük oyundan oluşur (ör. Izgara'nın kolay/orta/zor tahtaları)
  final List<String>? altTipler;

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
  });

  // Bu modun veritabanındaki günlük oyun tipleri
  List<String> get oyunTipleri => altTipler ?? [?tip];

  // Zorluk seçilerek oynanan mod. Bu modlarda günde yalnızca bir zorluk oynanır.
  bool get zorluklu => altTipler != null;
}

// Zorluklu oyunlarda zorluktan sonra seçilen süre. Her zorluklu oyunda aynı dört seçenek vardır.
enum OyunSuresi {
  suresiz(null, 'Süresiz'),
  saniye30(30, '30 sn'),
  saniye60(60, '60 sn'),
  saniye90(90, '90 sn');

  final int? saniye; // null: süre sınırı yok
  final String ad;

  const OyunSuresi(this.saniye, this.ad);
}

// Hub'da gösterilen modlar. İlk faz: Kesişim, Bonservis ve Izgara.
// Bingo proje planında ileriki fazlar için öngörülüyor.
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
  ),
  OyunModu(
    baslik: 'Bingo',
    aciklama: 'Kartındaki özellikleri tamamla.',
    ikon: Icons.apps_rounded,
    cizim: TebesirCizimi.bingo,
    renk: Renkler.metinSoluk,
    durum: OyunDurumu.yakinda,
  ),
];
