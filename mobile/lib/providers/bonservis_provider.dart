import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/bonservis_sorusu.dart';
import '../services/gunluk_oyun.dart';
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
class BonservisNotifier extends Notifier<BonservisState> {
  static const _oyunTipi = 'bonservis';
  static const puan = 2;

  final int? sure; // Yeni oyunda seçilen süre, saniye; null: süresiz. Yarım kalan oyunda sunucudaki süre geçerlidir.

  BonservisNotifier(this.sure);

  late OyunDeposu _depo;

  @override
  BonservisState build() {
    _depo = ref.read(oyunDeposuProvider);
    // Veriyi build bittikten sonra yüklüyoruz, build'in başlangıç durumu sonucun üzerine yazmasın
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
      };
      if (acilis is Oynanabilir) {
        // Oyun kapalıyken süre dolmuşsa ya da bütün sorular cevaplanmış ama kayıt kapanmamışsa oyun bitirilir
        final sureDoldu = acilis.kalanSaniye != null && acilis.kalanSaniye! <= 0;
        if (sureDoldu || state.sonuclar.length >= state.sorular.length) await _kapat(sureDoldu: sureDoldu);
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

  // Rakibin bedeli için tahmin. Hata olursa mesajını döndürür, başarılıysa null.
  Future<String?> tahminEt({required bool dahaFazla}) async {
    final soru = state.soru;
    if (!state.tahminEdilebilir || soru == null) return null;

    final userId = _depo.kullaniciId;
    if (userId == null) return oturumYokMesaji;

    state = state.copyWith(gonderiliyor: true);

    final dogru = dahaFazla == soru.rakipDahaPahali;
    final yeniSkor = dogru ? state.skor + puan : state.skor;
    final bitti = state.sonSoru;

    try {
      // Skoru her tahminden sonra kaydediyoruz, oyun bittiyse kaydı kilitliyoruz
      final yazildi = await _depo.skorYaz(
        kullaniciId: userId,
        oyunTipi: _oyunTipi,
        tarih: state.tarih!,
        skor: yeniSkor,
        bitti: bitti,
        ilerleme: _ilerleme([...state.sonuclar, dogru]),
      );
      if (!ref.mounted) return null;

      if (!yazildi) {
        // Kayıt başka bir yerden kapatılmış: oyun artık oynanamaz
        state = state.copyWith(durum: BonservisDurumu.zatenOynandi, gonderiliyor: false);
        return null;
      }

      state = state.copyWith(
        skor: yeniSkor,
        sonuclar: [...state.sonuclar, dogru],
        sonCevapDogru: dogru,
        gonderiliyor: false,
      );
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

  // Sunucuya yazılan ilerleme: cevaplanan her soru için doğru mu
  static List<Map<String, dynamic>> _ilerleme(List<bool> sonuclar) => [
        for (final dogru in sonuclar) {'dogru': dogru},
      ];

  // Kaydı o anki skorla kilitler ve bitiş ekranını açar
  Future<void> _kapat({required bool sureDoldu}) async {
    final userId = _depo.kullaniciId;
    state = state.copyWith(gonderiliyor: true);

    if (userId != null) {
      try {
        // Son sorunun cevabı verildiyse kayıt zaten kilitlidir, yazılmaz; sorun değil
        await _depo.skorYaz(
          kullaniciId: userId,
          oyunTipi: _oyunTipi,
          tarih: state.tarih!,
          skor: state.skor,
          bitti: true,
          ilerleme: _ilerleme(state.sonuclar),
        );
      } catch (_) {
        // Kayıt kapatılamazsa açık kalır; süre sunucuda da dolduğu için skor sonradan değiştirilemez
      }
    }
    if (!ref.mounted) return;

    state = state.copyWith(durum: BonservisDurumu.bitti, sureDoldu: sureDoldu);
  }
}

// Parametre seçilen süredir (saniye); null: süresiz
final bonservisProvider =
    NotifierProvider.autoDispose.family<BonservisNotifier, BonservisState, int?>(BonservisNotifier.new);
