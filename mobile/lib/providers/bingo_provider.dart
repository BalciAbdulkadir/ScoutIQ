import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/bingo.dart';
import '../models/izgara.dart' show OyunSuresiDurumu;
import '../providers/hub_provider.dart';
import '../services/gunluk_oyun.dart';
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
    );
  }
}

// Bingo oyunu. Destedeki oyuncular sırayla gelir; kullanıcı her oyuncuyu uyduğu kutuya koyar ya da pas geçer.
// Yanlış kutuya konan oyuncu gitmez, ceza da yoktur: başka kutu denenebilir. Oyuncu sadece doğru kutuya konunca
// ya da pas geçilince sıradakine geçilir. Pas sınırsızdır: destede sıra döner, pas geçilen oyuncu tekrar gelir
// (bingoSiradaki). Kutuya yerleşen oyuncu bir daha gelmez.
// Hamleler sunucuda tutulduğu için yarıda bırakılan kart tekrar açılınca kaldığı yerden devam eder; skor istemciden alınmaz.
// Oyun bütün kutular dolunca, pes edilince ya da süre dolunca biter. Kalan oyuncuların hiçbiri boş kutulara uymuyorsa
// sunucu oyunu bitirir.
class BingoNotifier extends Notifier<BingoState> {
  final GunlukOyunSecimi secim;

  BingoNotifier(this.secim);

  late OyunDeposu _depo;

  @override
  BingoState build() {
    _depo = ref.read(oyunDeposuProvider);
    // Veriyi build bittikten sonra yüklüyoruz: build'in döndürdüğü başlangıç durumu sonucun üzerine yazmasın
    Future.microtask(_yukle);
    return const BingoState();
  }

  Future<void> _yukle() async {
    try {
      final kullaniciId = _depo.kullaniciId;
      if (kullaniciId == null) {
        state = state.copyWith(durum: BingoDurumu.hata, hataMesaji: oturumYokMesaji);
        return;
      }

      String tarih;
      try {
        tarih = await _depo.oyunTarihi();
      } catch (_) {
        tarih = bugununTarihi();
      }

      final oyun = await _depo.gununOyunu(secim.oyunTipi, tarih);
      final kart = BingoKarti.oku(oyun?['soru_verisi']);
      if (!ref.mounted) return;
      if (oyun == null || kart == null) {
        state = state.copyWith(durum: BingoDurumu.oyunYok);
        return;
      }
      final oyunId = oyun['id'] as String;

      // Kayıt yoksa oyun 'basladi' olarak açılır; varsa (devam eden ya da bitmiş) kart hamlelerden kurulur
      var kayit = await _depo.oyunKaydi(kullaniciId, secim.oyunTipi, tarih);
      var yeni = false;
      if (kayit == null) {
        try {
          await _depo.kayitAc(kullaniciId: kullaniciId, oyunId: oyunId, oyunTipi: secim.oyunTipi, tarih: tarih);
          kayit = {'durum': 'basladi'};
          yeni = true;
        } on KayitZatenVar {
          // Aynı anda başka bir cihazda açılmış: o kayıtla devam ediliyor
          kayit = await _depo.oyunKaydi(kullaniciId, secim.oyunTipi, tarih) ?? {'durum': 'basladi'};
        } on BaskaModOynandi {
          if (!ref.mounted) return;
          state = state.copyWith(durum: BingoDurumu.hata, hataMesaji: baskaZorlukMesaji);
          return;
        }
      }

      final hamleler = await _depo.bingoHamleleri(oyunId);
      if (!ref.mounted) return;

      final yerlesenHamleler = [
        for (final h in hamleler)
          if (h.dogru && h.hucre != null && h.oyuncu >= 1 && h.oyuncu <= kart.deste.length) h,
      ];
      final hucreler = {for (final h in yerlesenHamleler) h.hucre!: kart.deste[h.oyuncu - 1]};
      final yerlesenler = {for (final h in yerlesenHamleler) h.oyuncu};
      final siradakiSira = bingoSiradaki(
        desteBoyutu: kart.deste.length,
        yerlesenler: yerlesenler,
        son: hamleler.isEmpty ? 0 : hamleler.last.oyuncu,
      );
      var bitti = kayit['durum'] == 'tamamlandi' || hucreler.length >= kart.hucreSayisi || siradakiSira == null;

      // Süre: yeni oyunda seçilen süre başlatılır, yarım kalan oyunda sunucudaki kalan süre okunur
      OyunSuresiDurumu? sure;
      if (!bitti) {
        try {
          sure = await _depo.oyunSureyiBaslat(secim.oyunTipi, tarih, sure: yeni ? secim.sure : null);
        } catch (_) {
          // Sunucuya sorulamazsa yeni oyun seçilen süreyle cihazda sayılır, yarım kalan oyun süresiz açılır
          if (yeni && secim.sure != null) sure = OyunSuresiDurumu(toplam: secim.sure!, kalan: secim.sure!);
        }
        if (!ref.mounted) return;
      }
      final sureDoldu = sure != null && sure.kalan <= 0;
      if (sureDoldu) {
        // Uygulama kapalıyken süre dolmuş: kart o anki skorla kapatılır
        await _depo.bingoPesEt(oyunId);
        if (!ref.mounted) return;
        bitti = true;
      }

      state = state.copyWith(
        durum: bitti ? BingoDurumu.bitti : BingoDurumu.oynaniyor,
        kart: kart,
        oyunId: oyunId,
        hucreler: hucreler,
        hamleSayisi: hamleler.length,
        siradakiSira: () => siradakiSira,
        yerlesenler: yerlesenler,
        sureSaniye: sure?.toplam,
        bitisZamani: sure == null || sureDoldu ? null : DateTime.now().add(Duration(seconds: sure.kalan)),
        sureDoldu: sureDoldu,
      );
      if (bitti) await _ornekCevaplariYukle();
    } catch (_) {
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
    } catch (_) {
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
    // Yanlış kutu hamle sayılmaz: oyuncu sırada kalır
    final kaydedildi = !sonuc.sureDoldu && !(hucre != null && !sonuc.dogru);
    // Sıradaki oyuncuyu sunucu söyler; söylemezse aynı kuralla burada bulunur
    final siradakiSira = kaydedildi
        ? sonuc.siradaki ??
            bingoSiradaki(desteBoyutu: state.kart!.deste.length, yerlesenler: yerlesenler, son: oyuncuSira)
        : oyuncuSira;

    state = state.copyWith(
      durum: sonuc.bitti ? BingoDurumu.bitti : BingoDurumu.oynaniyor,
      hucreler: hucreler,
      yerlesenler: yerlesenler,
      hamleSayisi: kaydedildi ? state.hamleSayisi + 1 : state.hamleSayisi,
      siradakiSira: () => siradakiSira,
      sonHamle: sonuc.sureDoldu ? null : (oyuncu: oyuncu, hucre: hucre, dogru: sonuc.dogru),
      gonderiliyor: false,
      sureDoldu: sonuc.sureDoldu,
    );

    if (sonuc.bitti) await _ornekCevaplariYukle();
    return null;
  }

  // Oyunu o anki skorla bitirir
  Future<String?> pesEt() async {
    if (state.durum != BingoDurumu.oynaniyor || state.gonderiliyor) return null;
    state = state.copyWith(gonderiliyor: true);

    try {
      await _depo.bingoPesEt(state.oyunId!);
    } catch (_) {
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
