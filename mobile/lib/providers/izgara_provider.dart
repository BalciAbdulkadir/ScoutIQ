import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/izgara.dart';
import '../models/oyun_paketi.dart';
import '../models/oyuncu_oneri.dart';
import '../services/gunluk_oyun.dart';
import '../services/analitik.dart';
import '../services/hata_kaydi.dart';
import 'puan_provider.dart';
import '../services/oyun_sonu.dart';
import '../services/oyun_deposu.dart';

const baskaIzgaraMesaji = 'Bugünün Izgarasını başka bir zorlukta oynadın. Yeni tahta gece yarısı açılıyor.';

enum IzgaraDurumu { yukleniyor, oynaniyor, bitti, oyunYok, hata }

class IzgaraState {
  final IzgaraDurumu durum;
  final IzgaraTahtasi? tahta;
  final String? oyunId;
  final Map<int, IzgaraOyuncusu> hucreler; // Dolu hücreler: hücre (0-8) -> oyuncu
  final int tahminSayisi; // Sayılan (tekrar olmayan) tahmin sayısı; tahmin hakkı sınırı yoktur
  final bool gonderiliyor; // Tahmin ya da pes etme sunucuda işlenirken ikinci isteği engeller
  final String? hataMesaji; // durum 'hata' iken gösterilir
  final IzgaraTahminSonucu? sonTahmin; // Arama kutusunun altında gösterilen son tahminin sonucu
  final Map<int, IzgaraOyuncusu> ornekCevaplar; // Oyun bitince boş hücreler için sunucudan gelen örnek cevaplar
  final int? sureSaniye; // Süreli tahtada seçilen toplam süre; süresizse null
  final DateTime? bitisZamani; // Süreli tahtada sürenin dolacağı an (cihaz saatine göre)
  final bool sureDoldu; // Oyun süre dolduğu için bitti
  final IzgaraKutuSecimi? kutuSecimi; // Oyuncu birden fazla boş kutuya uyuyor: kullanıcının seçmesi bekleniyor

  const IzgaraState({
    this.durum = IzgaraDurumu.yukleniyor,
    this.tahta,
    this.oyunId,
    this.hucreler = const {},
    this.tahminSayisi = 0,
    this.gonderiliyor = false,
    this.hataMesaji,
    this.sonTahmin,
    this.ornekCevaplar = const {},
    this.sureSaniye,
    this.bitisZamani,
    this.sureDoldu = false,
    this.kutuSecimi,
  });

  // Skor dolu hücre sayısıdır
  int get skor => hucreler.length;

  IzgaraState copyWith({
    IzgaraDurumu? durum,
    IzgaraTahtasi? tahta,
    String? oyunId,
    Map<int, IzgaraOyuncusu>? hucreler,
    int? tahminSayisi,
    bool? gonderiliyor,
    String? hataMesaji,
    IzgaraTahminSonucu? sonTahmin,
    Map<int, IzgaraOyuncusu>? ornekCevaplar,
    int? sureSaniye,
    DateTime? bitisZamani,
    bool? sureDoldu,
    IzgaraKutuSecimi? Function()? kutuSecimi, // null'a çekmek için: kutuSecimi: () => null
  }) {
    return IzgaraState(
      durum: durum ?? this.durum,
      tahta: tahta ?? this.tahta,
      oyunId: oyunId ?? this.oyunId,
      hucreler: hucreler ?? this.hucreler,
      tahminSayisi: tahminSayisi ?? this.tahminSayisi,
      gonderiliyor: gonderiliyor ?? this.gonderiliyor,
      hataMesaji: hataMesaji ?? this.hataMesaji,
      sonTahmin: sonTahmin ?? this.sonTahmin,
      ornekCevaplar: ornekCevaplar ?? this.ornekCevaplar,
      sureSaniye: sureSaniye ?? this.sureSaniye,
      bitisZamani: bitisZamani ?? this.bitisZamani,
      sureDoldu: sureDoldu ?? this.sureDoldu,
      kutuSecimi: kutuSecimi != null ? kutuSecimi() : this.kutuSecimi,
    );
  }
}

// Izgara oyunu. Kesişim'den farkı: tahminler sunucuda tutulduğu için yarıda bırakılan tahta
// tekrar açılınca kaldığı yerden devam eder; skor istemciden alınmaz.
// Tahmin hakkı sınırı yoktur: oyun dokuz kutu dolunca, pes edilince ya da süre dolunca biter.
class IzgaraNotifier extends Notifier<IzgaraState> {
  final IzgaraAcilisi acilis;

  IzgaraNotifier(this.acilis);

  IzgaraZorlugu get zorluk => acilis.zorluk;

  late OyunDeposu _depo;

  // Açılışta ya da hamlede gelen beklenmeyen hata Crashlytics'e gider (services/hata_kaydi.dart); kullanıcıya
  // gösterilen mesaj değişmez. build'de alınır: hata geldiğinde ekran kapanmış olabilir.
  late HataKaydi _hatalar;

  void _hataKaydet(Object hata, StackTrace iz, OyunIslemi islem) =>
      _hatalar.oyunHatasi(hata, iz, islem: islem, oyunTipi: acilis.zorluk.oyunTipi, sure: acilis.sure);

  // Analitik olaylar (services/analitik.dart): başladı, bitti, yarıda bırakıldı
  late OyunOlaylari _olaylar;
  bool _oynaniyor = false;
  bool _pesEdildi = false;

  void _olaylariDinle() {
    _olaylar = OyunOlaylari(ref.read(analitikProvider), acilis.zorluk.oyunTipi);
    // Puan bitiş ekranıyla paylaşılır; ekran açık kaldıkça canlı tutulur
    final puan = oyunPuaniProvider(_olaylar.gunlukOyunTipi);
    ref.listen(puan, (_, _) {});
    listenSelf((onceki, simdiki) {
      _oynaniyor = simdiki.durum == IzgaraDurumu.oynaniyor;
      // Oynanırken bitti (bitmiş oyunu açmak sayılmaz)
      if (onceki != null && onceki.durum == IzgaraDurumu.oynaniyor && simdiki.durum == IzgaraDurumu.bitti) {
        final sebep = _pesEdildi ? BitisSebebi.pes : simdiki.sureDoldu ? BitisSebebi.sureDoldu : BitisSebebi.tamamlandi;
        // oyun_bitti puan sunucudan okununca gider (puansız oyunda puan parametresi yok)
        ref.read(puan.notifier).yukle().then((p) => _olaylar.bitti(skor: simdiki.skor, sebep: sebep, puan: p?.puan));
        ref.read(oyunSonuProvider).oyunBitti(gunlukOyunTipi: _olaylar.gunlukOyunTipi, skor: simdiki.skor);
      }
      // Bitmiş oyun açıldıysa da puanı gösterilir
      if (simdiki.durum == IzgaraDurumu.bitti && onceki?.durum != IzgaraDurumu.bitti) {
        ref.read(puan.notifier).yukle();
      }
    });
    ref.onDispose(() {
      if (_oynaniyor) _olaylar.yaridaBirakildi();
    });
  }

  @override
  IzgaraState build() {
    _depo = ref.read(oyunDeposuProvider);
    _hatalar = ref.read(hataKaydiProvider);
    // Veriyi build bittikten sonra yüklüyoruz: build'in döndürdüğü başlangıç durumu sonucun üzerine yazmasın
    _olaylariDinle();
    Future.microtask(_yukle);
    return const IzgaraState();
  }

  Future<void> _yukle() async {
    try {
      if (_depo.kullaniciId == null) {
        state = state.copyWith(durum: IzgaraDurumu.hata, hataMesaji: oturumYokMesaji);
        return;
      }

      // Tahta, kayıt ve süre tek çağrıyla açılır (040_oyun_ac.sql): kayıt yoksa açılır ve seçilen süre aynı anda başlar;
      // varsa (devam eden ya da bitmiş) tahta tahminlerden kurulur, süre sunucudaki kalan süredir
      final OyunPaketi paket;
      try {
        paket = await _depo.oyunAc(zorluk.oyunTipi, sure: acilis.sure);
      } on BaskaModOynandi {
        if (!ref.mounted) return;
        state = state.copyWith(durum: IzgaraDurumu.hata, hataMesaji: baskaIzgaraMesaji);
        return;
      }
      final tahta = IzgaraTahtasi.oku(paket.soruVerisi);
      if (!ref.mounted) return;
      if (paket.durum == OyunPaketiDurumu.yok || paket.oyunId == null || tahta == null) {
        state = state.copyWith(durum: IzgaraDurumu.oyunYok);
        return;
      }
      final oyunId = paket.oyunId!;
      if (paket.yeni) _olaylar.basladi(sure: acilis.sure);

      final tahminler = await _depo.izgaraTahminleri(oyunId);
      if (!ref.mounted) return;

      final bitti = paket.bitti || tahminler.where((t) => t.hucre != null).length >= izgaraBoyutu * izgaraBoyutu;
      final kalan = paket.kalan;

      state = state.copyWith(
        durum: bitti ? IzgaraDurumu.bitti : IzgaraDurumu.oynaniyor,
        sureSaniye: paket.sure,
        bitisZamani: bitti || kalan == null ? null : DateTime.now().add(Duration(seconds: kalan)),
        // Uygulama kapalıyken süre dolmuş: sunucu tahtayı o anki skorla kapattı
        sureDoldu: paket.sureDoldu,
        tahta: tahta,
        oyunId: oyunId,
        hucreler: {
          for (final t in tahminler)
            if (t.hucre != null) t.hucre!: IzgaraOyuncusu(isim: t.oyuncuIsim, fotoUrl: t.fotoUrl),
        },
        tahminSayisi: tahminler.length,
      );
      if (bitti) await _ornekCevaplariYukle();
    } catch (e, iz) {
      _hataKaydet(e, iz, OyunIslemi.acilis);
      if (!ref.mounted) return;
      state = state.copyWith(durum: IzgaraDurumu.hata, hataMesaji: yuklemeHataMesaji);
    }
  }

  Future<List<OyuncuOneri>> oyuncuAra(String metin) => _depo.oyuncuAra(metin);

  // Seçilen oyuncuyu sunucuya gönderir. Hata olursa mesajını döndürür, başarılıysa null.
  // hucre: kutu seçiminde kullanıcının dokunduğu kutu. Oyuncu birden fazla boş kutuya uyuyorsa sunucu kayıt yapmaz,
  // uyduğu kutuları döndürür: tahmin sayılmaz, kutuSecimi dolar ve kullanıcı birini seçer (kutuSec).
  Future<String?> tahminEt(OyuncuOneri oyuncu, {int? hucre}) async {
    if (state.durum != IzgaraDurumu.oynaniyor || state.gonderiliyor) return null;
    state = state.copyWith(gonderiliyor: true);

    IzgaraTahminSonucu sonuc;
    try {
      sonuc = await _depo.izgaraTahmin(oyunId: state.oyunId!, oyuncuId: oyuncu.id, hucre: hucre);
    } catch (e, iz) {
      _hataKaydet(e, iz, OyunIslemi.hamle);
      if (!ref.mounted) return null;
      state = state.copyWith(gonderiliyor: false, kutuSecimi: () => null);
      return gonderimHataMesaji;
    }
    if (!ref.mounted) return null;

    if (sonuc.secim && !sonuc.bitti) {
      state = state.copyWith(
        gonderiliyor: false,
        kutuSecimi: () => IzgaraKutuSecimi(oyuncu: oyuncu, hucreler: sonuc.secenekler.toSet()),
      );
      return null;
    }

    final hucreler = {...state.hucreler};
    if (sonuc.dogru && sonuc.hucre != null) {
      hucreler[sonuc.hucre!] = IzgaraOyuncusu(isim: sonuc.oyuncuIsim, fotoUrl: sonuc.fotoUrl ?? oyuncu.fotoUrl);
    }

    state = state.copyWith(
      durum: sonuc.bitti ? IzgaraDurumu.bitti : IzgaraDurumu.oynaniyor,
      hucreler: hucreler,
      tahminSayisi: sonuc.tekrar || sonuc.sureDoldu ? state.tahminSayisi : state.tahminSayisi + 1,
      sonTahmin: sonuc,
      gonderiliyor: false,
      sureDoldu: sonuc.sureDoldu,
      kutuSecimi: () => null,
    );

    if (sonuc.bitti) await _ornekCevaplariYukle();
    return null;
  }

  // Kutu seçiminde vurgulanan kutulardan birine dokunuldu: oyuncu o kutuyla gönderilir. Vurgulu olmayan kutu bir şey yapmaz.
  Future<String?> kutuSec(int hucre) async {
    final secim = state.kutuSecimi;
    if (secim == null || !secim.hucreler.contains(hucre)) return null;
    return tahminEt(secim.oyuncu, hucre: hucre);
  }

  // Kutu seçiminden vazgeçildi: oyuncu yerleşmez, tahmin sayılmaz
  void kutuSecimindenVazgec() {
    if (state.kutuSecimi == null) return;
    state = state.copyWith(kutuSecimi: () => null);
  }

  // Oyunu o anki skorla bitirir
  Future<String?> pesEt() async {
    if (state.durum != IzgaraDurumu.oynaniyor || state.gonderiliyor) return null;
    state = state.copyWith(gonderiliyor: true);
    _pesEdildi = true;

    try {
      await _depo.izgaraPesEt(state.oyunId!);
    } catch (e, iz) {
      _hataKaydet(e, iz, OyunIslemi.pes);
      if (!ref.mounted) return null;
      state = state.copyWith(gonderiliyor: false);
      return 'Bağlantı sorunu. İnternet bağlantını kontrol edip tekrar dene.';
    }
    if (!ref.mounted) return null;

    state = state.copyWith(durum: IzgaraDurumu.bitti, gonderiliyor: false, kutuSecimi: () => null);
    await _ornekCevaplariYukle();
    return null;
  }

  // Ekrandaki sayaç sıfıra inince çağrılır: tahta o anki skorla kapatılır.
  // Sunucu da süreyi kontrol ettiği için bu çağrı gelmese bile süre dolduktan sonra tahmin kabul edilmez.
  Future<void> sureDoldu() async {
    if (state.durum != IzgaraDurumu.oynaniyor || state.gonderiliyor) return;
    state = state.copyWith(gonderiliyor: true);

    try {
      await _depo.izgaraPesEt(state.oyunId!);
    } catch (_) {
      // Bağlantı yoksa tahta yine kapalı gösterilir; sunucu süresi dolan tahmini zaten kabul etmez
    }
    if (!ref.mounted) return;

    state = state.copyWith(durum: IzgaraDurumu.bitti, gonderiliyor: false, sureDoldu: true, kutuSecimi: () => null);
    await _ornekCevaplariYukle();
  }

  // Örnek cevaplar tahtaya ek bilgidir: gelmezse boş hücreler boş kalır, hata kullanıcıya yansıtılmaz
  Future<void> _ornekCevaplariYukle() async {
    if (state.skor >= izgaraBoyutu * izgaraBoyutu) return;
    try {
      final ornekler = await _depo.izgaraOrnekCevaplar(state.oyunId!);
      if (!ref.mounted) return;
      state = state.copyWith(ornekCevaplar: ornekler);
    } catch (_) {}
  }
}

final izgaraProvider = NotifierProvider.autoDispose.family<IzgaraNotifier, IzgaraState, IzgaraAcilisi>(IzgaraNotifier.new);
