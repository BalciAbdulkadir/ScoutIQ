// kesisim_cevap fonksiyonunun cevabı (034_skor_sunucuda.sql, 040_oyun_ac.sql). Skor ve ilerleme sunucuda yazılır.
class KesisimCevapSonucu {
  final bool dogru;
  final int skor; // Sunucudaki güncel skor
  final bool bitti; // Son soru cevaplandı, kayıt kapandı
  final bool sureDoldu; // Süre dolmuştu: cevap kabul edilmedi, oyun o anki skorla bitti
  // Oyun bitmediyse sıradaki soru: sorular tek tek gelir, sıradaki soru cevaptan önce telefona inmez
  final Map<String, dynamic>? siradakiSoru;

  const KesisimCevapSonucu({
    required this.dogru,
    required this.skor,
    required this.bitti,
    this.sureDoldu = false,
    this.siradakiSoru,
  });

  factory KesisimCevapSonucu.fromJson(Map<String, dynamic> json) {
    return KesisimCevapSonucu(
      dogru: json['dogru'] == true,
      skor: (json['skor'] as num).toInt(),
      bitti: json['bitti'] == true,
      sureDoldu: json['sure_doldu'] == true,
      siradakiSoru: json['siradaki_soru'] as Map<String, dynamic>?,
    );
  }
}
