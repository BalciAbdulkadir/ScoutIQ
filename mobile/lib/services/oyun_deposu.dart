import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/izgara.dart';
import '../models/oyuncu_oneri.dart';

// Aynı gün aynı oyun için kayıt zaten varsa (örneğin başka bir cihazda başlanmışsa) fırlatılır
class KayitZatenVar implements Exception {}

// Oyunların veritabanı işlemleri. Oyun mantığı bu arayüz üzerinden çalışır,
// böylece testlerde Supabase yerine sahte bir depo verilebilir.
abstract class OyunDeposu {
  String? get kullaniciId;

  // Türkiye saatine göre bugünün tarihi (yyyy-MM-dd), sunucudan
  Future<String> oyunTarihi();

  // Kullanıcının o günkü kaydı: {'skor': int, 'durum': 'basladi' | 'tamamlandi'} ya da null
  Future<Map<String, dynamic>?> oyunKaydi(String kullaniciId, String oyunTipi, String tarih);

  // Yarıda bırakılmış ('basladi') kaydı kapatır
  Future<void> yarimKaydiKapat(String kullaniciId, String oyunTipi, String tarih);

  // Günün oyunu: {'id': String, 'soru_verisi': List} ya da null
  Future<Map<String, dynamic>?> gununOyunu(String oyunTipi, String tarih);

  // Oyun başlarken 'basladi' kaydını atar. Kayıt zaten varsa KayitZatenVar fırlatır.
  Future<void> kayitAc({required String kullaniciId, required String oyunId, required String oyunTipi, required String tarih});

  Future<List<OyuncuOneri>> oyuncuAra(String metin);

  Future<bool> kesisimCevapKontrol({required String oyunId, required int soruIndex, required String oyuncuId});

  // Bitmiş bir Kesişim oyununun her sorusu için örnek bir doğru cevap: soru index'i -> oyuncu adı.
  // Sunucu sadece oyunu bitirmiş kullanıcıya cevap döndürür.
  Future<Map<int, String>> kesisimOrnekCevaplar(String oyunId);

  // 'basladi' durumundaki kaydın skorunu yazar, bittiyse kilitler.
  // Güncellenecek kayıt yoksa (başka yerden kapatılmışsa) false döner.
  Future<bool> skorYaz({required String kullaniciId, required String oyunTipi, required String tarih, required int skor, required bool bitti});

  // Izgara: tahminler, skor ve haklar sunucuda tutulur (011_izgara.sql)

  // Kullanıcının bu tahtadaki önceki tahminleri, sırayla. Uygulama yeniden açılınca tahta bunlarla kurulur.
  Future<List<IzgaraTahmini>> izgaraTahminleri(String oyunId);

  // Oyuncuyu uygun boş hücreye yerleştirmeyi dener
  Future<IzgaraTahminSonucu> izgaraTahmin({required String oyunId, required String oyuncuId});

  // Oyunu o anki skorla bitirir, skoru döndürür
  Future<int> izgaraPesEt(String oyunId);

  // Bitmiş tahtanın her hücresi için örnek bir doğru cevap: hücre -> oyuncu adı
  Future<Map<int, String>> izgaraOrnekCevaplar(String oyunId);
}

class SupabaseOyunDeposu implements OyunDeposu {
  final SupabaseClient _supabase;

  SupabaseOyunDeposu(this._supabase);

  @override
  String? get kullaniciId => _supabase.auth.currentUser?.id;

  @override
  Future<String> oyunTarihi() async {
    final tarih = await _supabase.rpc('bugunun_tarihi');
    if (tarih is String && tarih.isNotEmpty) return tarih;
    throw StateError('bugunun_tarihi boş döndü');
  }

  @override
  Future<Map<String, dynamic>?> oyunKaydi(String kullaniciId, String oyunTipi, String tarih) {
    return _supabase
        .from('kullanici_oyun_gecmisi')
        .select('skor, durum')
        .eq('kullanici_id', kullaniciId)
        .eq('oyun_tipi', oyunTipi)
        .eq('tarih', tarih)
        .maybeSingle();
  }

  @override
  Future<void> yarimKaydiKapat(String kullaniciId, String oyunTipi, String tarih) async {
    await _supabase
        .from('kullanici_oyun_gecmisi')
        .update({'durum': 'tamamlandi'})
        .eq('kullanici_id', kullaniciId)
        .eq('oyun_tipi', oyunTipi)
        .eq('tarih', tarih)
        .eq('durum', 'basladi');
  }

  @override
  Future<Map<String, dynamic>?> gununOyunu(String oyunTipi, String tarih) {
    return _supabase
        .from('gunluk_oyunlar')
        .select()
        .eq('oyun_tipi', oyunTipi)
        .eq('tarih', tarih)
        .limit(1)
        .maybeSingle();
  }

  @override
  Future<void> kayitAc({required String kullaniciId, required String oyunId, required String oyunTipi, required String tarih}) async {
    try {
      await _supabase.from('kullanici_oyun_gecmisi').insert({
        'kullanici_id': kullaniciId,
        'oyun_id': oyunId,
        'oyun_tipi': oyunTipi,
        'tarih': tarih,
        'skor': 0,
        'durum': 'basladi',
      });
    } on PostgrestException catch (e) {
      // 23505: aynı gün için kayıt zaten var
      if (e.code == '23505') throw KayitZatenVar();
      rethrow;
    }
  }

  @override
  Future<List<OyuncuOneri>> oyuncuAra(String metin) async {
    final sonuc = await _supabase.rpc('oyuncu_ara', params: {'p_arama': metin});
    return (sonuc as List<dynamic>)
        .map((satir) => OyuncuOneri.fromJson(satir as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<bool> kesisimCevapKontrol({required String oyunId, required int soruIndex, required String oyuncuId}) async {
    final dogruMu = await _supabase.rpc('kesisim_cevap_kontrol', params: {
      'p_oyun_id': oyunId,
      'p_soru_index': soruIndex,
      'p_oyuncu_id': oyuncuId,
    });
    return dogruMu == true;
  }

  @override
  Future<Map<int, String>> kesisimOrnekCevaplar(String oyunId) async {
    final satirlar = await _supabase.rpc('kesisim_ornek_cevaplar', params: {'p_oyun_id': oyunId}) as List<dynamic>;
    return {
      for (final satir in satirlar.cast<Map<String, dynamic>>())
        if (satir['oyuncu_isim'] != null) (satir['soru_index'] as num).toInt(): satir['oyuncu_isim'] as String,
    };
  }

  @override
  Future<bool> skorYaz({required String kullaniciId, required String oyunTipi, required String tarih, required int skor, required bool bitti}) async {
    final guncellenen = await _supabase
        .from('kullanici_oyun_gecmisi')
        .update({'skor': skor, 'durum': bitti ? 'tamamlandi' : 'basladi'})
        .eq('kullanici_id', kullaniciId)
        .eq('oyun_tipi', oyunTipi)
        .eq('tarih', tarih)
        .eq('durum', 'basladi')
        .select('skor');
    return guncellenen.isNotEmpty;
  }

  @override
  Future<List<IzgaraTahmini>> izgaraTahminleri(String oyunId) async {
    final satirlar = await _supabase
        .from('izgara_tahminleri')
        .select('sira, oyuncu_isim, hucre, oyuncular(foto_url)')
        .eq('kullanici_id', kullaniciId!)
        .eq('oyun_id', oyunId)
        .order('sira');
    return satirlar.map(IzgaraTahmini.fromJson).toList();
  }

  @override
  Future<IzgaraTahminSonucu> izgaraTahmin({required String oyunId, required String oyuncuId}) async {
    final sonuc = await _supabase.rpc('izgara_tahmin', params: {'p_oyun_id': oyunId, 'p_oyuncu_id': oyuncuId});
    return IzgaraTahminSonucu.fromJson(sonuc as Map<String, dynamic>);
  }

  @override
  Future<int> izgaraPesEt(String oyunId) async {
    final skor = await _supabase.rpc('izgara_pes_et', params: {'p_oyun_id': oyunId});
    return (skor as num).toInt();
  }

  @override
  Future<Map<int, String>> izgaraOrnekCevaplar(String oyunId) async {
    final satirlar = await _supabase.rpc('izgara_ornek_cevaplar', params: {'p_oyun_id': oyunId}) as List<dynamic>;
    return {
      for (final satir in satirlar.cast<Map<String, dynamic>>())
        if (satir['oyuncu_isim'] != null) (satir['hucre'] as num).toInt(): satir['oyuncu_isim'] as String,
    };
  }
}

final oyunDeposuProvider = Provider<OyunDeposu>((ref) {
  return SupabaseOyunDeposu(Supabase.instance.client);
});
