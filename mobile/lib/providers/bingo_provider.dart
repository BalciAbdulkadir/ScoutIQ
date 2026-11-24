import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/bingo.dart';
import '../models/oyun_paketi.dart';
import '../services/gunluk_oyun.dart';
import '../services/analitik.dart';
import '../services/hata_kaydi.dart';
import 'puan_provider.dart';
import '../services/oyun_sonu.dart';
import '../services/oyun_deposu.dart';

enum BingoDurumu { yukleniyor, oynaniyor, bitti, oyunYok, hata }

// Son hamle: hangi oyuncu, nereye, sonucu ne oldu. Kartın üstündeki satırda gösterilir.
typedef SonBingoHamlesi = ({BingoOyuncusu oyuncu, int? hucre, bool dogru});

class BingoState {
  final BingoDurumu durum;
  final BingoKarti? kart;
  final String? oyunId;
  final Map<int, BingoOyuncusu> hucreler; // Dolu kutular: kutu (0-11) -> oyuncu
  final int hamleSayisi; // Sunucuya kaydedilen hamle sayısı (yerleşen ya da pas geçilen oyuncular)
  final int? siradakiSira; // Sıradaki oyuncunun destedeki sırası (1'den); kalmadıysa null
  final Set<int> yerlesenler; // Kutuya yerleşmiş oyuncuların destedeki sıraları: bunlar bir daha gelmez
  final bool gonderiliyor; // Hamle ya da pes etme sunucuda işlenirken ikinci isteği engeller
  final String? hataMesaji; // durum 'hata' iken gösterilir
  final SonBingoHamlesi? sonHamle;
  final Map<int, BingoOyuncusu> ornekCevaplar; // Oyun bitince boş kutular için sunucudan gelen örnek cevaplar
  final int? sureSaniye; // Süreli oyunda seçilen toplam süre; süresizse null
  final DateTime? bitisZamani; // Süreli oyunda sürenin dolacağı an (cihaz saatine göre)
  final bool sureDoldu; // Oyun süre dolduğu için bitti
  final int cezaSayisi; // Süreli oyunda yanlış kutu cezası (2 sn) sayısı: sayacın yanındaki "−2 sn" her artışta görünür

  const BingoState({
    this.durum = BingoDurumu.yukleniyor,
    this.kart,
    this.oyunId,
    this.hucreler = const {},
    this.hamleSayisi = 0,
    this.siradakiSira,
    this.yerlesenler = const {},
    this.gonderiliyor = false,
    this.hataMesaji,
    this.sonHamle,
    this.ornekCevaplar = const {},
    this.sureSaniye,
    this.bitisZamani,
    this.sureDoldu = false,
    this.cezaSayisi = 0,
  });

  // Skor dolu kutu sayısıdır
  int get skor => hucreler.length;

  // Sırası gelen oyuncu; oyuncu kalmadıysa null
  BingoOyuncusu? get siradaki {
    final sira = siradakiSira;
    if (kart == null || sira == null || sira < 1 || sira > kart!.deste.length) return null;
    return kart!.deste[sira - 1];
  }

  // Sıradaki oyuncunun az önce yanlış konduğu kutu: kartta kırmızı gösterilir, oyuncu başka kutu deneyebilir
  int? get yanlisKutu {
    final h = sonHamle;
    if (h == null || h.dogru || h.hucre == null || !identical(h.oyuncu, siradaki)) return null;
    return h.hucre;
  }

  BingoState copyWith({
    BingoDurumu? durum,
    BingoKarti? kart,
    String? oyunId,
    Map<int, BingoOyuncusu>? hucreler,
    int? hamleSayisi,
    int? Function()? siradakiSira,
    Set<int>? yerlesenler,
    bool? gonderiliyor,
    String? hataMesaji,
    SonBingoHamlesi? sonHamle,
    Map<int, BingoOyuncusu>? ornekCevaplar,
    int? sureSaniye,
    DateTime? bitisZamani,
    bool? sureDoldu,
    int? cezaSayisi,
  }) {
    return BingoState(
      durum: durum ?? this.durum,
      kart: kart ?? this.kart,
      oyunId: oyunId ?? this.oyunId,
      hucreler: hucreler ?? this.hucreler,
      hamleSayisi: hamleSayisi ?? this.hamleSayisi,
      siradakiSira: siradakiSira != null ? siradakiSira() : this.siradakiSira,
      yerlesenler: yerlesenler ?? this.yerlesenler,
      gonderiliyor: gonderiliyor ?? this.gonderiliyor,
      hataMesaji: hataMesaji ?? this.hataMesaji,
      sonHamle: sonHamle ?? this.sonHamle,
      ornekCevaplar: ornekCevaplar ?? this.ornekCevaplar,
      sureSaniye: sureSaniye ?? this.sureSaniye,
      bitisZamani: bitisZamani ?? this.bitisZamani,
      sureDoldu: sureDoldu ?? this.sureDoldu,
      cezaSayisi: cezaSayisi ?? this.cezaSayisi,
    );
  }
}

// Bingo oyunu. Destedeki oyuncular sırayla gelir; kullanıcı her oyuncuyu uyduğu kutuya koyar ya da pas geçer.
// Yanlış kutuya konan oyuncu gitmez, başka kutu denenebilir. Süreli oyunda her yanlış kutu süreden 2 saniye düşer
// (043_sure_40_bingo_ceza.sql; süreyi sunucu tutar, sayaç sunucunun döndürdüğü kalan süreye göre düzeltilir). Oyuncu sadece doğru kutuya konunca
// ya da pas geçilince sıradakine geçilir. Pas sınırsızdır: destede sıra döner, pas geçilen oyuncu tekrar gelir
// (sıradaki oyuncuyu sunucu söyler, 023_bingo_sinirsiz_pas.sql). Kutuya yerleşen oyuncu bir daha gelmez.
// Deste telefona baştan inmez: açık oyunda sadece görülmüş oyuncular gelir, sıradaki oyuncu hamlenin cevabındadır
// (040_oyun_ac.sql).
// Hamleler sunucuda tutulduğu için yarıda bırakılan kart tekrar açılınca kaldığı yerden devam eder; skor istemciden alınmaz.
// Oyun bütün kutular dolunca, pes edilince ya da süre dolunca biter. Kalan oyuncuların hiçbiri boş kutulara uymuyorsa
// sunucu oyunu bitirir.
class BingoNotifier extends Notifier<BingoState> {
  final GunlukOyunSecimi secim;

  BingoNotifier(this.secim);

  late OyunDeposu _depo;

  // Açılışta ya da hamlede gelen beklenmeyen hata Crashlytics'e gider (services/hata_kaydi.dart); kullanıcıya
  // gösterilen mesaj değişmez. build'de alınır: hata geldiğinde ekran kapanmış olabilir.
  late HataKaydi _hatalar;

  void _hataKaydet(Object hata, StackTrace iz, OyunIslemi islem) =>
      _hatalar.oyunHatasi(hata, iz, islem: islem, oyunTipi: secim.oyunTipi, sure: secim.sure);

  // Analitik olaylar (services/analitik.dart): başladı, bitti, yarıda bırakıldı
  late OyunOlaylari _olaylar;
  bool _oynaniyor = false;
  bool _pesEdildi = false;

  void _olaylariDinle() {
    _olaylar = OyunOlaylari(ref.read(analitikProvider), secim.oyunTipi);
    // Puan bitiş ekranıyla paylaşılır; ekran açık kaldıkça canlı tutulur
    final puan = oyunPuaniProvider(_olaylar.gunlukOyunTipi);
    ref.listen(puan, (_, _) {});
    listenSelf((onceki, simdiki) {
      _oynaniyor = simdiki.durum == BingoDurumu.oynaniyor;
      // Oynanırken bitti (bitmiş oyunu açmak sayılmaz)
      if (onceki != null && onceki.durum == BingoDurumu.oynaniyor && simdiki.durum == BingoDurumu.bitti) {
        final sebep = _pesEdildi ? BitisSebebi.pes : simdiki.sureDoldu ? BitisSebebi.sureDoldu : BitisSebebi.tamamlandi;
        // oyun_bitti puan sunucudan okununca gider (puansız oyunda puan parametresi yok)
        ref.read(puan.notifier).yukle().then((p) => _olaylar.bitti(skor: simdiki.skor, sebep: sebep, puan: p?.puan));
        ref.read(oyunSonuProvider).oyunBitti(gunlukOyunTipi: _olaylar.gunlukOyunTipi, skor: simdiki.skor);
      }
      // Bitmiş oyun açıldıysa da puanı gösterilir
      if (simdiki.durum == BingoDurumu.bitti && onceki?.durum != BingoDurumu.bitti) {
        ref.read(puan.notifier).yukle();
      }
    });
    ref.onDispose(() {
      if (_oynaniyor) _olaylar.yaridaBirakildi();
    });
  }

  @override
  BingoState build() {
    _depo = ref.read(oyunDeposuProvider);
    _hatalar = ref.read(hataKaydiProvider);
    // Veriyi build bittikten sonra yüklüyoruz: build'in döndürdüğü başlangıç durumu sonucun üzerine yazmasın
    _olaylariDinle();
    Future.microtask(_yukle);
    return const BingoState();
  }

  Future<void> _yukle() async {
    try {
      if (_depo.kullaniciId == null) {
        state = state.copyWith(durum: BingoDurumu.hata, hataMesaji: oturumYokMesaji);
        return;
      }

      // Kart, kayıt ve süre tek çağrıyla açılır (040_oyun_ac.sql): kayıt yoksa açılır ve seçilen süre aynı anda başlar;
      // varsa (devam eden ya da bitmiş) kart hamlelerden kurulur. Açık oyunda deste sadece görülmüş oyuncuları taşır,
      // sıradaki oyuncuyu sunucu söyler.
      final OyunPaketi paket;
      try {
        paket = await _depo.oyunAc(secim.oyunTipi, sure: secim.sure);
      } on BaskaModOynandi {
        if (!ref.mounted) return;
        state = state.copyWith(durum: BingoDurumu.hata, hataMesaji: baskaZorlukMesaji);
        return;
      }
      final kart = BingoKarti.oku(paket.soruVerisi);
      if (!ref.mounted) return;
      if (paket.durum == OyunPaketiDurumu.yok || paket.oyunId == null || kart == null) {
        state = state.copyWith(durum: BingoDurumu.oyunYok);
        return;
      }
      final oyunId = paket.oyunId!;
      if (paket.yeni) _olaylar.basladi(sure: secim.sure);

      final hamleler = await _depo.bingoHamleleri(oyunId);
      if (!ref.mounted) return;

      final yerlesenHamleler = [
        for (final h in hamleler)
          if (h.dogru && h.hucre != null && h.oyuncu >= 1 && h.oyuncu <= kart.deste.length && kart.deste[h.oyuncu - 1] != null)
            h,
      ];
      final hucreler = {for (final h in yerlesenHamleler) h.hucre!: kart.deste[h.oyuncu - 1]!};
      final yerlesenler = {for (final h in yerlesenHamleler) h.oyuncu};
      final siradakiSira = paket.siradaki;
      final bitti = paket.bitti || hucreler.length >= kart.hucreSayisi || siradakiSira == null;
      final kalan = paket.kalan;

      state = state.copyWith(
        durum: bitti ? BingoDurumu.bitti : BingoDurumu.oynaniyor,
        kart: kart,
        oyunId: oyunId,
        hucreler: hucreler,
        hamleSayisi: hamleler.length,
        siradakiSira: () => bitti ? null : siradakiSira,
        yerlesenler: yerlesenler,
        sureSaniye: paket.sure,
        bitisZamani: bitti || kalan == null ? null : DateTime.now().add(Duration(seconds: kalan)),
        // Uygulama kapalıyken süre dolmuş: sunucu kartı o anki skorla kapattı
        sureDoldu: paket.sureDoldu,
      );
      if (bitti) await _ornekCevaplariYukle();
    } catch (e, iz) {
      _hataKaydet(e, iz, OyunIslemi.acilis);
      if (!ref.mounted) return;
      state = state.copyWith(durum: BingoDurumu.hata, hataMesaji: yuklemeHataMesaji);
    }
  }

  // Sırası gelen oyuncuyu kutuya koyar. Hata olursa mesajını döndürür, başarılıysa null.
  Future<String?> yerlestir(int hucre) {
    if (state.hucreler.containsKey(hucre)) return Future.value(null);
    return _hamle(hucre);
  }

  // Sırası gelen oyuncuyu pas geçer
  Future<String?> pasGec() => _hamle(null);

  Future<String?> _hamle(int? hucre) async {
    final oyuncu = state.siradaki;
    final oyuncuSira = state.siradakiSira;
    if (state.durum != BingoDurumu.oynaniyor || state.gonderiliyor || oyuncu == null || oyuncuSira == null) return null;
    state = state.copyWith(gonderiliyor: true);

    BingoHamleSonucu sonuc;
    try {
      sonuc = await _depo.bingoHamle(oyunId: state.oyunId!, sira: state.hamleSayisi + 1, hucre: hucre);
    } catch (e, iz) {
      _hataKaydet(e, iz, OyunIslemi.hamle);
      if (!ref.mounted) return null;
      state = state.copyWith(gonderiliyor: false);
      return gonderimHataMesaji;
    }
    if (!ref.mounted) return null;

    final hucreler = {...state.hucreler};
    final yerlesenler = {...state.yerlesenler};
    if (sonuc.dogru && sonuc.hucre != null) {
      hucreler[sonuc.hucre!] = oyuncu;
      yerlesenler.add(oyuncuSira);
    }
    // Yanlış kutu hamle sayılmaz: oyuncu sırada kalır. Süreli oyunda 2 saniye ceza: sayaç sunucunun kalan süresine
    // göre düzeltilir (cevap gelmediyse 2 saniye düşülür)
    final yanlis = hucre != null && !sonuc.dogru && !sonuc.sureDoldu;
    final ceza = yanlis && state.bitisZamani != null;
    final bitisZamani = !ceza
        ? null
        : sonuc.kalan != null
            ? DateTime.now().add(Duration(seconds: sonuc.kalan!))
            : state.bitisZamani!.subtract(const Duration(seconds: 2));
    final kaydedildi = !sonuc.sureDoldu && !(hucre != null && !sonuc.dogru);
    // Sıradaki oyuncuyu sunucu söyler; oyuncunun kendisi de cevapla gelir (deste baştan telefona inmez)
    final siradakiSira = kaydedildi ? sonuc.siradaki : oyuncuSira;
    final siradakiOyuncu = sonuc.siradakiOyuncu;
    final kart = siradakiSira != null && siradakiOyuncu != null ? state.kart!.oyuncuyla(siradakiSira, siradakiOyuncu) : null;

    state = state.copyWith(
      durum: sonuc.bitti ? BingoDurumu.bitti : BingoDurumu.oynaniyor,
      kart: kart,
      hucreler: hucreler,
      yerlesenler: yerlesenler,
      hamleSayisi: kaydedildi ? state.hamleSayisi + 1 : state.hamleSayisi,
      siradakiSira: () => siradakiSira,
      sonHamle: sonuc.sureDoldu ? null : (oyuncu: oyuncu, hucre: hucre, dogru: sonuc.dogru),
      gonderiliyor: false,
      sureDoldu: sonuc.sureDoldu,
      bitisZamani: bitisZamani,
      cezaSayisi: ceza ? state.cezaSayisi + 1 : null,
    );

    if (sonuc.bitti) await _ornekCevaplariYukle();
    return null;
  }

  // Oyunu o anki skorla bitirir
  Future<String?> pesEt() async {
    if (state.durum != BingoDurumu.oynaniyor || state.gonderiliyor) return null;
    state = state.copyWith(gonderiliyor: true);
    _pesEdildi = true;

    try {
      await _depo.bingoPesEt(state.oyunId!);
    } catch (e, iz) {
      _hataKaydet(e, iz, OyunIslemi.pes);
      if (!ref.mounted) return null;
      state = state.copyWith(gonderiliyor: false);
      return 'Bağlantı sorunu. İnternet bağlantını kontrol edip tekrar dene.';
    }
    if (!ref.mounted) return null;

    state = state.copyWith(durum: BingoDurumu.bitti, gonderiliyor: false);
    await _ornekCevaplariYukle();
    return null;
  }

  // Ekrandaki sayaç sıfıra inince çağrılır: kart o anki skorla kapatılır.
  // Sunucu da süreyi kontrol ettiği için bu çağrı gelmese bile süre dolduktan sonra hamle kabul edilmez.
  Future<void> sureDoldu() async {
    if (state.durum != BingoDurumu.oynaniyor || state.gonderiliyor) return;
    state = state.copyWith(gonderiliyor: true);

    try {
      await _depo.bingoPesEt(state.oyunId!);
    } catch (_) {
      // Bağlantı yoksa kart yine kapalı gösterilir; sunucu süresi dolan hamleyi zaten kabul etmez
    }
    if (!ref.mounted) return;

    state = state.copyWith(durum: BingoDurumu.bitti, gonderiliyor: false, sureDoldu: true);
    await _ornekCevaplariYukle();
  }

  // Örnek cevaplar karta ek bilgidir: gelmezse boş kutular boş kalır, hata kullanıcıya yansıtılmaz
  Future<void> _ornekCevaplariYukle() async {
    if (state.skor >= state.kart!.hucreSayisi) return;
    try {
      final ornekler = await _depo.bingoOrnekCevaplar(state.oyunId!);
      if (!ref.mounted) return;
      state = state.copyWith(ornekCevaplar: ornekler);
    } catch (_) {}
  }
}

// Parametre: oyun tipi ('bingo') ve seçilen süre
final bingoProvider = NotifierProvider.autoDispose.family<BingoNotifier, BingoState, GunlukOyunSecimi>(BingoNotifier.new);
