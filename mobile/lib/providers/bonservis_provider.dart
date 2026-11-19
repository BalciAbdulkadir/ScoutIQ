import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/bonservis_sorusu.dart';
import '../services/gunluk_oyun.dart';
import '../services/analitik.dart';
import '../services/oyun_sonu.dart';
import '../services/oyun_deposu.dart';

enum BonservisDurumu { yukleniyor, oynaniyor, bitti, zatenOynandi, oyunYok, hata }

const _ayni = Object();

class BonservisState {
  final BonservisDurumu durum;
  final List<BonservisSorusu> sorular;
  final int soruIndex;
  final int skor; // Puan: her doğru tahmin 2 puan
  final List<bool> sonuclar; // Cevaplanan soruların doğru/yanlış sonucu, ilerleme çubuğu için
  final bool? sonCevapDogru; // Doluysa şu anki sorunun cevabı verildi ve sonuç gösteriliyor
  final bool gonderiliyor;
  final String? tarih;
  final String? hataMesaji;
  final DateTime? bitisZamani; // Süreli oyunda sürenin dolacağı an; süresizse null
  final bool sureDoldu; // Oyun süre dolduğu için bitti

  const BonservisState({
    this.durum = BonservisDurumu.yukleniyor,
    this.sorular = const [],
    this.soruIndex = 0,
    this.skor = 0,
    this.sonuclar = const [],
    this.sonCevapDogru,
    this.gonderiliyor = false,
    this.tarih,
    this.hataMesaji,
    this.bitisZamani,
    this.sureDoldu = false,
  });

  BonservisSorusu? get soru => soruIndex < sorular.length ? sorular[soruIndex] : null;
  bool get sonSoru => soruIndex == sorular.length - 1;
  bool get tahminEdilebilir => durum == BonservisDurumu.oynaniyor && !gonderiliyor && sonCevapDogru == null;

  BonservisState copyWith({
    BonservisDurumu? durum,
    List<BonservisSorusu>? sorular,
    int? soruIndex,
    int? skor,
    List<bool>? sonuclar,
    Object? sonCevapDogru = _ayni,
    bool? gonderiliyor,
    String? tarih,
    String? hataMesaji,
    DateTime? bitisZamani,
    bool? sureDoldu,
  }) {
    return BonservisState(
      durum: durum ?? this.durum,
      sorular: sorular ?? this.sorular,
      soruIndex: soruIndex ?? this.soruIndex,
      skor: skor ?? this.skor,
      sonuclar: sonuclar ?? this.sonuclar,
      sonCevapDogru: identical(sonCevapDogru, _ayni) ? this.sonCevapDogru : sonCevapDogru as bool?,
      gonderiliyor: gonderiliyor ?? this.gonderiliyor,
      tarih: tarih ?? this.tarih,
      hataMesaji: hataMesaji ?? this.hataMesaji,
      bitisZamani: bitisZamani ?? this.bitisZamani,
      sureDoldu: sureDoldu ?? this.sureDoldu,
    );
  }
}

// Bonservis oyunu: her soruda bir oyuncunun bedeli görünür, diğerininki için "daha fazla / daha az" tahmin edilir.
// Yanlış tahminde oyun bitmez, beş sorunun hepsi oynanır. Her doğru tahmin 2 puan (en fazla 10).
// Süre seçildiyse (30, 60 ya da 90 saniye) bütün sorular içindir; dolunca oyun o anki skorla biter.
// Oyundan çıkınca oyun bitmez: süre sunucuda işlemeye devam eder, oyun tekrar açılınca kaldığı sorudan sürer.
// Her zorluk ayrı bir günlük oyundur: bonservis_kolay, bonservis_orta ya da bonservis_zor.
// Tahmin sunucuda kontrol edilir; skor ve ilerleme sunucuda yazılır. Tahmin edilen oyuncunun bedeli soruyla gelmez,
// tahminden sonra sunucudan gelir (033_skor_sunucuda.sql).
class BonservisNotifier extends Notifier<BonservisState> {
  static const puan = 2;

  final GunlukOyunSecimi secim;

  BonservisNotifier(this.secim);

  String get _oyunTipi => secim.oyunTipi;

  // Yeni oyunda seçilen süre, saniye; null: süresiz. Yarım kalan oyunda sunucudaki süre geçerlidir.
  int? get sure => secim.sure;

  late OyunDeposu _depo;

  // Analitik olaylar (services/analitik.dart): başladı, bitti, yarıda bırakıldı
  late OyunOlaylari _olaylar;
  bool _oynaniyor = false;

  void _olaylariDinle() {
    _olaylar = OyunOlaylari(ref.read(analitikProvider), secim.oyunTipi);
    listenSelf((onceki, simdiki) {
      _oynaniyor = simdiki.durum == BonservisDurumu.oynaniyor;
      // Oynanırken bitti (bitmiş oyunu açmak sayılmaz)
      if (onceki != null && onceki.durum == BonservisDurumu.oynaniyor && simdiki.durum == BonservisDurumu.bitti) {
        _olaylar.bitti(skor: simdiki.skor, sebep: simdiki.sureDoldu ? BitisSebebi.sureDoldu : BitisSebebi.tamamlandi);
        ref.read(oyunSonuProvider).oyunBitti(gunlukOyunTipi: _olaylar.gunlukOyunTipi, skor: simdiki.skor);
      }
    });
    ref.onDispose(() {
      if (_oynaniyor) _olaylar.yaridaBirakildi();
    });
  }
  String? _oyunId;

  @override
  BonservisState build() {
    _depo = ref.read(oyunDeposuProvider);
    // Veriyi build bittikten sonra yüklüyoruz, build'in başlangıç durumu sonucun üzerine yazmasın
    _olaylariDinle();
    Future.microtask(_yukle);
    return const BonservisState();
  }

  Future<void> _yukle() async {
    try {
      final acilis = await gunlukOyunuAc(_depo, _oyunTipi, sure: sure);
      if (!ref.mounted) return;

      state = switch (acilis) {
        Oynanabilir(:final sorular, :final tarih, :final skor, :final ilerleme, :final kalanSaniye) =>
          _devamDurumu(bonservisSorulariniOku(sorular), tarih, skor, ilerleme, kalanSaniye),
        ZatenOynandi(:final skor) => state.copyWith(durum: BonservisDurumu.zatenOynandi, skor: skor),
        OyunYok() => state.copyWith(durum: BonservisDurumu.oyunYok),
        OturumYok() => state.copyWith(durum: BonservisDurumu.hata, hataMesaji: oturumYokMesaji),
        BaskaZorlukOynandi() => state.copyWith(durum: BonservisDurumu.hata, hataMesaji: baskaZorlukMesaji),
      };
      if (acilis is Oynanabilir) {
        _oyunId = acilis.oyunId;
        if (acilis.yeni) _olaylar.basladi(sure: sure);
        // Oyun kapalıyken süre dolmuşsa ya da bütün sorular cevaplanmış ama kayıt kapanmamışsa oyun bitirilir
        final sureDoldu = acilis.kalanSaniye != null && acilis.kalanSaniye! <= 0;
        if (sureDoldu || state.sonuclar.length >= state.sorular.length) {
          await _kapat(sureDoldu: sureDoldu);
        } else if (state.sonuclar.isNotEmpty) {
          // Yarım kalan oyunda cevaplanmış soruların bedelleri bitiş özeti için
          await _bedelleriYukle();
        }
      }
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(durum: BonservisDurumu.hata, hataMesaji: yuklemeHataMesaji);
    }
  }

  // Oyun açılınca kurulan durum. Yarım kalan oyun kaldığı sorudan devam eder.
  BonservisState _devamDurumu(
    List<BonservisSorusu> sorular,
    String tarih,
    int skor,
    List<Map<String, dynamic>> ilerleme,
    int? kalanSaniye,
  ) {
    return state.copyWith(
      durum: BonservisDurumu.oynaniyor,
      sorular: sorular,
      tarih: tarih,
      soruIndex: sorular.isEmpty ? 0 : ilerleme.length.clamp(0, sorular.length - 1),
      skor: skor,
      sonuclar: [for (final c in ilerleme) c['dogru'] == true],
      bitisZamani: kalanSaniye == null ? null : DateTime.now().add(Duration(seconds: kalanSaniye)),
    );
  }

  // Rakibin bedeli için tahmin; sunucu kontrol edip skoru yazar ve bedeli döndürür.
  // Hata olursa mesajını döndürür, başarılıysa null.
  Future<String?> tahminEt({required bool dahaFazla}) async {
    final soru = state.soru;
    if (!state.tahminEdilebilir || soru == null) return null;
    if (_depo.kullaniciId == null) return oturumYokMesaji;

    state = state.copyWith(gonderiliyor: true);

    try {
      final sonuc = await _depo.bonservisTahmin(oyunId: _oyunId!, soruIndex: state.soruIndex, dahaFazla: dahaFazla);
      if (!ref.mounted) return null;

      if (sonuc.sureDoldu) {
        // Süre sunucuda dolmuştu: tahmin sayılmadı, oyun o anki skorla bitti
        state = state.copyWith(durum: BonservisDurumu.bitti, sureDoldu: true, skor: sonuc.skor, gonderiliyor: false);
        await _bedelleriYukle();
        return null;
      }

      final bedel = sonuc.rakipBonservis;
      state = state.copyWith(
        sorular: bedel == null
            ? null
            : [
                for (var i = 0; i < state.sorular.length; i++)
                  i == state.soruIndex ? state.sorular[i].rakipBedeliyle(bedel) : state.sorular[i],
              ],
        skor: sonuc.skor,
        sonuclar: [...state.sonuclar, sonuc.dogru],
        sonCevapDogru: sonuc.dogru,
        gonderiliyor: false,
      );
      return null;
    } on OyunAcikDegil {
      // Kayıt başka bir yerden kapatılmış: oyun artık oynanamaz
      if (!ref.mounted) return null;
      state = state.copyWith(durum: BonservisDurumu.zatenOynandi, gonderiliyor: false);
      return null;
    } catch (e) {
      if (!ref.mounted) return null;
      state = state.copyWith(gonderiliyor: false);
      return gonderimHataMesaji;
    }
  }

  // Sonuç gösterildikten sonra sıradaki soruya geçer ya da oyunu bitirir
  void devamEt() {
    if (state.durum != BonservisDurumu.oynaniyor || state.sonCevapDogru == null) return;

    if (state.sonSoru) {
      state = state.copyWith(durum: BonservisDurumu.bitti);
      return;
    }

    state = state.copyWith(soruIndex: state.soruIndex + 1, sonCevapDogru: null);
  }

  // Ekrandaki sayaç sıfıra inince çağrılır: oyun o anki skorla biter, cevaplanmayan sorular boş kalır.
  // Tahmin gönderilirken çağrılırsa yok sayılır; sayaç sıfırda kaldıkça tekrar çağırır.
  Future<void> sureDoldu() async {
    if (state.durum != BonservisDurumu.oynaniyor || state.gonderiliyor) return;
    await _kapat(sureDoldu: true);
  }

  // Kaydı o anki skorla kapatır (skor sunucuda kalır) ve bitiş ekranını açar
  Future<void> _kapat({required bool sureDoldu}) async {
    state = state.copyWith(gonderiliyor: true);

    if (_depo.kullaniciId != null && _oyunId != null) {
      try {
        // Son sorunun cevabı verildiyse kayıt zaten kapalıdır; sunucu bir şey yapmaz
        await _depo.oyunuBitir(_oyunId!);
      } catch (_) {
        // Kayıt kapatılamazsa açık kalır; süre sunucuda da dolduğu için sonradan tahmin kabul edilmez
      }
    }
    if (!ref.mounted) return;

    state = state.copyWith(durum: BonservisDurumu.bitti, sureDoldu: sureDoldu, gonderiliyor: false);
    await _bedelleriYukle();
  }

  // Sağdaki oyuncuların bedelleri sunucudan: cevaplananlarınki, oyun bittiyse hepsi (bitiş özeti için).
  // Bedeller özete ek bilgidir: gelmezse "?" kalır, hata kullanıcıya yansıtılmaz.
  Future<void> _bedelleriYukle() async {
    final oyunId = _oyunId;
    if (oyunId == null) return;
    try {
      final bedeller = await _depo.bonservisBedelleri(oyunId);
      if (!ref.mounted || bedeller.isEmpty) return;
      state = state.copyWith(sorular: [
        for (var i = 0; i < state.sorular.length; i++)
          bedeller[i] != null ? state.sorular[i].rakipBedeliyle(bedeller[i]!) : state.sorular[i],
      ]);
    } catch (_) {}
  }
}

// Parametre: zorluğun oyun tipi (ör. bonservis_zor) ve seçilen süre
final bonservisProvider =
    NotifierProvider.autoDispose.family<BonservisNotifier, BonservisState, GunlukOyunSecimi>(BonservisNotifier.new);
