import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/izgara.dart';

// Oyunlar Türkiye saatiyle 00.00'da yenilendiği için cihazın saat dilimine güvenmiyoruz.
// Türkiye'de yaz saati uygulaması yok, saat her zaman UTC+3.
DateTime turkiyeSaati() => DateTime.now().toUtc().add(const Duration(hours: 3));

String bugununTarihi() => DateFormat('yyyy-MM-dd').format(turkiyeSaati());

const _aylar = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];
const _gunler = ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'];

// "25 Ekim, Cumartesi"
String tarihMetni(DateTime tarih) => '${tarih.day} ${_aylar[tarih.month - 1]}, ${_gunler[tarih.weekday - 1]}';

Duration yenilenmeyeKalanSure() {
  final simdi = turkiyeSaati();
  final geceYarisi = DateTime.utc(simdi.year, simdi.month, simdi.day + 1);
  return geceYarisi.difference(simdi);
}

class KullaniciBilgisi {
  final String ad; // Tam ad
  final String? eposta;
  final String? fotoUrl;

  const KullaniciBilgisi({required this.ad, this.eposta, this.fotoUrl});

  String get ilkAd => ad.split(' ').first;
}

// Giriş yapmış kullanıcının Google hesabından gelen bilgileri
final kullaniciProvider = Provider<KullaniciBilgisi?>((ref) {
  final kullanici = Supabase.instance.client.auth.currentUser;
  if (kullanici == null) return null;

  final bilgiler = kullanici.userMetadata ?? const {};
  final ad = (bilgiler['full_name'] ?? bilgiler['name'] ?? kullanici.email?.split('@').first ?? 'Futbolsever') as String;
  return KullaniciBilgisi(
    ad: ad,
    eposta: kullanici.email,
    fotoUrl: (bilgiler['avatar_url'] ?? bilgiler['picture']) as String?,
  );
});

// Kullanıcının bugün oynadığı oyunlar: oyun_tipi -> skor
final bugunOynananlarProvider = FutureProvider.autoDispose<Map<String, int>>((ref) async {
  final supabase = Supabase.instance.client;
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return {};

  final kayitlar = await supabase
      .from('kullanici_oyun_gecmisi')
      .select('oyun_tipi, skor, durum')
      .eq('kullanici_id', userId)
      .eq('tarih', bugununTarihi());

  return {
    for (final kayit in kayitlar)
      // Yarıda bırakılan oyun kaldığı yerden devam eder, bitmiş sayılmaz
      if (kayit['durum'] != 'basladi') kayit['oyun_tipi'] as String: (kayit['skor'] as num?)?.toInt() ?? 0,
  };
});

// Bugün başlanıp bitmemiş Kesişim ve Bonservis oyunları (oyun_tipi). Hub'da "Devam et" yazar,
// dokununca süre sorulmadan oyun kaldığı yerden açılır. Izgara'nınki bugunkuIzgaraProvider'dadır.
final yarimOyunlarProvider = FutureProvider.autoDispose<Set<String>>((ref) async {
  final supabase = Supabase.instance.client;
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return {};

  final kayitlar = await supabase
      .from('kullanici_oyun_gecmisi')
      .select('oyun_tipi')
      .eq('kullanici_id', userId)
      .eq('tarih', bugununTarihi())
      .eq('durum', 'basladi')
      .inFilter('oyun_tipi', ['kesisim', 'bonservis']);

  return {for (final kayit in kayitlar) kayit['oyun_tipi'] as String};
});

bool izgaraTipiMi(String oyunTipi) => oyunTipi.startsWith('izgara_');

// Kullanıcının bugünkü Izgara tahtası (yarım ya da bitmiş). Kullanıcı günde tek bir Izgara oynar:
// varsa hub'da Izgara'ya dokununca zorluk ve süre sorulmadan bu tahta açılır.
typedef BugunkuIzgara = ({IzgaraZorlugu zorluk, bool bitti});

final bugunkuIzgaraProvider = FutureProvider.autoDispose<BugunkuIzgara?>((ref) async {
  final supabase = Supabase.instance.client;
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return null;

  final kayitlar = await supabase
      .from('kullanici_oyun_gecmisi')
      .select('oyun_tipi, durum')
      .eq('kullanici_id', userId)
      .eq('tarih', bugununTarihi())
      .inFilter('oyun_tipi', [for (final z in IzgaraZorlugu.values) z.oyunTipi]);

  final durumlar = {for (final kayit in kayitlar) kayit['oyun_tipi'] as String: kayit['durum'] as String?};
  // Kural gelmeden önce birden fazla zorluk oynanmış olabilir: yarım kalan önce, yoksa kolaydan zora ilki
  for (final zorluk in IzgaraZorlugu.values) {
    if (durumlar[zorluk.oyunTipi] == 'basladi') return (zorluk: zorluk, bitti: false);
  }
  for (final zorluk in IzgaraZorlugu.values) {
    if (durumlar.containsKey(zorluk.oyunTipi)) return (zorluk: zorluk, bitti: true);
  }
  return null;
});
