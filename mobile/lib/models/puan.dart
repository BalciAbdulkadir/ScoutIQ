// Puan ve liderlik tablosu (038_puan_ve_liderlik.sql, CLAUDE.md madde 15).
// Skor (doğru/kutu/oyuncu sayısı) ayrı kalır; puan liderlik tablosuna giden sayıdır ve sunucuda, oyun bitince yazılır
// (039_puan_her_dogruya.sql). Her doğru ve her dolu kutu puan getirir. Süresiz oyun puansızdır, Top 10 hariç.
// Not: services/puanlama.dart "uygulamayı puanla" (Play değerlendirmesi) içindir, bu dosyayla ilgisi yoktur.

// Sunucudaki puan_detay jsonb'si. puan null ise oyun puansızdır (sebep 'suresiz').
class PuanDetayi {
  final int? puan;
  final String? sebep;
  final int? taban; // Çarpanlardan önceki puan
  final bool kusursuz; // 5/5, 9/9, 12/12, 10/10
  final int? kalanCan; // Top 10
  final num? zorlukCarpani;
  final num? sureCarpani;
  final int? sure; // saniye; Top 10'da null
  final int? kalanSaniye;
  final int hizBonusu;

  const PuanDetayi({
    this.puan,
    this.sebep,
    this.taban,
    this.kusursuz = false,
    this.kalanCan,
    this.zorlukCarpani,
    this.sureCarpani,
    this.sure,
    this.kalanSaniye,
    this.hizBonusu = 0,
  });

  factory PuanDetayi.fromJson(Map<String, dynamic> json) => PuanDetayi(
        puan: (json['puan'] as num?)?.toInt(),
        sebep: json['sebep'] as String?,
        taban: (json['taban'] as num?)?.toInt(),
        kusursuz: json['kusursuz'] == true,
        kalanCan: (json['kalan_can'] as num?)?.toInt(),
        zorlukCarpani: json['zorluk_carpani'] as num?,
        sureCarpani: json['sure_carpani'] as num?,
        sure: (json['sure'] as num?)?.toInt(),
        kalanSaniye: (json['kalan_saniye'] as num?)?.toInt(),
        hizBonusu: (json['hiz_bonusu'] as num?)?.toInt() ?? 0,
      );

  bool get puansiz => puan == null;
  bool get suresiz => sebep == 'suresiz';
}

class LiderlikSatiri {
  final int sira; // Eşit puanda aynı numara
  final String ad; // Takma ad ya da "Oyuncu 3FA9"
  final int puan;
  final int oyun; // Puanlı (bitirilen) oyun sayısı
  final bool ben;
  final String? kullaniciId; // Takma ad bildirmek için (041). Kullanıcının alttaki kendi satırında yok.
  final bool varsayilan; // Ad sistemin ürettiği "Oyuncu 3FA9": bildirilemez

  const LiderlikSatiri({
    required this.sira,
    required this.ad,
    required this.puan,
    required this.oyun,
    this.ben = false,
    this.kullaniciId,
    this.varsayilan = false,
  });

  factory LiderlikSatiri.fromJson(Map<String, dynamic> json, {bool? ben}) => LiderlikSatiri(
        sira: (json['sira'] as num).toInt(),
        ad: json['ad'] as String,
        puan: (json['puan'] as num).toInt(),
        oyun: (json['oyun'] as num?)?.toInt() ?? 0,
        ben: ben ?? json['ben'] == true,
        kullaniciId: json['kullanici_id'] as String?,
        varsayilan: json['varsayilan'] == true,
      );

  // Başkasının seçtiği takma ad bildirilebilir; kendi adı ve sistemin ürettiği ad bildirilemez
  bool get bildirilebilir => !ben && !varsayilan && kullaniciId != null;
}

class LiderlikSonucu {
  final List<LiderlikSatiri> liste; // En fazla 50 kişi, sırayla
  final LiderlikSatiri? ben; // Kullanıcının kendi satırı; bu dönemde puanı yoksa null
  final int katilimci;

  const LiderlikSonucu({required this.liste, this.ben, this.katilimci = 0});

  factory LiderlikSonucu.fromJson(Map<String, dynamic> json) => LiderlikSonucu(
        liste: [
          for (final satir in (json['liste'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>())
            LiderlikSatiri.fromJson(satir),
        ],
        ben: json['ben'] is Map<String, dynamic> ? LiderlikSatiri.fromJson(json['ben'], ben: true) : null,
        katilimci: (json['katilimci'] as num?)?.toInt() ?? 0,
      );

  // Kullanıcı listede görünüyor mu (görünmüyorsa kendi satırı altta sabit durur)
  bool get benListede => liste.any((s) => s.ben);
}

enum LiderlikDonemi {
  gun('gun', 'Bugün'),
  hafta('hafta', 'Bu Hafta'),
  tum('tum', 'Tüm Zamanlar');

  final String kod;
  final String ad;

  const LiderlikDonemi(this.kod, this.ad);
}

// Liderlik tablosundaki oyun filtresi: null bütün oyunlar
const liderlikOyunlari = <({String? kod, String ad})>[
  (kod: null, ad: 'Hepsi'),
  (kod: 'kesisim', ad: 'Kesişim'),
  (kod: 'bonservis', ad: 'Bonservis'),
  (kod: 'izgara', ad: 'Izgara'),
  (kod: 'bingo', ad: 'Bingo'),
  (kod: 'top10', ad: 'Top 10'),
];

// Kullanıcının takma adı. varsayilan: henüz seçmedi, tabloda "Oyuncu 3FA9" görünüyor.
class Profil {
  final String takmaAd;
  final bool varsayilan;
  final DateTime? degistirilebilirTarih; // Bu tarihten önce takma ad değiştirilemez
  final bool sifirlandi; // Takma ad bildirildiği için sıfırlandı (041); yeni ad seçilene kadar true

  const Profil({required this.takmaAd, required this.varsayilan, this.degistirilebilirTarih, this.sifirlandi = false});

  factory Profil.fromJson(Map<String, dynamic> json) => Profil(
        takmaAd: json['takma_ad'] as String,
        varsayilan: json['varsayilan'] == true,
        degistirilebilirTarih: json['degistirilebilir_tarih'] == null
            ? null
            : DateTime.tryParse(json['degistirilebilir_tarih'] as String)?.toLocal(),
        sifirlandi: json['sifirlandi'] == true,
      );

  bool degistirilebilir(DateTime simdi) => degistirilebilirTarih == null || !simdi.isBefore(degistirilebilirTarih!);
}

// Takma ad kaydedilemedi: mesaj kullanıcıya gösterilir
class TakmaAdHatasi implements Exception {
  final String mesaj;
  const TakmaAdHatasi(this.mesaj);

  @override
  String toString() => mesaj;
}

// Sunucunun hata ipucundan (hint) Türkçe mesaj
String takmaAdHataMesaji(String? hint) => switch (hint) {
      'takma_ad_gecersiz' => '3-16 karakter; harf, rakam, _ ve . kullanılabilir',
      'takma_ad_yasakli' => 'Bu takma ad kullanılamaz',
      'takma_ad_alinmis' => 'Bu takma ad alınmış',
      'takma_ad_erken' => 'Takma adını 7 günde bir değiştirebilirsin',
      'takma_ad_kilitli' => 'Takma adını değiştiremezsin',
      'takma_ad_sifirlanmis' => 'Bu ad bildirildiği için kullanılamaz, başka bir ad seç',
      _ => 'Takma ad kaydedilemedi. İnternet bağlantını kontrol edip tekrar dene.',
    };

// Takma ad bildirilemedi (041): sunucunun hata ipucundan Türkçe mesaj
String bildirimHataMesaji(String? hint) => switch (hint) {
      'bildirim_icin_erken' => 'Ad bildirmek için en az 3 farklı gün oyun bitirmiş olman gerekir.',
      'varsayilan_ad' => 'Bu ad bildirilemez.',
      'kendini_bildiremez' => 'Kendi adını bildiremezsin.',
      _ => 'Bildirim gönderilemedi. Tekrar dene.',
    };

// Seçim ekranında gösterilen çarpanlar ve en yüksek puan. Puanı uygulama yazmaz; bu değerler sunucudaki
// puan_hesapla (039) ile aynı olmalıdır, biri değişirse öbürü de değişir.
const enFazlaTaban = {'kesisim': 100, 'bonservis': 60, 'izgara': 100, 'bingo': 100, 'top10': 130};
const zorlukCarpanlari = {'kolay': 1.0, 'orta': 1.5, 'zor': 2.0};
const tekModCarpani = 1.5; // Bingo ve Top 10
const sureCarpanlari = {40: 1.5, 60: 1.25, 90: 1.0};
const hizBonusuOrani = 0.2;

// Seçilen zorluk ve süreyle alınabilecek en yüksek puan (kusursuz ve en hızlı bitiş): taban × zorluk × süre × 1.2,
// aşağı yuvarlanır. zorluk null: tek modlu oyun. Süresizse null (puansız).
int? enFazlaPuan({required String oyun, String? zorluk, int? sure}) {
  final taban = enFazlaTaban[oyun];
  if (sure == null || taban == null) return null;
  final z = zorluk == null ? tekModCarpani : (zorlukCarpanlari[zorluk] ?? 1.0);
  final s = sureCarpanlari[sure] ?? 1.0;
  return (taban * z * s * (1 + hizBonusuOrani) + 1e-9).floor();
}

// "1240" -> "1.240"
String binlik(int sayi) {
  final metin = sayi.abs().toString();
  final parcalar = <String>[];
  for (var i = metin.length; i > 0; i -= 3) {
    parcalar.insert(0, metin.substring(i - 3 < 0 ? 0 : i - 3, i));
  }
  return '${sayi < 0 ? '-' : ''}${parcalar.join('.')}';
}

// Çarpanı kısa yazar: 1.0 -> "1", 1.25 -> "1.25"
String carpanMetni(num carpan) => carpan == carpan.roundToDouble() ? carpan.toInt().toString() : carpan.toString();
