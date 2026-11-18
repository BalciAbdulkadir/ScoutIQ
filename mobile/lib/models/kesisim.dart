// kesisim_cevap fonksiyonunun cevabı (033_skor_sunucuda.sql). Skor ve ilerleme sunucuda yazılır.
class KesisimCevapSonucu {
  final bool dogru;
  final int skor; // Sunucudaki güncel skor
  final bool bitti; // Son soru cevaplandı, kayıt kapandı
  final bool sureDoldu; // Süre dolmuştu: cevap kabul edilmedi, oyun o anki skorla bitti

  const KesisimCevapSonucu({required this.dogru, required this.skor, required this.bitti, this.sureDoldu = false});

  factory KesisimCevapSonucu.fromJson(Map<String, dynamic> json) {
    return KesisimCevapSonucu(
      dogru: json['dogru'] == true,
      skor: (json['skor'] as num).toInt(),
      bitti: json['bitti'] == true,
      sureDoldu: json['sure_doldu'] == true,
    );
  }
}
