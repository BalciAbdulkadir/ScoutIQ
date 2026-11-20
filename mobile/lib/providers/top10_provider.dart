import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/oyuncu_oneri.dart';
import '../models/top10.dart';
import '../providers/hub_provider.dart';
import '../services/gunluk_oyun.dart';
import '../services/analitik.dart';
import 'puan_provider.dart';
import '../services/oyun_sonu.dart';
import '../services/oyun_deposu.dart';

enum Top10Durumu { yukleniyor, oynaniyor, bitti, oyunYok, hata }

class Top10State {
  final Top10Durumu durum;
  final Top10Sorusu? soru;
  final String? oyunId;
  final Map<int, Top10Oyuncusu> bulunanlar; // Bulunan satırlar: sıra (1-10) -> oyuncu
  final Set<String> denenenler; // Doğru ya da yanlış denenmiş oyuncu isimleri
  final int yanlisSayisi; // Listede olmayan oyuncu tahminleri; her biri bir can götürür
  final bool gonderiliyor; // Tahmin ya da pes etme sunucuda işlenirken ikinci isteği engeller
  final String? hataMesaji; // durum 'hata' iken gösterilir
  final Top10TahminSonucu? sonTahmin; // Arama kutusunun altında gösterilen son tahminin sonucu
  final Map<int, Top10Oyuncusu> cevaplar; // Oyun bitince bütün liste (bulunamayanlar dahil)

  const Top10State({
    this.durum = Top10Durumu.yukleniyor,
    this.soru,
    this.oyunId,
    this.bulunanlar = const {},
    this.denenenler = const {},
    this.yanlisSayisi = 0,
    this.gonderiliyor = false,
    this.hataMesaji,
    this.sonTahmin,
    this.cevaplar = const {},
  });

  // Her bulunan oyuncu 1 puan
  int get skor => bulunanlar.length;

  int get kalanCan => (top10Can - yanlisSayisi).clamp(0, top10Can);

  Top10State copyWith({
    Top10Durumu? durum,
    Top10Sorusu? soru,
    String? oyunId,
    Map<int, Top10Oyuncusu>? bulunanlar,
    Set<String>? denenenler,
    int? yanlisSayisi,
    bool? gonderiliyor,
    String? hataMesaji,
    Top10TahminSonucu? sonTahmin,
    Map<int, Top10Oyuncusu>? cevaplar,
  }) {
    return Top10State(
      durum: durum ?? this.durum,
      soru: soru ?? this.soru,
      oyunId: oyunId ?? this.oyunId,
      bulunanlar: bulunanlar ?? this.bulunanlar,
      denenenler: denenenler ?? this.denenenler,
      yanlisSayisi: yanlisSayisi ?? this.yanlisSayisi,
      gonderiliyor: gonderiliyor ?? this.gonderiliyor,
      hataMesaji: hataMesaji ?? this.hataMesaji,
      sonTahmin: sonTahmin ?? this.sonTahmin,
      cevaplar: cevaplar ?? this.cevaplar,
    );
  }
}

// Top 10 oyunu. Tahminler sunucuda tutulur: yarıda bırakılan oyun tekrar açılınca kaldığı yerden devam eder.
// Süre yoktur. 3 can vardır: listede olmayan oyuncuyu tahmin etmek bir can götürür.
// Oyun 10 oyuncu bulununca, canlar bitince ya da pes edilince biter. Canlar sunucuda, yanlış tahminlerden hesaplanır.
class Top10Notifier extends Notifier<Top10State> {
  final String oyunTipi;

  Top10Notifier(this.oyunTipi);

  late OyunDeposu _depo;

  // Analitik olaylar (services/analitik.dart): başladı, bitti, yarıda bırakıldı
  late OyunOlaylari _olaylar;
  bool _oynaniyor = false;
  bool _pesEdildi = false;

  void _olaylariDinle() {
    _olaylar = OyunOlaylari(ref.read(analitikProvider), oyunTipi);
    // Puan bitiş ekranıyla paylaşılır; ekran açık kaldıkça canlı tutulur
    final puan = oyunPuaniProvider(_olaylar.gunlukOyunTipi);
    ref.listen(puan, (_, _) {});
    listenSelf((onceki, simdiki) {
      _oynaniyor = simdiki.durum == Top10Durumu.oynaniyor;
      // Oynanırken bitti (bitmiş oyunu açmak sayılmaz)
      if (onceki != null && onceki.durum == Top10Durumu.oynaniyor && simdiki.durum == Top10Durumu.bitti) {
        final sebep = _pesEdildi ? BitisSebebi.pes : simdiki.kalanCan == 0 ? BitisSebebi.canBitti : BitisSebebi.tamamlandi;
        // oyun_bitti puan sunucudan okununca gider (puansız oyunda puan parametresi yok)
        ref.read(puan.notifier).yukle().then((p) => _olaylar.bitti(skor: simdiki.skor, sebep: sebep, puan: p?.puan));
        ref.read(oyunSonuProvider).oyunBitti(gunlukOyunTipi: _olaylar.gunlukOyunTipi, skor: simdiki.skor);
      }
      // Bitmiş oyun açıldıysa da puanı gösterilir
      if (simdiki.durum == Top10Durumu.bitti && onceki?.durum != Top10Durumu.bitti) {
        ref.read(puan.notifier).yukle();
      }
    });
    ref.onDispose(() {
      if (_oynaniyor) _olaylar.yaridaBirakildi();
    });
  }

  @override
  Top10State build() {
    _depo = ref.read(oyunDeposuProvider);
    // Veriyi build bittikten sonra yüklüyoruz: build'in döndürdüğü başlangıç durumu sonucun üzerine yazmasın
    _olaylariDinle();
    Future.microtask(_yukle);
    return const Top10State();
  }

  Future<void> _yukle() async {
    try {
      final kullaniciId = _depo.kullaniciId;
      if (kullaniciId == null) {
        state = state.copyWith(durum: Top10Durumu.hata, hataMesaji: oturumYokMesaji);
        return;
      }

      String tarih;
      try {
        tarih = await _depo.oyunTarihi();
      } catch (_) {
        tarih = bugununTarihi();
      }

      final oyun = await _depo.gununOyunu(oyunTipi, tarih);
      final soru = Top10Sorusu.oku(oyun?['soru_verisi']);
      if (!ref.mounted) return;
      if (oyun == null || soru == null) {
        state = state.copyWith(durum: Top10Durumu.oyunYok);
        return;
      }
      final oyunId = oyun['id'] as String;

      // Kayıt yoksa oyun 'basladi' olarak açılır; varsa (devam eden ya da bitmiş) liste tahminlerden kurulur
      var kayit = await _depo.oyunKaydi(kullaniciId, oyunTipi, tarih);
      if (kayit == null) {
        try {
          await _depo.kayitAc(kullaniciId: kullaniciId, oyunId: oyunId, oyunTipi: oyunTipi, tarih: tarih);
          kayit = {'durum': 'basladi'};
          _olaylar.basladi();
        } on KayitZatenVar {
          // Aynı anda başka bir cihazda açılmış: o kayıtla devam ediliyor
          kayit = await _depo.oyunKaydi(kullaniciId, oyunTipi, tarih) ?? {'durum': 'basladi'};
        }
      }

      final tahminler = await _depo.top10Tahminleri(oyunId);
      if (!ref.mounted) return;
      final yanlisSayisi = tahminler.where((t) => t.sira == null).length;
      final bitti = kayit['durum'] == 'tamamlandi' ||
          tahminler.where((t) => t.sira != null).length >= top10Boyu ||
          yanlisSayisi >= top10Can;

      // Bulunanların değerleri (ve oyun bittiyse bütün liste) sunucudan gelir
      final cevaplar = tahminler.any((t) => t.sira != null) || bitti ? await _depo.top10Cevaplar(oyunId) : <int, Top10Oyuncusu>{};
      if (!ref.mounted) return;
      final bulunanSiralar = {for (final t in tahminler) ?t.sira};

      state = state.copyWith(
        durum: bitti ? Top10Durumu.bitti : Top10Durumu.oynaniyor,
        soru: soru,
        oyunId: oyunId,
        bulunanlar: {
          for (final sira in bulunanSiralar)
            if (cevaplar[sira] != null) sira: cevaplar[sira]!,
        },
        denenenler: {for (final t in tahminler) t.oyuncuIsim},
        yanlisSayisi: yanlisSayisi,
        cevaplar: bitti ? cevaplar : const {},
      );
    } catch (_) {
      if (!ref.mounted) return;
      state = state.copyWith(durum: Top10Durumu.hata, hataMesaji: yuklemeHataMesaji);
    }
  }

  Future<List<OyuncuOneri>> oyuncuAra(String metin) => _depo.oyuncuAra(metin);

  // Seçilen oyuncuyu sunucuya gönderir. Hata olursa mesajını döndürür, başarılıysa null.
  Future<String?> tahminEt(OyuncuOneri oyuncu) async {
    if (state.durum != Top10Durumu.oynaniyor || state.gonderiliyor) return null;
    state = state.copyWith(gonderiliyor: true);

    Top10TahminSonucu sonuc;
    try {
      sonuc = await _depo.top10Tahmin(oyunId: state.oyunId!, oyuncuId: oyuncu.id);
    } catch (_) {
      if (!ref.mounted) return null;
      state = state.copyWith(gonderiliyor: false);
      return gonderimHataMesaji;
    }
    if (!ref.mounted) return null;

    final bulunanlar = {...state.bulunanlar};
    if (sonuc.dogru && sonuc.sira != null) {
      bulunanlar[sonuc.sira!] = Top10Oyuncusu(isim: sonuc.oyuncuIsim, fotoUrl: sonuc.fotoUrl ?? oyuncu.fotoUrl, deger: sonuc.deger);
    }

    // Kalan can sunucudan gelir; göndermeyen eski sunucuda yanlış tahmin burada sayılır
    final yanlisSayisi = sonuc.kalanCan != null
        ? top10Can - sonuc.kalanCan!
        : state.yanlisSayisi + (!sonuc.dogru && !sonuc.tekrar ? 1 : 0);

    state = state.copyWith(
      durum: sonuc.bitti ? Top10Durumu.bitti : Top10Durumu.oynaniyor,
      bulunanlar: bulunanlar,
      denenenler: {...state.denenenler, sonuc.oyuncuIsim},
      yanlisSayisi: yanlisSayisi,
      sonTahmin: sonuc,
      gonderiliyor: false,
    );

    if (sonuc.bitti) await _cevaplariYukle();
    return null;
  }

  // Oyunu o anki skorla bitirir
  Future<String?> pesEt() async {
    if (state.durum != Top10Durumu.oynaniyor || state.gonderiliyor) return null;
    state = state.copyWith(gonderiliyor: true);
    _pesEdildi = true;

    try {
      await _depo.top10PesEt(state.oyunId!);
    } catch (_) {
      if (!ref.mounted) return null;
      state = state.copyWith(gonderiliyor: false);
      return 'Bağlantı sorunu. İnternet bağlantını kontrol edip tekrar dene.';
    }
    if (!ref.mounted) return null;

    state = state.copyWith(durum: Top10Durumu.bitti, gonderiliyor: false);
    await _cevaplariYukle();
    return null;
  }

  // Bütün liste oyun bitince açılır. Gelmezse bulunamayan satırlar boş kalır, hata kullanıcıya yansıtılmaz.
  Future<void> _cevaplariYukle() async {
    try {
      final cevaplar = await _depo.top10Cevaplar(state.oyunId!);
      if (!ref.mounted) return;
      state = state.copyWith(cevaplar: cevaplar);
    } catch (_) {}
  }
}

final top10Provider = NotifierProvider.autoDispose.family<Top10Notifier, Top10State, String>(Top10Notifier.new);
