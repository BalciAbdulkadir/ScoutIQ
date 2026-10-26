import '../providers/hub_provider.dart';
import 'oyun_deposu.dart';

const oturumYokMesaji = 'Oturumun kapanmış görünüyor. Lütfen tekrar giriş yap.';
const yuklemeHataMesaji = 'Oyun yüklenemedi. İnternet bağlantını kontrol edip tekrar dene.';
const gonderimHataMesaji = 'Cevap gönderilemedi. İnternet bağlantını kontrol edip tekrar dene.';

// Bir günlük oyunu açmaya çalışmanın sonucu. Tüm oyun modları aynı "günde tek atış" kurallarını kullanır.
sealed class OyunAcilisi {}

// Oyun oynanabilir: 'basladi' kaydı açıldı
class Oynanabilir extends OyunAcilisi {
  final String oyunId;
  final List<dynamic> sorular;
  final String tarih;
  Oynanabilir(this.oyunId, this.sorular, this.tarih);
}

// Bugün bitirilmiş
class ZatenOynandi extends OyunAcilisi {
  final int skor;
  ZatenOynandi(this.skor);
}

// Bugün başlanıp yarıda bırakılmış: tamamlanmış sayılır ve kaydı kapatılır
class YaridaBirakildi extends OyunAcilisi {
  final int skor;
  YaridaBirakildi(this.skor);
}

class OyunYok extends OyunAcilisi {}

class OturumYok extends OyunAcilisi {}

// Oyun günü telefonun saatinden değil sunucudan alınır, veritabanı kuralları da bu tarihe göre çalışır.
// Sunucuya ulaşılamazsa aynı hesabı yapan yerel fonksiyona düşüyoruz.
Future<String> _oyunTarihi(OyunDeposu depo) async {
  try {
    return await depo.oyunTarihi();
  } catch (_) {
    return bugununTarihi();
  }
}

// Daha önce atılmış kayda göre oyunu kilitler
Future<OyunAcilisi> _kayittanKilitle(OyunDeposu depo, Map<String, dynamic> kayit, String userId, String oyunTipi, String tarih) async {
  final skor = (kayit['skor'] as num?)?.toInt() ?? 0;

  if (kayit['durum'] == 'basladi') {
    // Kaydı kapatıyoruz ki yarım kalan oyunun skoru sonradan değiştirilemesin
    try {
      await depo.yarimKaydiKapat(userId, oyunTipi, tarih);
    } catch (_) {}
    return YaridaBirakildi(skor);
  }

  return ZatenOynandi(skor);
}

// Günün oyununu açar. Oyun oynanabilirse kaydı 'basladi' olarak atar:
// oyun yarıda bırakılırsa bu kayıt tekrar oynamayı engeller. Bağlantı hatalarında fırlatır.
Future<OyunAcilisi> gunlukOyunuAc(OyunDeposu depo, String oyunTipi) async {
  final userId = depo.kullaniciId;
  if (userId == null) return OturumYok();

  final tarih = await _oyunTarihi(depo);

  // 1. Kullanıcı bugün bu oyuna başlamış ya da bitirmiş mi?
  final kayit = await depo.oyunKaydi(userId, oyunTipi, tarih);
  if (kayit != null) return _kayittanKilitle(depo, kayit, userId, oyunTipi, tarih);

  // 2. Bugünün oyununu çek
  final oyun = await depo.gununOyunu(oyunTipi, tarih);
  final sorular = oyun?['soru_verisi'] as List<dynamic>?;
  if (oyun == null || sorular == null || sorular.isEmpty) return OyunYok();

  // 3. Kaydı aç
  try {
    await depo.kayitAc(kullaniciId: userId, oyunId: oyun['id'], oyunTipi: oyunTipi, tarih: tarih);
  } on KayitZatenVar {
    // Oyun aynı anda başka bir cihazda başlatılmış
    final mevcut = await depo.oyunKaydi(userId, oyunTipi, tarih);
    if (mevcut != null) return _kayittanKilitle(depo, mevcut, userId, oyunTipi, tarih);
    rethrow;
  }

  return Oynanabilir(oyun['id'], sorular, tarih);
}
