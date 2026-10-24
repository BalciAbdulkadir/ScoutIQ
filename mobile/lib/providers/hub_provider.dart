import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Oyunlar Türkiye saatiyle 00.00'da yenilendiği için cihazın saat dilimine güvenmiyoruz.
// Türkiye'de yaz saati uygulaması yok, saat her zaman UTC+3.
DateTime turkiyeSaati() => DateTime.now().toUtc().add(const Duration(hours: 3));

String bugununTarihi() => DateFormat('yyyy-MM-dd').format(turkiyeSaati());

Duration yenilenmeyeKalanSure() {
  final simdi = turkiyeSaati();
  final geceYarisi = DateTime.utc(simdi.year, simdi.month, simdi.day + 1);
  return geceYarisi.difference(simdi);
}

// Kullanıcının bugün oynadığı oyunlar: oyun_tipi -> skor
final bugunOynananlarProvider = FutureProvider.autoDispose<Map<String, int>>((ref) async {
  final supabase = Supabase.instance.client;
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return {};

  final kayitlar = await supabase
      .from('kullanici_oyun_gecmisi')
      .select('oyun_tipi, skor')
      .eq('kullanici_id', userId)
      .eq('tarih', bugununTarihi());

  return {
    for (final kayit in kayitlar)
      kayit['oyun_tipi'] as String: (kayit['skor'] as num?)?.toInt() ?? 0,
  };
});
