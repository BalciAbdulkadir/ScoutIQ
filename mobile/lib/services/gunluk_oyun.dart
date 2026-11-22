import '../models/oyun_paketi.dart';
import '../providers/hub_provider.dart';
import 'oyun_deposu.dart';

const oturumYokMesaji = 'Oturumun kapanmış görünüyor. Lütfen tekrar giriş yap.';
const yuklemeHataMesaji = 'Oyun yüklenemedi. İnternet bağlantını kontrol edip tekrar dene.';
const gonderimHataMesaji = 'Cevap gönderilemedi. İnternet bağlantını kontrol edip tekrar dene.';
const baskaZorlukMesaji = 'Bu oyunu bugün başka bir zorlukta oynadın. Yeni oyunlar gece yarısı açılıyor.';

// Kesişim ya da Bonservis ekranını açan seçim: zorluğun günlük oyun tipi (ör. kesisim_orta) ve seçilen süre
// (saniye; null: süresiz). Süre sadece yeni başlanan oyunda kullanılır, yarım kalan oyunun süresi sunucudan okunur.
typedef GunlukOyunSecimi = ({String oyunTipi, int? sure});

// Bir günlük oyunu (Kesişim ya da Bonservis, herhangi bir zorluğu) açmaya çalışmanın sonucu.
sealed class OyunAcilisi {}

// Oyun oynanabilir: yeni başladı ya da yarım kalmıştı ve kaldığı yerden devam ediyor.
// Sorular tek tek gelir: sorular cevaplanmış sorular + sıradaki sorudur, toplam sayı soruSayisi'dir (040_oyun_ac.sql).
// Oyun kapalıyken süre dolmuşsa (sureDoldu) sunucu kaydı kapatmıştır, sorular tamdır.
class Oynanabilir extends OyunAcilisi {
  final String oyunId;
  final List<dynamic> sorular;
  final int soruSayisi;
  final String tarih;
  final int skor; // Yarım kalan oyunda o ana kadarki skor
  final List<Map<String, dynamic>> ilerleme; // Cevaplanan sorular, sırayla: {'dogru': bool, 'cevap': String?}
  final int? kalanSaniye; // Süreli oyunda sunucuya göre kalan süre (0: dolmuş); süresizse null
  final bool yeni; // Kayıt şimdi açıldı: oyun yeni başladı (yarım kalan oyun değil)
  final bool sureDoldu; // Oyun kapalıyken süre dolmuş, kayıt kapatıldı

  Oynanabilir(this.oyunId, this.sorular, this.tarih,
      {int? soruSayisi,
      this.skor = 0,
      this.ilerleme = const [],
      this.kalanSaniye,
      this.yeni = false,
      this.sureDoldu = false})
      : soruSayisi = soruSayisi ?? sorular.length;
}

// Bugün bitirilmiş
class ZatenOynandi extends OyunAcilisi {
  final int skor;
  final List<Map<String, dynamic>> ilerleme; // Cevaplanan sorular (paylaşım metnindeki kareler için)
  ZatenOynandi(this.skor, {this.ilerleme = const []});
}

class OyunYok extends OyunAcilisi {}

class OturumYok extends OyunAcilisi {}

// Kullanıcı bu oyunun bugün başka bir zorluğunu açmış: her oyunda günde tek zorluk oynanır
class BaskaZorlukOynandi extends OyunAcilisi {}

// Günün oyununu açar: kayıt, süre ve soru tek çağrıyla sunucuda açılır (040_oyun_ac.sql). Seçilen süre (saniye)
// sadece yeni açılan oyunda kullanılır. Oyundan çıkınca oyun bitmez: yarım kalan oyun kaldığı yerden, sunucudaki
// kalan süreyle açılır. Bağlantı hatalarında fırlatır.
Future<OyunAcilisi> gunlukOyunuAc(OyunDeposu depo, String oyunTipi, {int? sure}) async {
  if (depo.kullaniciId == null) return OturumYok();

  final OyunPaketi paket;
  try {
    paket = await depo.oyunAc(oyunTipi, sure: sure);
  } on BaskaModOynandi {
    return BaskaZorlukOynandi();
  }

  final sorular = paket.soruVerisi is List ? paket.soruVerisi as List<dynamic> : null;
  if (paket.durum == OyunPaketiDurumu.yok || paket.oyunId == null || sorular == null || sorular.isEmpty) return OyunYok();
  // Süre bu açılışta dolduysa oyun bitiş ekranıyla açılır (yarım kalan oyun gibi), diğer bitmiş oyunlar özetsiz
  if (paket.bitti && !paket.sureDoldu) return ZatenOynandi(paket.skor, ilerleme: paket.ilerleme);

  return Oynanabilir(
    paket.oyunId!,
    sorular,
    paket.tarih ?? bugununTarihi(),
    soruSayisi: paket.soruSayisi,
    skor: paket.skor,
    ilerleme: paket.ilerleme,
    kalanSaniye: paket.sureDoldu ? 0 : paket.kalan,
    yeni: paket.yeni,
    sureDoldu: paket.sureDoldu,
  );
}

// Bitmiş oyunun bütün soruları (bitiş özeti için): sunucu bitmiş oyunda soru verisinin tamamını döndürür.
// Gelmezse null; özet o ana kadar gelen sorularla gösterilir.
Future<List<dynamic>?> bitmisOyununSorulari(OyunDeposu depo, String oyunTipi) async {
  try {
    final paket = await depo.oyunAc(oyunTipi);
    return paket.bitti && paket.soruVerisi is List ? paket.soruVerisi as List<dynamic> : null;
  } catch (_) {
    return null;
  }
}
