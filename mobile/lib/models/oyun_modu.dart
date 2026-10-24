import 'package:flutter/material.dart';

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

// Hub'da gösterilen modlar. İlk faz: Kesişim ve Bonservis. Diğerleri ileriki fazlarda.
const List<OyunModu> oyunModlari = [
  OyunModu(
    tip: 'kesisim',
    baslik: 'Kesişim',
    aciklama: 'İki takımda da forma giymiş oyuncuyu bul.',
    ikon: Icons.sync_alt,
    renk: Colors.greenAccent,
    durum: OyunDurumu.aktif,
    maksimumSkor: 10,
  ),
  OyunModu(
    tip: 'bonservis',
    baslik: 'Bonservis',
    aciklama: 'Kariyerindeki toplam bonservis daha mı fazla, daha mı az?',
    ikon: Icons.attach_money,
    renk: Colors.lightBlueAccent,
    durum: OyunDurumu.aktif,
    maksimumSkor: 5,
  ),
  OyunModu(
    baslik: 'Kariyer Yolu',
    aciklama: 'Kulüplerinden oyuncuyu tahmin et.',
    ikon: Icons.route,
    renk: Colors.grey,
    durum: OyunDurumu.yakinda,
  ),
  OyunModu(
    baslik: 'Kimlik',
    aciklama: 'İpuçlarından oyuncuyu bul.',
    ikon: Icons.person_search,
    renk: Colors.grey,
    durum: OyunDurumu.yakinda,
  ),
  OyunModu(
    baslik: '9\'lu Izgara',
    aciklama: 'Izgarayı doğru oyuncularla doldur.',
    ikon: Icons.grid_3x3,
    renk: Colors.grey,
    durum: OyunDurumu.yakinda,
  ),
];
