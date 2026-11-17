// Top 10 oyununun verileri. Soru gunluk_oyunlar.soru_verisi'nden okunur (biçim: 029_top10.sql).
// Cevaplar soru verisinde yoktur; tahminler sunucuda kontrol edilir, liste oyun bitince açılır.

const top10Boyu = 10;
// Can sayısı: listede olmayan oyuncuyu tahmin etmek bir can götürür, canlar bitince oyun biter (031_top10_can.sql)
const top10Can = 3;

// Listedeki bir satırın ipucu: oyuncunun uyruğunun bayrağı
class Top10Satiri {
  final int sira;
  final String? ulke; // Transfermarkt'taki İngilizce ülke adı
  final String? bayrakUrl;

  const Top10Satiri({required this.sira, this.ulke, this.bayrakUrl});

  factory Top10Satiri.fromJson(Map<String, dynamic> json) {
    return Top10Satiri(
      sira: (json['sira'] as num).toInt(),
      ulke: json['ulke'] as String?,
      bayrakUrl: json['bayrak'] as String?,
    );
  }
}

// Günün sorusu: başlık ve 10 satırın bayrakları
class Top10Sorusu {
  final String baslik;
  final String? altBaslik; // Verinin dönemi ve tarihi: "2000'den bugüne · Kasım 2026 itibarıyla"
  final List<Top10Satiri> satirlar;

  const Top10Sorusu({required this.baslik, this.altBaslik, required this.satirlar});

  // Soru eksik ya da bozuksa null
  static Top10Sorusu? oku(Object? veri) {
    if (veri is! Map<String, dynamic>) return null;
    final baslik = veri['baslik'];
    final satirlar = veri['satirlar'];
    if (baslik is! String || satirlar is! List || satirlar.length != top10Boyu) return null;
    return Top10Sorusu(
      baslik: baslik,
      altBaslik: veri['alt_baslik'] as String?,
      satirlar: satirlar.cast<Map<String, dynamic>>().map(Top10Satiri.fromJson).toList()
        ..sort((a, b) => a.sira.compareTo(b.sira)),
    );
  }
}

// Listede bulunmuş (ya da oyun bitince açılmış) bir oyuncu
class Top10Oyuncusu {
  final String isim;
  final String? fotoUrl;
  final String? deger; // "222 M€", "1055 puan"

  const Top10Oyuncusu({required this.isim, this.fotoUrl, this.deger});
}

// top10_tahminleri tablosundaki bir satır. sira null: yanlış tahmin.
class Top10Tahmini {
  final String oyuncuIsim;
  final int? sira;

  const Top10Tahmini({required this.oyuncuIsim, this.sira});

  factory Top10Tahmini.fromJson(Map<String, dynamic> json) {
    return Top10Tahmini(oyuncuIsim: json['oyuncu_isim'] as String, sira: (json['sira'] as num?)?.toInt());
  }
}

// top10_tahmin fonksiyonunun cevabı
class Top10TahminSonucu {
  final bool dogru;
  final int? sira;
  final String? deger;
  final bool tekrar; // Oyuncu daha önce denenmiş: tahmin sayılmadı
  final String oyuncuIsim;
  final String? fotoUrl;
  final int skor;
  final int? kalanCan; // 031'den önceki sunucu göndermez: o zaman uygulama kendisi hesaplar
  final bool bitti;

  const Top10TahminSonucu({
    required this.dogru,
    this.sira,
    this.deger,
    this.tekrar = false,
    required this.oyuncuIsim,
    this.fotoUrl,
    required this.skor,
    this.kalanCan,
    required this.bitti,
  });

  factory Top10TahminSonucu.fromJson(Map<String, dynamic> json) {
    return Top10TahminSonucu(
      dogru: json['dogru'] == true,
      sira: (json['sira'] as num?)?.toInt(),
      deger: json['deger'] as String?,
      tekrar: json['tekrar'] == true,
      oyuncuIsim: json['oyuncu_isim'] as String,
      fotoUrl: json['foto_url'] as String?,
      skor: (json['skor'] as num).toInt(),
      kalanCan: (json['kalan_can'] as num?)?.toInt(),
      bitti: json['bitti'] == true,
    );
  }
}
