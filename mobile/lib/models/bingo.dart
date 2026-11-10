// Bingo oyununun verileri. Kart ve deste gunluk_oyunlar.soru_verisi'nden okunur (biçim: 020_bingo.sql).
// Hangi oyuncunun hangi kutuya uyduğu soru verisinde yoktur; hamleler sunucuda kontrol edilir.

// Kartın kutu sayısı: günün kartı 12 kutudur (4 satır, 3 sütun, 021_bingo_tek_mod.sql). Tek modlu Bingo'dan önce
// üretilmiş 16 kutulu (4x4) kartlar da okunur.
const bingoKutuSayilari = {12, 16};

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

// Günün kartı: 12 kategori ve sırayla gelecek oyuncular
class BingoKarti {
  final List<BingoKategorisi> hucreler;
  final List<BingoOyuncusu> deste;

  const BingoKarti({required this.hucreler, required this.deste});

  int get hucreSayisi => hucreler.length;

  // 12 kutu 4 satır x 3 sütun, eski 16 kutulu kart 4x4 dizilir
  int get sutunSayisi => hucreSayisi > 12 ? 4 : 3;
  int get satirSayisi => (hucreSayisi / sutunSayisi).ceil();

  // Kart eksik ya da bozuksa null
  static BingoKarti? oku(Object? veri) {
    if (veri is! Map<String, dynamic>) return null;
    final hucreler = veri['hucreler'];
    final deste = veri['oyuncular'];
    if (hucreler is! List || !bingoKutuSayilari.contains(hucreler.length) || deste is! List || deste.isEmpty) return null;
    return BingoKarti(
      hucreler: hucreler.cast<Map<String, dynamic>>().map(BingoKategorisi.fromJson).toList(),
      deste: deste.cast<Map<String, dynamic>>().map(BingoOyuncusu.fromJson).toList(),
    );
  }
}

// Destede sıra döner (023_bingo_sinirsiz_pas.sql'deki bingo_siradaki ile aynı): son gelen oyuncudan sonraki,
// henüz yerleşmemiş ilk oyuncu; destenin sonundan başa dönülür. Pas geçilen oyuncu böylece sırası gelince tekrar gelir.
// Sıralar 1'den başlar; son 0 ise henüz oyuncu gelmemiştir. Yerleşmemiş oyuncu kalmadıysa null.
int? bingoSiradaki({required int desteBoyutu, required Set<int> yerlesenler, required int son}) {
  for (var adim = 1; adim <= desteBoyutu; adim++) {
    final sira = (son + adim - 1) % desteBoyutu + 1;
    if (!yerlesenler.contains(sira)) return sira;
  }
  return null;
}

// bingo_hamleleri tablosundaki bir satır. hucre null: pas.
class BingoHamlesi {
  final int sira; // Kullanıcının kaçıncı hamlesi, 1'den başlar
  final int oyuncu; // Hamlede gelen oyuncunun destedeki sırası, 1'den başlar
  final int? hucre;
  final bool dogru;

  const BingoHamlesi({required this.sira, int? oyuncu, this.hucre, required this.dogru}) : oyuncu = oyuncu ?? sira;

  factory BingoHamlesi.fromJson(Map<String, dynamic> json) {
    return BingoHamlesi(
      sira: (json['sira'] as num).toInt(),
      // 023'ten önceki hamlelerde oyuncu kolonu yoktu: destedeki sıra hamle sırasıyla aynıydı
      oyuncu: (json['oyuncu'] as num?)?.toInt(),
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
  final int? siradaki; // Sunucuya göre sıradaki oyuncunun destedeki sırası; eski sunucu göndermez

  const BingoHamleSonucu({
    required this.dogru,
    this.hucre,
    required this.skor,
    required this.bitti,
    this.sureDoldu = false,
    this.siradaki,
  });

  factory BingoHamleSonucu.fromJson(Map<String, dynamic> json) {
    return BingoHamleSonucu(
      dogru: json['dogru'] == true,
      hucre: (json['hucre'] as num?)?.toInt(),
      skor: (json['skor'] as num).toInt(),
      bitti: json['bitti'] == true,
      sureDoldu: json['sure_doldu'] == true,
      siradaki: (json['siradaki'] as num?)?.toInt(),
    );
  }
}
