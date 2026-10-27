// Cevap kutusunun altındaki öneri listesindeki bir oyuncu (oyuncu_ara RPC'sinin bir satırı)
class OyuncuOneri {
  final String id;
  final String isim;
  final String? fotoUrl;

  const OyuncuOneri({required this.id, required this.isim, this.fotoUrl});

  factory OyuncuOneri.fromJson(Map<String, dynamic> json) {
    return OyuncuOneri(id: json['id'] as String, isim: json['isim'] as String, fotoUrl: json['foto_url'] as String?);
  }
}
