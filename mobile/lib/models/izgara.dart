// 3x3 Izgara oyununun verileri. Tahta gunluk_oyunlar.soru_verisi'nden okunur (biçim: 011_izgara.sql).

const izgaraBoyutu = 3;
const izgaraHakSayisi = 9;

// Kolay, orta ve zor ayrı oyunlardır; her biri günde bir kez oynanır
enum IzgaraZorlugu {
  kolay('izgara_kolay', 'Kolay', 'Sadece kulüpler'),
  orta('izgara_orta', 'Orta', 'Kulüpler ve tanınmış milli takımlar'),
  zor('izgara_zor', 'Zor', 'Kulüpler ve diğer milli takımlar');

  final String oyunTipi;
  final String ad;
  final String aciklama;

  const IzgaraZorlugu(this.oyunTipi, this.ad, this.aciklama);
}

// Satır ya da sütun başlığı: bir kulüp ya da bir milli takım
class IzgaraBasligi {
  final bool milli;
  final String isim;
  final String? logoUrl;

  const IzgaraBasligi({required this.milli, required this.isim, this.logoUrl});

  factory IzgaraBasligi.fromJson(Map<String, dynamic> json) {
    final milli = json['tip'] == 'milli';
    final tmId = json['tm_id'] as String?;
    return IzgaraBasligi(
      milli: milli,
      isim: json['isim'] as String? ?? '—',
      // Milli takımların logosu tahtada yok; Transfermarkt'taki federasyon arması kullanılır.
      // Bulunamazsa uygulamada bayrak ikonu gösterilir.
      logoUrl: milli
          ? (tmId == null ? null : 'https://tmssl.akamaized.net/images/wappen/head/$tmId.png')
          : json['logo'] as String?,
    );
  }
}

class IzgaraTahtasi {
  final List<IzgaraBasligi> satirlar;
  final List<IzgaraBasligi> sutunlar;

  const IzgaraTahtasi({required this.satirlar, required this.sutunlar});

  // Tahta eksik ya da bozuksa null
  static IzgaraTahtasi? oku(Object? veri) {
    if (veri is! Map<String, dynamic>) return null;
    List<IzgaraBasligi>? basliklar(Object? liste) {
      if (liste is! List || liste.length != izgaraBoyutu) return null;
      return liste.cast<Map<String, dynamic>>().map(IzgaraBasligi.fromJson).toList();
    }

    final satirlar = basliklar(veri['satirlar']);
    final sutunlar = basliklar(veri['sutunlar']);
    if (satirlar == null || sutunlar == null) return null;
    return IzgaraTahtasi(satirlar: satirlar, sutunlar: sutunlar);
  }

  IzgaraBasligi satiri(int hucre) => satirlar[hucre ~/ izgaraBoyutu];
  IzgaraBasligi sutunu(int hucre) => sutunlar[hucre % izgaraBoyutu];
}

// Hücreye yerleşmiş oyuncu
class IzgaraOyuncusu {
  final String isim;
  final String? fotoUrl;

  const IzgaraOyuncusu({required this.isim, this.fotoUrl});
}

// izgara_tahminleri tablosundaki bir satır. hucre null: yanlış tahmin.
class IzgaraTahmini {
  final int sira;
  final String oyuncuIsim;
  final int? hucre;
  final String? fotoUrl;

  const IzgaraTahmini({required this.sira, required this.oyuncuIsim, this.hucre, this.fotoUrl});

  factory IzgaraTahmini.fromJson(Map<String, dynamic> json) {
    final oyuncu = json['oyuncular'];
    return IzgaraTahmini(
      sira: (json['sira'] as num).toInt(),
      oyuncuIsim: json['oyuncu_isim'] as String,
      hucre: (json['hucre'] as num?)?.toInt(),
      fotoUrl: oyuncu is Map<String, dynamic> ? oyuncu['foto_url'] as String? : null,
    );
  }
}

// izgara_tahmin fonksiyonunun cevabı
class IzgaraTahminSonucu {
  final bool dogru;
  final int? hucre;
  final bool tekrar; // Oyuncu bu tahtada zaten kullanılmış: hak düşmedi
  final String oyuncuIsim;
  final String? fotoUrl;
  final int kalanHak;
  final int skor;
  final bool bitti;

  const IzgaraTahminSonucu({
    required this.dogru,
    this.hucre,
    this.tekrar = false,
    required this.oyuncuIsim,
    this.fotoUrl,
    required this.kalanHak,
    required this.skor,
    required this.bitti,
  });

  factory IzgaraTahminSonucu.fromJson(Map<String, dynamic> json) {
    return IzgaraTahminSonucu(
      dogru: json['dogru'] == true,
      hucre: (json['hucre'] as num?)?.toInt(),
      tekrar: json['tekrar'] == true,
      oyuncuIsim: json['oyuncu_isim'] as String,
      fotoUrl: json['foto_url'] as String?,
      kalanHak: (json['kalan_hak'] as num).toInt(),
      skor: (json['skor'] as num).toInt(),
      bitti: json['bitti'] == true,
    );
  }
}
