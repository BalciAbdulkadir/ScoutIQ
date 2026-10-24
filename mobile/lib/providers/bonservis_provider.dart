import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/bonservis_sorusu.dart';
import '../services/gunluk_oyun.dart';
import '../services/oyun_deposu.dart';

enum BonservisDurumu { yukleniyor, oynaniyor, bitti, zatenOynandi, yaridaBirakildi, oyunYok, hata }

const _ayni = Object();

class BonservisState {
  final BonservisDurumu durum;
  final List<BonservisSorusu> sorular;
  final int soruIndex;
  final int skor; // Doğru tahmin sayısı
  final List<bool> sonuclar; // Cevaplanan soruların doğru/yanlış sonucu, ilerleme çubuğu için
  final bool? sonCevapDogru; // Doluysa şu anki sorunun cevabı verildi ve sonuç gösteriliyor
  final bool gonderiliyor;
  final String? tarih;
  final String? hataMesaji;

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
    );
  }
}

// Bonservis oyunu: her soruda bir oyuncunun bedeli görünür, diğerininki için "daha fazla / daha az" tahmin edilir.
// Yanlış tahminde oyun biter.
class BonservisNotifier extends Notifier<BonservisState> {
  static const _oyunTipi = 'bonservis';

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
      final acilis = await gunlukOyunuAc(_depo, _oyunTipi);
      if (!ref.mounted) return;

      state = switch (acilis) {
        Oynanabilir(:final sorular, :final tarih) =>
          state.copyWith(durum: BonservisDurumu.oynaniyor, sorular: bonservisSorulariniOku(sorular), tarih: tarih),
        ZatenOynandi(:final skor) => state.copyWith(durum: BonservisDurumu.zatenOynandi, skor: skor),
        YaridaBirakildi(:final skor) => state.copyWith(durum: BonservisDurumu.yaridaBirakildi, skor: skor),
        OyunYok() => state.copyWith(durum: BonservisDurumu.oyunYok),
        OturumYok() => state.copyWith(durum: BonservisDurumu.hata, hataMesaji: oturumYokMesaji),
      };
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(durum: BonservisDurumu.hata, hataMesaji: yuklemeHataMesaji);
    }
  }

  // Rakibin bedeli için tahmin. Hata olursa mesajını döndürür, başarılıysa null.
  Future<String?> tahminEt({required bool dahaFazla}) async {
    final soru = state.soru;
    if (!state.tahminEdilebilir || soru == null) return null;

    final userId = _depo.kullaniciId;
    if (userId == null) return oturumYokMesaji;

    state = state.copyWith(gonderiliyor: true);

    final dogru = dahaFazla == soru.rakipDahaPahali;
    final yeniSkor = dogru ? state.skor + 1 : state.skor;
    final bitti = !dogru || state.sonSoru;

    try {
      // Skoru her tahminden sonra kaydediyoruz, oyun bittiyse kaydı kilitliyoruz
      final yazildi = await _depo.skorYaz(
        kullaniciId: userId,
        oyunTipi: _oyunTipi,
        tarih: state.tarih!,
        skor: yeniSkor,
        bitti: bitti,
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
    final dogru = state.sonCevapDogru;
    if (dogru == null) return;

    if (!dogru || state.sonSoru) {
      state = state.copyWith(durum: BonservisDurumu.bitti);
      return;
    }

    state = state.copyWith(soruIndex: state.soruIndex + 1, sonCevapDogru: null);
  }
}

final bonservisProvider = NotifierProvider.autoDispose<BonservisNotifier, BonservisState>(() {
  return BonservisNotifier();
});
