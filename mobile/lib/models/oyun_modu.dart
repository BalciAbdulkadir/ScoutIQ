import 'package:flutter/material.dart';
import '../theme/renkler.dart';

enum OyunDurumu { aktif, hazirlaniyor, yakinda }

class OyunModu {
  final String? tip; // Supabase'deki oyun_tipi değeri. Veritabanında henüz karşılığı olmayan modlar için null.
  final String baslik;
  final String aciklama;
  final IconData ikon;
  final Color renk;
  final OyunDurumu durum;
  final int? maksimumSkor;

  const OyunModu({
    this.tip,
    required this.baslik,
    required this.aciklama,
    required this.ikon,
    required this.renk,
    required this.durum,
    this.maksimumSkor,
  });
}

// Hub'da gösterilen modlar. İlk faz: Kesişim ve Bonservis.
// Izgara ve Bingo proje planında ileriki fazlar için öngörülüyor.
const List<OyunModu> oyunModlari = [
  OyunModu(
    tip: 'kesisim',
    baslik: 'Kesişim',
    aciklama: 'İki takımda da forma giymiş bir oyuncu bul.',
    ikon: Icons.join_inner,
    renk: Renkler.kesisim,
    durum: OyunDurumu.aktif,
    maksimumSkor: 10,
  ),
  OyunModu(
    tip: 'bonservis',
    baslik: 'Bonservis',
    aciklama: 'Kariyerindeki toplam bonservis daha mı fazla, daha mı az?',
    ikon: Icons.euro,
    renk: Renkler.bonservis,
    durum: OyunDurumu.aktif,
    maksimumSkor: 5,
  ),
  OyunModu(
    baslik: '9\'lu Izgara',
    aciklama: 'Satır ve sütunlardaki koşullara uyan oyuncularla ızgarayı doldur.',
    ikon: Icons.grid_view_rounded,
    renk: Renkler.metinSoluk,
    durum: OyunDurumu.yakinda,
  ),
  OyunModu(
    baslik: 'Bingo',
    aciklama: 'Kartındaki özellikleri taşıyan oyuncuları bul.',
    ikon: Icons.apps_rounded,
    renk: Renkler.metinSoluk,
    durum: OyunDurumu.yakinda,
  ),
];
