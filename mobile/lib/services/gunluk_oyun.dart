import '../models/izgara.dart';
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

// Oyun oynanabilir: yeni başladı ya da yarım kalmıştı ve kaldığı yerden devam ediyor
class Oynanabilir extends OyunAcilisi {
  final String oyunId;
  final List<dynamic> sorular;
  final String tarih;
  final int skor; // Yarım kalan oyunda o ana kadarki skor
  final List<Map<String, dynamic>> ilerleme; // Cevaplanan sorular, sırayla: {'dogru': bool, 'cevap': String?}
  final int? kalanSaniye; // Süreli oyunda sunucuya göre kalan süre (0: dolmuş); süresizse null

  Oynanabilir(this.oyunId, this.sorular, this.tarih, {this.skor = 0, this.ilerleme = const [], this.kalanSaniye});
}

// Bugün bitirilmiş
class ZatenOynandi extends OyunAcilisi {
  final int skor;
  ZatenOynandi(this.skor);
}

class OyunYok extends OyunAcilisi {}

class OturumYok extends OyunAcilisi {}

// Kullanıcı bu oyunun bugün başka bir zorluğunu açmış: her oyunda günde tek zorluk oynanır
class BaskaZorlukOynandi extends OyunAcilisi {}

// Oyun günü telefonun saatinden değil sunucudan alınır, veritabanı kuralları da bu tarihe göre çalışır.
// Sunucuya ulaşılamazsa aynı hesabı yapan yerel fonksiyona düşüyoruz.
Future<String> _oyunTarihi(OyunDeposu depo) async {
  try {
    return await depo.oyunTarihi();
  } catch (_) {
    return bugununTarihi();
  }
}

int _skor(Map<String, dynamic> kayit) => (kayit['skor'] as num?)?.toInt() ?? 0;

List<Map<String, dynamic>> _ilerleme(Map<String, dynamic> kayit) =>
    (kayit['ilerleme'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().toList();

// Günün oyununu açar. Kayıt yoksa 'basladi' olarak atar ve seçilen süreyi (sure, saniye) sunucuda başlatır.
// Oyundan çıkınca oyun bitmez: yarım kalan kayıt varsa oyun kaldığı yerden, sunucudaki kalan süreyle açılır.
// Bağlantı hatalarında fırlatır.
Future<OyunAcilisi> gunlukOyunuAc(OyunDeposu depo, String oyunTipi, {int? sure}) async {
  final userId = depo.kullaniciId;
  if (userId == null) return OturumYok();

  final tarih = await _oyunTarihi(depo);

  // 1. Kullanıcı bugün bu oyunu bitirmiş mi?
  var kayit = await depo.oyunKaydi(userId, oyunTipi, tarih);
  if (kayit != null && kayit['durum'] != 'basladi') return ZatenOynandi(_skor(kayit));

  // 2. Bugünün oyununu çek
  final oyun = await depo.gununOyunu(oyunTipi, tarih);
  final sorular = oyun?['soru_verisi'] as List<dynamic>?;
  if (oyun == null || sorular == null || sorular.isEmpty) return OyunYok();

  // 3. Kayıt yoksa aç
  var yeni = false;
  if (kayit == null) {
    try {
      await depo.kayitAc(kullaniciId: userId, oyunId: oyun['id'], oyunTipi: oyunTipi, tarih: tarih);
      kayit = {'skor': 0, 'durum': 'basladi'};
      yeni = true;
    } on KayitZatenVar {
      // Oyun aynı anda başka bir cihazda başlatılmış: o kayıtla devam ediliyor
      kayit = await depo.oyunKaydi(userId, oyunTipi, tarih);
      if (kayit == null) rethrow;
      if (kayit['durum'] != 'basladi') return ZatenOynandi(_skor(kayit));
    } on BaskaModOynandi {
      return BaskaZorlukOynandi();
    }
  }

  // 4. Süre: yeni oyunda seçilen süre başlatılır, yarım kalan oyunda sunucudaki kalan süre okunur
  OyunSuresiDurumu? sureDurumu;
  try {
    sureDurumu = await depo.oyunSureyiBaslat(oyunTipi, tarih, sure: yeni ? sure : null);
  } catch (_) {
    // Sunucuya sorulamazsa yeni oyun seçilen süreyle cihazda sayılır, yarım kalan oyun süresiz açılır
    if (yeni && sure != null) sureDurumu = OyunSuresiDurumu(toplam: sure, kalan: sure);
  }

  return Oynanabilir(
    oyun['id'],
    sorular,
    tarih,
    skor: _skor(kayit),
    ilerleme: _ilerleme(kayit),
    kalanSaniye: sureDurumu?.kalan,
  );
}
