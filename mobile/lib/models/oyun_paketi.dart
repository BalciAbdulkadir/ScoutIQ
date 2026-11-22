// oyun_ac fonksiyonunun cevabı (040_oyun_ac.sql). Soru, kayıt ve süre tek adımda sunucuda açılır: kayıt yoksa açılır
// ve seçilen süre aynı anda başlar; kayıt varsa yeni süre yok sayılır, oyun kaldığı yerden döner.
// Açık oyunda henüz sırası gelmemiş soru gelmez: Kesişim ve Bonservis'te cevaplanmış sorular + sıradaki soru,
// Bingo'da destenin görülmüş oyuncuları (görülmemişlerin yeri null). Bitmiş oyunda soru verisinin tamamı gelir.
enum OyunPaketiDurumu { yok, acik, bitti }

class OyunPaketi {
  final OyunPaketiDurumu durum;
  final bool yeni; // Kayıt bu çağrıda açıldı: oyun yeni başladı
  final String? oyunId;
  final String? tarih; // Oyun günü (Türkiye saatiyle), sunucudan
  final int skor;
  final List<Map<String, dynamic>> ilerleme; // Kesişim ve Bonservis'te cevaplanan sorular, sırayla
  final int? sure; // Süreli oyunda seçilen toplam süre (saniye); süresizse null
  final int? kalan; // Süreli oyunda sunucuya göre kalan süre (saniye)
  final bool sureDoldu; // Oyun kapalıyken süre dolmuştu, kayıt bu çağrıda kapatıldı
  final int? soruSayisi; // Kesişim ve Bonservis'in toplam soru sayısı
  final int? siradaki; // Bingo'da sıradaki oyuncunun destedeki sırası (1'den)
  final Object? soruVerisi;

  const OyunPaketi({
    required this.durum,
    this.yeni = false,
    this.oyunId,
    this.tarih,
    this.skor = 0,
    this.ilerleme = const [],
    this.sure,
    this.kalan,
    this.sureDoldu = false,
    this.soruSayisi,
    this.siradaki,
    this.soruVerisi,
  });

  bool get bitti => durum == OyunPaketiDurumu.bitti;

  factory OyunPaketi.fromJson(Map<String, dynamic> json) {
    return OyunPaketi(
      durum: switch (json['durum']) {
        'basladi' => OyunPaketiDurumu.acik,
        'tamamlandi' => OyunPaketiDurumu.bitti,
        _ => OyunPaketiDurumu.yok,
      },
      yeni: json['yeni'] == true,
      oyunId: json['oyun_id'] as String?,
      tarih: json['tarih'] as String?,
      skor: (json['skor'] as num?)?.toInt() ?? 0,
      ilerleme: (json['ilerleme'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().toList(),
      sure: (json['sure'] as num?)?.toInt(),
      kalan: (json['kalan'] as num?)?.toInt(),
      sureDoldu: json['sure_doldu'] == true,
      soruSayisi: (json['soru_sayisi'] as num?)?.toInt(),
      siradaki: (json['siradaki'] as num?)?.toInt(),
      soruVerisi: json['soru_verisi'],
    );
  }
}
