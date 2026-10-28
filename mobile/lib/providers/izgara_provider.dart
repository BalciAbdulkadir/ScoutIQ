import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/izgara.dart';
import '../models/oyuncu_oneri.dart';
import '../providers/hub_provider.dart';
import '../services/gunluk_oyun.dart';
import '../services/oyun_deposu.dart';

enum IzgaraDurumu { yukleniyor, oynaniyor, bitti, oyunYok, hata }

class IzgaraState {
  final IzgaraDurumu durum;
  final IzgaraTahtasi? tahta;
  final String? oyunId;
  final Map<int, IzgaraOyuncusu> hucreler; // Dolu hücreler: hücre (0-8) -> oyuncu
  final int kalanHak;
  final bool gonderiliyor; // Tahmin ya da pes etme sunucuda işlenirken ikinci isteği engeller
  final String? hataMesaji; // durum 'hata' iken gösterilir
  final IzgaraTahminSonucu? sonTahmin; // Arama kutusunun altında gösterilen son tahminin sonucu
  final Map<int, String> ornekCevaplar; // Oyun bitince boş hücreler için sunucudan gelen örnek cevaplar

  const IzgaraState({
    this.durum = IzgaraDurumu.yukleniyor,
    this.tahta,
    this.oyunId,
    this.hucreler = const {},
    this.kalanHak = izgaraHakSayisi,
    this.gonderiliyor = false,
    this.hataMesaji,
    this.sonTahmin,
    this.ornekCevaplar = const {},
  });

  // Skor dolu hücre sayısıdır
  int get skor => hucreler.length;

  IzgaraState copyWith({
    IzgaraDurumu? durum,
    IzgaraTahtasi? tahta,
    String? oyunId,
    Map<int, IzgaraOyuncusu>? hucreler,
    int? kalanHak,
    bool? gonderiliyor,
    String? hataMesaji,
    IzgaraTahminSonucu? sonTahmin,
    Map<int, String>? ornekCevaplar,
  }) {
    return IzgaraState(
      durum: durum ?? this.durum,
      tahta: tahta ?? this.tahta,
      oyunId: oyunId ?? this.oyunId,
      hucreler: hucreler ?? this.hucreler,
      kalanHak: kalanHak ?? this.kalanHak,
      gonderiliyor: gonderiliyor ?? this.gonderiliyor,
      hataMesaji: hataMesaji ?? this.hataMesaji,
      sonTahmin: sonTahmin ?? this.sonTahmin,
      ornekCevaplar: ornekCevaplar ?? this.ornekCevaplar,
    );
  }
}

// Izgara oyunu. Kesişim'den farkı: tahminler sunucuda tutulduğu için yarıda bırakılan tahta
// tekrar açılınca kaldığı yerden devam eder; hak ve skor istemciden alınmaz.
class IzgaraNotifier extends Notifier<IzgaraState> {
  final IzgaraZorlugu zorluk;

  IzgaraNotifier(this.zorluk);

  late OyunDeposu _depo;

  @override
  IzgaraState build() {
    _depo = ref.read(oyunDeposuProvider);
    // Veriyi build bittikten sonra yüklüyoruz: build'in döndürdüğü başlangıç durumu sonucun üzerine yazmasın
    Future.microtask(_yukle);
    return const IzgaraState();
  }

  Future<void> _yukle() async {
    try {
      final kullaniciId = _depo.kullaniciId;
      if (kullaniciId == null) {
        state = state.copyWith(durum: IzgaraDurumu.hata, hataMesaji: oturumYokMesaji);
        return;
      }

      String tarih;
      try {
        tarih = await _depo.oyunTarihi();
      } catch (_) {
        tarih = bugununTarihi();
      }

      final oyun = await _depo.gununOyunu(zorluk.oyunTipi, tarih);
      final tahta = IzgaraTahtasi.oku(oyun?['soru_verisi']);
      if (!ref.mounted) return;
      if (oyun == null || tahta == null) {
        state = state.copyWith(durum: IzgaraDurumu.oyunYok);
        return;
      }
      final oyunId = oyun['id'] as String;

      // Kayıt yoksa oyun 'basladi' olarak açılır; varsa (devam eden ya da bitmiş) tahta tahminlerden kurulur
      var kayit = await _depo.oyunKaydi(kullaniciId, zorluk.oyunTipi, tarih);
      if (kayit == null) {
        try {
          await _depo.kayitAc(kullaniciId: kullaniciId, oyunId: oyunId, oyunTipi: zorluk.oyunTipi, tarih: tarih);
          kayit = {'durum': 'basladi'};
        } on KayitZatenVar {
          // Aynı anda başka bir cihazda açılmış: o kayıtla devam ediliyor
          kayit = await _depo.oyunKaydi(kullaniciId, zorluk.oyunTipi, tarih) ?? {'durum': 'basladi'};
        }
      }

      final tahminler = await _depo.izgaraTahminleri(oyunId);
      if (!ref.mounted) return;

      final bitti = kayit['durum'] == 'tamamlandi' || tahminler.length >= izgaraHakSayisi;
      state = state.copyWith(
        durum: bitti ? IzgaraDurumu.bitti : IzgaraDurumu.oynaniyor,
        tahta: tahta,
        oyunId: oyunId,
        hucreler: {
          for (final t in tahminler)
            if (t.hucre != null) t.hucre!: IzgaraOyuncusu(isim: t.oyuncuIsim, fotoUrl: t.fotoUrl),
        },
        kalanHak: (izgaraHakSayisi - tahminler.length).clamp(0, izgaraHakSayisi),
      );
      if (bitti) await _ornekCevaplariYukle();
    } catch (_) {
      if (!ref.mounted) return;
      state = state.copyWith(durum: IzgaraDurumu.hata, hataMesaji: yuklemeHataMesaji);
    }
  }

  Future<List<OyuncuOneri>> oyuncuAra(String metin) => _depo.oyuncuAra(metin);

  // Seçilen oyuncuyu sunucuya gönderir. Hata olursa mesajını döndürür, başarılıysa null.
  Future<String?> tahminEt(OyuncuOneri oyuncu) async {
    if (state.durum != IzgaraDurumu.oynaniyor || state.gonderiliyor) return null;
    state = state.copyWith(gonderiliyor: true);

    IzgaraTahminSonucu sonuc;
    try {
      sonuc = await _depo.izgaraTahmin(oyunId: state.oyunId!, oyuncuId: oyuncu.id);
    } catch (_) {
      if (!ref.mounted) return null;
      state = state.copyWith(gonderiliyor: false);
      return gonderimHataMesaji;
    }
    if (!ref.mounted) return null;

    final hucreler = {...state.hucreler};
    if (sonuc.dogru && sonuc.hucre != null) {
      hucreler[sonuc.hucre!] = IzgaraOyuncusu(isim: sonuc.oyuncuIsim, fotoUrl: sonuc.fotoUrl ?? oyuncu.fotoUrl);
    }

    state = state.copyWith(
      durum: sonuc.bitti ? IzgaraDurumu.bitti : IzgaraDurumu.oynaniyor,
      hucreler: hucreler,
      kalanHak: sonuc.kalanHak,
      sonTahmin: sonuc,
      gonderiliyor: false,
    );

    if (sonuc.bitti) await _ornekCevaplariYukle();
    return null;
  }

  // Oyunu o anki skorla bitirir
  Future<String?> pesEt() async {
    if (state.durum != IzgaraDurumu.oynaniyor || state.gonderiliyor) return null;
    state = state.copyWith(gonderiliyor: true);

    try {
      await _depo.izgaraPesEt(state.oyunId!);
    } catch (_) {
      if (!ref.mounted) return null;
      state = state.copyWith(gonderiliyor: false);
      return 'Bağlantı sorunu. İnternet bağlantını kontrol edip tekrar dene.';
    }
    if (!ref.mounted) return null;

    state = state.copyWith(durum: IzgaraDurumu.bitti, gonderiliyor: false);
    await _ornekCevaplariYukle();
    return null;
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

final izgaraProvider = NotifierProvider.autoDispose.family<IzgaraNotifier, IzgaraState, IzgaraZorlugu>(IzgaraNotifier.new);
