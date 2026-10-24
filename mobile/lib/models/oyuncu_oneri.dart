// Cevap kutusunun altındaki öneri listesindeki bir oyuncu (oyuncu_ara RPC'sinin bir satırı)
class OyuncuOneri {
  final String id;
  final String isim;

  const OyuncuOneri({required this.id, required this.isim});

  factory OyuncuOneri.fromJson(Map<String, dynamic> json) {
    return OyuncuOneri(id: json['id'] as String, isim: json['isim'] as String);
  }
}
