// Bonservis oyunundaki bir oyuncu ve kariyeri boyunca ödenen toplam bonservis (Euro)
class BonservisOyuncusu {
  final String id;
  final String isim;
  // Tahmin edilen (sağdaki) oyuncunun bedeli soruyla gelmez, tahminden sonra sunucudan gelir: o zamana kadar null.
  // Bedeli baştan görünen (soldaki) oyuncuda her zaman doludur.
  final int? toplamBonservis;
  final String? fotoUrl; // Fotoğrafı olmayan oyuncularda ve fotoğraflar eklenmeden önceki oyunlarda null

  const BonservisOyuncusu({required this.id, required this.isim, required this.toplamBonservis, this.fotoUrl});

  BonservisOyuncusu bedelle(int bedel) => BonservisOyuncusu(id: id, isim: isim, toplamBonservis: bedel, fotoUrl: fotoUrl);
}

// Bir soru: bedeli görünen referans oyuncu ve bedeli tahmin edilecek rakip
class BonservisSorusu {
  final BonservisOyuncusu referans;
  final BonservisOyuncusu rakip;

  const BonservisSorusu({required this.referans, required this.rakip});

  // Rakibin bedeli açıldıysa (tahminden sonra) karşılaştırma; açılmadıysa null
  bool? get rakipDahaPahali {
    final r = rakip.toplamBonservis, ref = referans.toplamBonservis;
    return r == null || ref == null ? null : r > ref;
  }

  BonservisOyuncusu get pahaliOlan => rakipDahaPahali == true ? rakip : referans;

  // İki bedel arasındaki fark; rakibin bedeli açılmadıysa null
  int? get fark {
    final r = rakip.toplamBonservis, ref = referans.toplamBonservis;
    return r == null || ref == null ? null : (r - ref).abs();
  }

  BonservisSorusu rakipBedeliyle(int bedel) => BonservisSorusu(referans: referans, rakip: rakip.bedelle(bedel));
}

// Backend'in soru_verisi'ni sorulara çevirir. Her soru bağımsız iki oyuncudur: oyuncu_a (sol) bedeliyle
// gösterilir, oyuncu_b (sağ) için tahmin istenir. Doğru cevabın hangi tarafta olacağını backend rastgele seçer.
// Sağdaki oyuncunun bedeli yeni sorularda yoktur (034_skor_sunucuda.sql); eski sorularda varsa okunur ama
// ekranda tahminden önce gösterilmez.
List<BonservisSorusu> bonservisSorulariniOku(List<dynamic> soruVerisi) {
  BonservisOyuncusu oyuncu(Map<String, dynamic> soru, String taraf) => BonservisOyuncusu(
        id: soru['oyuncu_${taraf}_id'] as String,
        isim: soru['oyuncu_$taraf'] as String,
        toplamBonservis: (soru['oyuncu_${taraf}_bonservis'] as num?)?.toInt(),
        fotoUrl: soru['oyuncu_${taraf}_foto'] as String?,
      );

  return [
    for (final ham in soruVerisi)
      BonservisSorusu(referans: oyuncu(ham as Map<String, dynamic>, 'a'), rakip: oyuncu(ham, 'b')),
  ];
}

// bonservis_tahmin fonksiyonunun cevabı (034_skor_sunucuda.sql, 040_oyun_ac.sql). Skor ve ilerleme sunucuda yazılır.
class BonservisTahminSonucu {
  final bool dogru;
  final int? rakipBonservis; // Tahmin edilen oyuncunun bedeli; süre dolduysa null
  final int skor; // Sunucudaki güncel skor
  final bool bitti; // Son soru cevaplandı, kayıt kapandı
  final bool sureDoldu; // Süre dolmuştu: tahmin kabul edilmedi, oyun o anki skorla bitti
  // Oyun bitmediyse sıradaki soru (soru verisi biçiminde): sorular tek tek gelir
  final Map<String, dynamic>? siradakiSoru;

  const BonservisTahminSonucu({
    required this.dogru,
    this.rakipBonservis,
    required this.skor,
    required this.bitti,
    this.sureDoldu = false,
    this.siradakiSoru,
  });

  factory BonservisTahminSonucu.fromJson(Map<String, dynamic> json) {
    return BonservisTahminSonucu(
      dogru: json['dogru'] == true,
      rakipBonservis: (json['rakip_bonservis'] as num?)?.toInt(),
      skor: (json['skor'] as num).toInt(),
      bitti: json['bitti'] == true,
      sureDoldu: json['sure_doldu'] == true,
      siradakiSoru: json['siradaki_soru'] as Map<String, dynamic>?,
    );
  }
}

// 79000000 -> "79 M€", 77400000 -> "77,4 M€". Bedel bilinmiyorsa "? M€".
String bonservisMetni(int? euro) {
  if (euro == null) return '? M€';
  final milyon = euro / 1000000;
  final metin = milyon == milyon.roundToDouble() ? milyon.toStringAsFixed(0) : milyon.toStringAsFixed(1);
  return '${metin.replaceAll('.', ',')} M€';
}
