// Bingo oyununun verileri. Kart ve deste gunluk_oyunlar.soru_verisi'nden okunur (biçim: 020_bingo.sql).
// Hangi oyuncunun hangi kutuya uyduğu soru verisinde yoktur; hamleler sunucuda kontrol edilir.

const bingoBoyutu = 4;
const bingoHucreSayisi = bingoBoyutu * bingoBoyutu;

enum BingoKategoriTipi { kulup, milli, lig, basari }

// Karttaki bir kutunun kategorisi: bir kulüp, milli takım, lig ya da başarı
class BingoKategorisi {
  final BingoKategoriTipi tip;
  final String isim;
  final String? logoUrl; // Kulüp logosu, bayrak, lig ya da kupa logosu; yoksa simge gösterilir

  const BingoKategorisi({required this.tip, required this.isim, this.logoUrl});

  // Kutuda ismin altında yazan, kategorinin ne istediği
  String get aciklama => switch (tip) {
        BingoKategoriTipi.kulup => 'kulübünde oynadı',
        BingoKategoriTipi.milli => 'milli takımında oynadı',
        BingoKategoriTipi.lig => 'liginde oynadı',
        BingoKategoriTipi.basari => 'kazandı',
      };

  factory BingoKategorisi.fromJson(Map<String, dynamic> json) {
    return BingoKategorisi(
      tip: switch (json['tip']) {
        'kulup' => BingoKategoriTipi.kulup,
        'milli' => BingoKategoriTipi.milli,
        'lig' => BingoKategoriTipi.lig,
        _ => BingoKategoriTipi.basari,
      },
      isim: json['isim'] as String,
      logoUrl: json['logo'] as String?,
    );
  }
}

// Destedeki bir oyuncu
class BingoOyuncusu {
  final String isim;
  final String? fotoUrl;

  const BingoOyuncusu({required this.isim, this.fotoUrl});

  factory BingoOyuncusu.fromJson(Map<String, dynamic> json) {
    return BingoOyuncusu(isim: json['isim'] as String, fotoUrl: json['foto'] as String?);
  }
}

// Günün kartı: 16 kategori ve sırayla gelecek oyuncular
class BingoKarti {
  final List<BingoKategorisi> hucreler;
  final List<BingoOyuncusu> deste;

  const BingoKarti({required this.hucreler, required this.deste});

  // Kart eksik ya da bozuksa null
  static BingoKarti? oku(Object? veri) {
    if (veri is! Map<String, dynamic>) return null;
    final hucreler = veri['hucreler'];
    final deste = veri['oyuncular'];
    if (hucreler is! List || hucreler.length != bingoHucreSayisi || deste is! List || deste.isEmpty) return null;
    return BingoKarti(
      hucreler: hucreler.cast<Map<String, dynamic>>().map(BingoKategorisi.fromJson).toList(),
      deste: deste.cast<Map<String, dynamic>>().map(BingoOyuncusu.fromJson).toList(),
    );
  }
}

// bingo_hamleleri tablosundaki bir satır. hucre null: pas.
class BingoHamlesi {
  final int sira; // Destedeki sıra, 1'den başlar
  final int? hucre;
  final bool dogru;

  const BingoHamlesi({required this.sira, this.hucre, required this.dogru});

  factory BingoHamlesi.fromJson(Map<String, dynamic> json) {
    return BingoHamlesi(
      sira: (json['sira'] as num).toInt(),
      hucre: (json['hucre'] as num?)?.toInt(),
      dogru: json['dogru'] == true,
    );
  }
}

// bingo_hamle fonksiyonunun cevabı
class BingoHamleSonucu {
  final bool dogru;
  final int? hucre; // null: pas
  final int skor;
  final bool bitti;
  final bool sureDoldu; // Süre dolduğu için hamle kabul edilmedi, oyun bitti

  const BingoHamleSonucu({required this.dogru, this.hucre, required this.skor, required this.bitti, this.sureDoldu = false});

  factory BingoHamleSonucu.fromJson(Map<String, dynamic> json) {
    return BingoHamleSonucu(
      dogru: json['dogru'] == true,
      hucre: (json['hucre'] as num?)?.toInt(),
      skor: (json['skor'] as num).toInt(),
      bitti: json['bitti'] == true,
      sureDoldu: json['sure_doldu'] == true,
    );
  }
}
