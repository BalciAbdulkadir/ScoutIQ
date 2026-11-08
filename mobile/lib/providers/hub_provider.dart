import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/izgara.dart';
import '../models/oyun_modu.dart';

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

bool izgaraTipiMi(String oyunTipi) => oyunTipi.startsWith('izgara_');

// Zorluklu bir oyunun bugün açılmış zorluğu: altTipler'deki sırası (0 kolay, 1 orta, 2 zor) ve bitip bitmediği.
// Kullanıcı her oyunda günde tek zorluk oynar: varsa hub'da oyuna dokununca zorluk sorulmadan bu oyun açılır.
typedef BugunkuMod = ({int zorluk, bool bitti});

// Parametre oyunun tipidir: kesisim, bonservis, izgara ya da bingo. Zorluk modu olmayan oyunda (Bingo) zorluk 0'dır.
final bugunkuModProvider = FutureProvider.autoDispose.family<BugunkuMod?, String>((ref, oyun) async {
  final supabase = Supabase.instance.client;
  final userId = supabase.auth.currentUser?.id;
  final altTipler = oyunModlari.firstWhere((m) => m.tip == oyun).oyunTipleri;
  if (userId == null || altTipler.isEmpty) return null;

  final kayitlar = await supabase
      .from('kullanici_oyun_gecmisi')
      .select('oyun_tipi, durum')
      .eq('kullanici_id', userId)
      .eq('tarih', bugununTarihi())
      .inFilter('oyun_tipi', altTipler);

  final durumlar = {for (final kayit in kayitlar) kayit['oyun_tipi'] as String: kayit['durum'] as String?};
  // Kural gelmeden önce birden fazla zorluk oynanmış olabilir: yarım kalan önce, yoksa kolaydan zora ilki
  for (var i = 0; i < altTipler.length; i++) {
    if (durumlar[altTipler[i]] == 'basladi') return (zorluk: i, bitti: false);
  }
  for (var i = 0; i < altTipler.length; i++) {
    if (durumlar.containsKey(altTipler[i])) return (zorluk: i, bitti: true);
  }
  return null;
});

// Kullanıcının bugünkü Izgara tahtası (yarım ya da bitmiş)
typedef BugunkuIzgara = ({IzgaraZorlugu zorluk, bool bitti});

final bugunkuIzgaraProvider = FutureProvider.autoDispose<BugunkuIzgara?>((ref) async {
  final mod = await ref.watch(bugunkuModProvider('izgara').future);
  return mod == null ? null : (zorluk: IzgaraZorlugu.values[mod.zorluk], bitti: mod.bitti);
});
