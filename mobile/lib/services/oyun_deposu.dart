import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/bingo.dart';
import '../models/bonservis_sorusu.dart';
import '../models/kesisim.dart';
import '../models/izgara.dart';
import '../models/oyun_paketi.dart';
import '../models/oyuncu_oneri.dart';
import '../models/puan.dart';
import '../models/top10.dart';

// Kullanıcı bu oyunun bugün başka bir zorluğuna başlamış: her oyunda günde tek zorluk oynanır (019_zorluk_modlari.sql)
class BaskaModOynandi implements Exception {}

// Cevap gönderilen oyunun kaydı açık değil (başka bir cihazda bitirilmiş ya da kapatılmış)
class OyunAcikDegil implements Exception {}

// Oyunların veritabanı işlemleri. Oyun mantığı bu arayüz üzerinden çalışır,
// böylece testlerde Supabase yerine sahte bir depo verilebilir.
abstract class OyunDeposu {
  String? get kullaniciId;

  // Türkiye saatine göre bugünün tarihi (yyyy-MM-dd), sunucudan
  Future<String> oyunTarihi();

  // Günün oyununu açar (040_oyun_ac.sql). Soru, kayıt ve süre tek adımda sunucuda açılır: kayıt yoksa açılır ve
  // seçilen süre (saniye; null: süresiz) aynı anda başlar. Kayıt varsa süre yok sayılır, oyun kaldığı yerden döner.
  // Kullanıcı bu oyunun bugün başka bir modunu açtıysa BaskaModOynandi fırlatır.
  Future<OyunPaketi> oyunAc(String oyunTipi, {int? sure});

  // Bitmiş oyunun bütün soruları (042_bitmis_oyun_sorulari.sql): oyun id'siyle okunur, hiçbir şey açmaz ve süre
  // başlatmaz. Kullanıcının bu oyundaki kaydı bitmediyse null.
  Future<List<dynamic>?> bitmisOyunSorulari(String oyunId);

  Future<List<OyuncuOneri>> oyuncuAra(String metin);

  // Kesişim ve Bonservis: cevap sunucuda kontrol edilir, skor ve ilerleme sunucuda yazılır (034_skor_sunucuda.sql).
  // Kayıt açık değilse OyunAcikDegil fırlatır.

  // Seçilen oyuncuyu soru index'indeki sorunun cevabı olarak gönderir. Son soruda kayıt kapanır.
  Future<KesisimCevapSonucu> kesisimCevap({required String oyunId, required int soruIndex, required String oyuncuId});

  // Bonservis tahmini: sağdaki oyuncunun bedeli soldakinden daha fazla mı. Bedel tahminden sonra döner.
  Future<BonservisTahminSonucu> bonservisTahmin({required String oyunId, required int soruIndex, required bool dahaFazla});

  // Sağdaki oyuncuların bedelleri: soru index'i -> bedel. Cevaplanan sorularınkiler; oyun bittiyse hepsi.
  Future<Map<int, int>> bonservisBedelleri(String oyunId);

  // Kesişim ve Bonservis: süre dolunca oyunu o anki skorla kapatır, skora dokunmaz
  Future<void> oyunuBitir(String oyunId);

  // Bitmiş bir Kesişim oyununun her sorusu için örnek bir doğru cevap: soru index'i -> oyuncu adı.
  // Sunucu sadece oyunu bitirmiş kullanıcıya cevap döndürür.
  Future<Map<int, String>> kesisimOrnekCevaplar(String oyunId);

  // Izgara: tahminler ve skor sunucuda tutulur (011_izgara.sql)

  // Kullanıcının bu tahtadaki önceki tahminleri, sırayla. Uygulama yeniden açılınca tahta bunlarla kurulur.
  Future<List<IzgaraTahmini>> izgaraTahminleri(String oyunId);

  // Oyuncuyu uygun boş hücreye yerleştirmeyi dener
  Future<IzgaraTahminSonucu> izgaraTahmin({required String oyunId, required String oyuncuId});

  // Oyunu o anki skorla bitirir, skoru döndürür
  Future<int> izgaraPesEt(String oyunId);

  // Bitmiş tahtanın her hücresi için örnek bir doğru cevap: hücre -> oyuncu
  Future<Map<int, IzgaraOyuncusu>> izgaraOrnekCevaplar(String oyunId);

  // Kulüplerin logo adresleri: kulüp ID'si -> logo. Logosuz kulüpler dönmez.
  Future<Map<String, String>> kulupLogolari(List<String> kulupIdleri);

  // Bingo: hamleler ve skor sunucuda tutulur (020_bingo.sql)

  // Kullanıcının bu karttaki hamleleri, sırayla. Uygulama yeniden açılınca kart bunlarla kurulur.
  Future<List<BingoHamlesi>> bingoHamleleri(String oyunId);

  // Kullanıcının sira. hamlesi: sıradaki oyuncuyu hucre kutusuna koyar; hucre null ise pas geçer
  Future<BingoHamleSonucu> bingoHamle({required String oyunId, required int sira, int? hucre});

  // Oyunu o anki skorla bitirir, skoru döndürür
  Future<int> bingoPesEt(String oyunId);

  // Bitmiş kartta boş kalan her kutu için desteden ona uyan bir oyuncu: kutu -> oyuncu
  Future<Map<int, BingoOyuncusu>> bingoOrnekCevaplar(String oyunId);

  // Top 10: tahminler ve skor sunucuda tutulur (029_top10.sql)

  // Kullanıcının bu sorudaki tahminleri. Uygulama yeniden açılınca liste bunlarla kurulur.
  Future<List<Top10Tahmini>> top10Tahminleri(String oyunId);

  // Oyuncu listedeyse kendi sırasına yerleşir
  Future<Top10TahminSonucu> top10Tahmin({required String oyunId, required String oyuncuId});

  // Oyunu o anki skorla bitirir, skoru döndürür
  Future<int> top10PesEt(String oyunId);

  // Listedeki oyuncular: sıra -> oyuncu. Oyun bitmediyse sadece bulunanlar, bittiyse hepsi döner.
  Future<Map<int, Top10Oyuncusu>> top10Cevaplar(String oyunId);

  // Puan ve liderlik tablosu (038_puan_ve_liderlik.sql). Puan oyun bitince sunucuda yazılır, uygulama sadece okur.

  // Kullanıcının bitmiş oyununun puanı. tarih null ise sunucudaki bugün. Kayıt yoksa ya da puan henüz yazılmadıysa null.
  Future<PuanDetayi?> puanGetir(String oyunTipi, {String? tarih});

  // donem: bugün, bu hafta ya da tüm zamanlar; oyun: null (hepsi) ya da kesisim, bonservis, izgara, bingo, top10
  Future<LiderlikSonucu> liderlikTablosu(LiderlikDonemi donem, {String? oyun});

  // Kullanıcının takma adı (seçmediyse varsayılan "Oyuncu 3FA9")
  Future<Profil> profilGetir();

  // Takma adı kaydeder, kaydedilen adı döndürür. Sunucu reddederse TakmaAdHatasi fırlatır.
  Future<String> takmaAdKaydet(String ad);
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
  Future<OyunPaketi> oyunAc(String oyunTipi, {int? sure}) async {
    try {
      final sonuc = await _supabase.rpc('oyun_ac', params: {'p_oyun_tipi': oyunTipi, 'p_sure': sure});
      return OyunPaketi.fromJson(sonuc as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      if (e.hint == 'oyun_gunde_bir') throw BaskaModOynandi();
      rethrow;
    }
  }

  @override
  Future<List<dynamic>?> bitmisOyunSorulari(String oyunId) async {
    final sonuc = await _supabase.rpc('bitmis_oyun_sorulari', params: {'p_oyun_id': oyunId});
    return sonuc is List ? sonuc : null;
  }

  @override
  Future<List<OyuncuOneri>> oyuncuAra(String metin) async {
    final sonuc = await _supabase.rpc('oyuncu_ara', params: {'p_arama': metin});
    return (sonuc as List<dynamic>)
        .map((satir) => OyuncuOneri.fromJson(satir as Map<String, dynamic>))
        .toList();
  }

  // Sunucu fonksiyonunu çağırır; kayıt açık değilse OyunAcikDegil fırlatır
  Future<dynamic> _oyunRpc(String fonksiyon, Map<String, dynamic> parametreler) async {
    try {
      return await _supabase.rpc(fonksiyon, params: parametreler);
    } on PostgrestException catch (e) {
      if (e.message.contains('Oyun açık değil')) throw OyunAcikDegil();
      rethrow;
    }
  }

  @override
  Future<KesisimCevapSonucu> kesisimCevap({required String oyunId, required int soruIndex, required String oyuncuId}) async {
    final sonuc = await _oyunRpc('kesisim_cevap', {
      'p_oyun_id': oyunId,
      'p_soru_index': soruIndex,
      'p_oyuncu_id': oyuncuId,
    });
    return KesisimCevapSonucu.fromJson(sonuc as Map<String, dynamic>);
  }

  @override
  Future<BonservisTahminSonucu> bonservisTahmin({required String oyunId, required int soruIndex, required bool dahaFazla}) async {
    final sonuc = await _oyunRpc('bonservis_tahmin', {
      'p_oyun_id': oyunId,
      'p_soru_index': soruIndex,
      'p_daha_fazla': dahaFazla,
    });
    return BonservisTahminSonucu.fromJson(sonuc as Map<String, dynamic>);
  }

  @override
  Future<Map<int, int>> bonservisBedelleri(String oyunId) async {
    final satirlar = await _supabase.rpc('bonservis_bedelleri', params: {'p_oyun_id': oyunId}) as List<dynamic>;
    return {
      for (final satir in satirlar.cast<Map<String, dynamic>>())
        if (satir['rakip_bonservis'] != null)
          (satir['soru_index'] as num).toInt(): (satir['rakip_bonservis'] as num).toInt(),
    };
  }

  @override
  Future<void> oyunuBitir(String oyunId) async {
    await _supabase.rpc('oyunu_bitir', params: {'p_oyun_id': oyunId});
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
  Future<Map<int, IzgaraOyuncusu>> izgaraOrnekCevaplar(String oyunId) async {
    final satirlar = await _supabase.rpc('izgara_ornek_cevaplar', params: {'p_oyun_id': oyunId}) as List<dynamic>;
    return {
      for (final satir in satirlar.cast<Map<String, dynamic>>())
        if (satir['oyuncu_isim'] != null)
          (satir['hucre'] as num).toInt(): IzgaraOyuncusu(
            isim: satir['oyuncu_isim'] as String,
            // 012 çalıştırılmadan önce fonksiyon fotoğraf döndürmez
            fotoUrl: satir['foto_url'] as String?,
          ),
    };
  }

  @override
  Future<Map<String, String>> kulupLogolari(List<String> kulupIdleri) async {
    if (kulupIdleri.isEmpty) return {};
    final satirlar = await _supabase.from('kulupler').select('id, logo_url').inFilter('id', kulupIdleri);
    return {
      for (final satir in satirlar)
        if (satir['logo_url'] != null) satir['id'] as String: satir['logo_url'] as String,
    };
  }

  @override
  Future<List<BingoHamlesi>> bingoHamleleri(String oyunId) async {
    final satirlar = await _supabase
        .from('bingo_hamleleri')
        .select('sira, oyuncu, hucre, dogru')
        .eq('kullanici_id', kullaniciId!)
        .eq('oyun_id', oyunId)
        .order('sira');
    return satirlar.map(BingoHamlesi.fromJson).toList();
  }

  @override
  Future<BingoHamleSonucu> bingoHamle({required String oyunId, required int sira, int? hucre}) async {
    final sonuc = await _supabase.rpc('bingo_hamle', params: {'p_oyun_id': oyunId, 'p_sira': sira, 'p_hucre': hucre});
    return BingoHamleSonucu.fromJson(sonuc as Map<String, dynamic>);
  }

  @override
  Future<int> bingoPesEt(String oyunId) async {
    final skor = await _supabase.rpc('bingo_pes_et', params: {'p_oyun_id': oyunId});
    return (skor as num).toInt();
  }

  @override
  Future<Map<int, BingoOyuncusu>> bingoOrnekCevaplar(String oyunId) async {
    final satirlar = await _supabase.rpc('bingo_ornek_cevaplar', params: {'p_oyun_id': oyunId}) as List<dynamic>;
    return {
      for (final satir in satirlar.cast<Map<String, dynamic>>())
        if (satir['oyuncu_isim'] != null)
          (satir['hucre'] as num).toInt(): BingoOyuncusu(isim: satir['oyuncu_isim'] as String, fotoUrl: satir['foto_url'] as String?),
    };
  }

  @override
  Future<List<Top10Tahmini>> top10Tahminleri(String oyunId) async {
    final satirlar = await _supabase
        .from('top10_tahminleri')
        .select('oyuncu_isim, sira')
        .eq('kullanici_id', kullaniciId!)
        .eq('oyun_id', oyunId)
        .order('olusturma_zamani');
    return satirlar.map(Top10Tahmini.fromJson).toList();
  }

  @override
  Future<Top10TahminSonucu> top10Tahmin({required String oyunId, required String oyuncuId}) async {
    final sonuc = await _supabase.rpc('top10_tahmin', params: {'p_oyun_id': oyunId, 'p_oyuncu_id': oyuncuId});
    return Top10TahminSonucu.fromJson(sonuc as Map<String, dynamic>);
  }

  @override
  Future<int> top10PesEt(String oyunId) async {
    final skor = await _supabase.rpc('top10_pes_et', params: {'p_oyun_id': oyunId});
    return (skor as num).toInt();
  }

  @override
  Future<Map<int, Top10Oyuncusu>> top10Cevaplar(String oyunId) async {
    final satirlar = await _supabase.rpc('top10_cevaplar', params: {'p_oyun_id': oyunId}) as List<dynamic>;
    return {
      for (final satir in satirlar.cast<Map<String, dynamic>>())
        (satir['sira'] as num).toInt(): Top10Oyuncusu(
          isim: satir['oyuncu_isim'] as String,
          fotoUrl: satir['foto_url'] as String?,
          deger: satir['deger'] as String?,
        ),
    };
  }

  Future<Map<String, dynamic>?> _puanKaydi(String oyunTipi, String tarih) => _supabase
      .from('kullanici_oyun_gecmisi')
      .select('durum, puan, puan_detay')
      .eq('kullanici_id', kullaniciId!)
      .eq('oyun_tipi', oyunTipi)
      .eq('tarih', tarih)
      .maybeSingle();

  @override
  Future<PuanDetayi?> puanGetir(String oyunTipi, {String? tarih}) async {
    if (kullaniciId == null) return null;
    final gun = tarih ?? await oyunTarihi();
    var kayit = await _puanKaydi(oyunTipi, gun);
    // Puan oyun kapanırken yazılır; kapanış daha yeni gönderildiyse bir kez daha bakılır
    if (kayit != null && kayit['puan_detay'] == null) {
      await Future<void>.delayed(const Duration(seconds: 1));
      kayit = await _puanKaydi(oyunTipi, gun);
    }
    final detay = kayit?['puan_detay'];
    return detay is Map<String, dynamic> ? PuanDetayi.fromJson(detay) : null;
  }

  @override
  Future<LiderlikSonucu> liderlikTablosu(LiderlikDonemi donem, {String? oyun}) async {
    final sonuc = await _supabase.rpc('liderlik_tablosu', params: {'p_donem': donem.kod, 'p_oyun': oyun, 'p_adet': 50});
    return LiderlikSonucu.fromJson(sonuc as Map<String, dynamic>);
  }

  @override
  Future<Profil> profilGetir() async {
    final sonuc = await _supabase.rpc('profil_getir');
    return Profil.fromJson(sonuc as Map<String, dynamic>);
  }

  @override
  Future<String> takmaAdKaydet(String ad) async {
    try {
      final sonuc = await _supabase.rpc('takma_ad_kaydet', params: {'p_ad': ad});
      return sonuc as String;
    } on PostgrestException catch (e) {
      throw TakmaAdHatasi(takmaAdHataMesaji(e.hint));
    }
  }
}


final oyunDeposuProvider = Provider<OyunDeposu>((ref) {
  return SupabaseOyunDeposu(Supabase.instance.client);
});
