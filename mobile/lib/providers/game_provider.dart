import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/oyuncu_oneri.dart';
import '../services/gunluk_oyun.dart';
import '../services/analitik.dart';
import '../services/hata_kaydi.dart';
import 'puan_provider.dart';
import '../services/oyun_sonu.dart';
import '../services/oyun_deposu.dart';

class GameState {
  final String status; // 'loading', 'playing', 'completed', 'already_played', 'no_game', 'error'
  final List<dynamic> questions; // Gelen sorular: cevaplananlar + sıradaki; oyun bitince hepsi (040_oyun_ac.sql)
  final int soruSayisi; // Toplam soru sayısı (ilerleme çubuğu ve özet için)
  final int currentIndex;
  final int score;
  final String? lastGuessStatus;
  final String? gameId; // Oynanan oyunun Supabase ID'si
  final String? tarih; // Oyun günü (Türkiye saatine göre), kayıtlar bu tarihle atılır
  final bool gonderiliyor; // Cevap sunucuda kontrol edilirken ikinci gönderimi engeller
  final String? hataMesaji; // status 'error' iken gösterilir
  final List<bool> sonuclar; // Cevaplanan soruların doğru/yanlış sonucu (ilerleme çubuğu ve özet için)
  final List<String> cevaplar; // Cevaplanan sorularda seçilen oyuncular (özet için)
  final Map<int, String> ornekCevaplar; // Oyun bitince sunucudan gelen örnek doğru cevaplar: soru index'i -> oyuncu
  final DateTime? bitisZamani; // Süreli oyunda sürenin dolacağı an; süresizse null
  final bool sureDoldu; // Oyun süre dolduğu için bitti

  GameState({
    this.sonuclar = const [],
    this.cevaplar = const [],
    this.ornekCevaplar = const {},
    this.status = 'loading',
    this.questions = const [],
    this.soruSayisi = 5,
    this.currentIndex = 0,
    this.score = 0,
    this.lastGuessStatus,
    this.gameId,
    this.tarih,
    this.gonderiliyor = false,
    this.hataMesaji,
    this.bitisZamani,
    this.sureDoldu = false,
  });

  GameState copyWith({
    String? status,
    List<dynamic>? questions,
    int? soruSayisi,
    int? currentIndex,
    int? score,
    String? lastGuessStatus,
    String? gameId,
    String? tarih,
    bool? gonderiliyor,
    String? hataMesaji,
    List<bool>? sonuclar,
    List<String>? cevaplar,
    Map<int, String>? ornekCevaplar,
    DateTime? bitisZamani,
    bool? sureDoldu,
  }) {
    return GameState(
      sonuclar: sonuclar ?? this.sonuclar,
      cevaplar: cevaplar ?? this.cevaplar,
      ornekCevaplar: ornekCevaplar ?? this.ornekCevaplar,
      status: status ?? this.status,
      questions: questions ?? this.questions,
      soruSayisi: soruSayisi ?? this.soruSayisi,
      currentIndex: currentIndex ?? this.currentIndex,
      score: score ?? this.score,
      lastGuessStatus: lastGuessStatus ?? this.lastGuessStatus,
      gameId: gameId ?? this.gameId,
      tarih: tarih ?? this.tarih,
      gonderiliyor: gonderiliyor ?? this.gonderiliyor,
      hataMesaji: hataMesaji ?? this.hataMesaji,
      bitisZamani: bitisZamani ?? this.bitisZamani,
      sureDoldu: sureDoldu ?? this.sureDoldu,
    );
  }
}

// Kesişim oyunu. Her zorluk ayrı bir günlük oyundur: kesisim_kolay, kesisim_orta ya da kesisim_zor.
// Cevap sunucuda kontrol edilir; skor (doğru cevap 2 puan) ve ilerleme sunucuda yazılır (034_skor_sunucuda.sql).
// Süre seçildiyse (40, 60 ya da 90 saniye) bütün sorular içindir; dolunca oyun o anki skorla biter.
// Oyundan çıkınca oyun bitmez: süre sunucuda işlemeye devam eder, oyun tekrar açılınca kaldığı sorudan sürer.
class GameNotifier extends Notifier<GameState> {
  final GunlukOyunSecimi secim;

  GameNotifier(this.secim);

  String get _oyunTipi => secim.oyunTipi;

  // Yeni oyunda seçilen süre, saniye; null: süresiz. Yarım kalan oyunda sunucudaki süre geçerlidir.
  int? get sure => secim.sure;

  late OyunDeposu _depo;

  // Açılışta ya da hamlede gelen beklenmeyen hata Crashlytics'e gider (services/hata_kaydi.dart); kullanıcıya
  // gösterilen mesaj değişmez. build'de alınır: hata geldiğinde ekran kapanmış olabilir.
  late HataKaydi _hatalar;

  void _hataKaydet(Object hata, StackTrace iz, OyunIslemi islem) =>
      _hatalar.oyunHatasi(hata, iz, islem: islem, oyunTipi: secim.oyunTipi, sure: secim.sure);

  // Analitik olaylar (services/analitik.dart): başladı, bitti, yarıda bırakıldı
  late OyunOlaylari _olaylar;
  bool _oynaniyor = false;

  void _olaylariDinle() {
    _olaylar = OyunOlaylari(ref.read(analitikProvider), secim.oyunTipi);
    // Puan bitiş ekranıyla paylaşılır; ekran açık kaldıkça canlı tutulur
    final puan = oyunPuaniProvider(_olaylar.gunlukOyunTipi);
    ref.listen(puan, (_, _) {});
    listenSelf((onceki, simdiki) {
      _oynaniyor = simdiki.status == 'playing';
      // Oynanırken bitti (bitmiş oyunu açmak sayılmaz)
      if (onceki != null && onceki.status == 'playing' && simdiki.status == 'completed') {
        final sebep = simdiki.sureDoldu ? BitisSebebi.sureDoldu : BitisSebebi.tamamlandi;
        // oyun_bitti puan sunucudan okununca gider (puansız oyunda puan parametresi yok)
        ref.read(puan.notifier).yukle().then((p) => _olaylar.bitti(skor: simdiki.score, sebep: sebep, puan: p?.puan));
        ref.read(oyunSonuProvider).oyunBitti(gunlukOyunTipi: _olaylar.gunlukOyunTipi, skor: simdiki.score);
      }
      // Bitmiş oyun açıldıysa da puanı gösterilir
      const bitmis = {'completed', 'already_played'};
      if (bitmis.contains(simdiki.status) && !bitmis.contains(onceki?.status)) {
        ref.read(puan.notifier).yukle();
      }
    });
    ref.onDispose(() {
      if (_oynaniyor) _olaylar.yaridaBirakildi();
    });
  }

  @override
  GameState build() {
    _depo = ref.read(oyunDeposuProvider);
    _hatalar = ref.read(hataKaydiProvider);
    // Veriyi build bittikten sonra yüklüyoruz: _initGame state'i hemen değiştirirse (örneğin oturum yoksa)
    // build'in döndürdüğü başlangıç durumu o değişikliğin üzerine yazmasın
    _olaylariDinle();
    Future.microtask(_initGame);
    return GameState();
  }

  Future<void> _initGame() async {
    try {
      final acilis = await gunlukOyunuAc(_depo, _oyunTipi, sure: sure);
      if (!ref.mounted) return;

      state = switch (acilis) {
        Oynanabilir(
          :final oyunId,
          :final sorular,
          :final soruSayisi,
          :final tarih,
          :final skor,
          :final ilerleme,
          :final kalanSaniye
        ) =>
          state.copyWith(
            status: 'playing',
            questions: sorular,
            soruSayisi: soruSayisi,
            gameId: oyunId,
            tarih: tarih,
            // Yarım kalan oyun kaldığı sorudan devam eder
            currentIndex: ilerleme.length.clamp(0, sorular.length - 1),
            score: skor,
            sonuclar: [for (final c in ilerleme) c['dogru'] == true],
            cevaplar: [for (final c in ilerleme) c['cevap'] as String? ?? '—'],
            bitisZamani: kalanSaniye == null ? null : DateTime.now().add(Duration(seconds: kalanSaniye)),
          ),
        ZatenOynandi(:final skor, :final ilerleme) => state.copyWith(
            status: 'already_played', score: skor, sonuclar: [for (final c in ilerleme) c['dogru'] == true]),
        OyunYok() => state.copyWith(status: 'no_game'),
        OturumYok() => state.copyWith(status: 'error', hataMesaji: oturumYokMesaji),
        BaskaZorlukOynandi() => state.copyWith(status: 'error', hataMesaji: baskaZorlukMesaji),
      };
      if (acilis is Oynanabilir) {
        if (acilis.yeni) _olaylar.basladi(sure: sure);
        // Oyun kapalıyken süre dolmuşsa ya da bütün sorular cevaplanmış ama kayıt kapanmamışsa oyun bitirilir
        final sureDoldu = acilis.kalanSaniye != null && acilis.kalanSaniye! <= 0;
        if (sureDoldu || state.sonuclar.length >= state.soruSayisi) {
          await _kapat(sureDoldu: sureDoldu);
          return;
        }
        await _eksikLogolariTamamla();
      }
    } catch (e, iz) {
      _hataKaydet(e, iz, OyunIslemi.acilis);
      if (!ref.mounted) return;
      state = state.copyWith(status: 'error', hataMesaji: yuklemeHataMesaji);
    }
  }

  // Logolar eklenmeden önce üretilmiş sorularda kulüp logosu yoktur: kulüp ID'sinden tamamlanır.
  // Logolar süstür; gelmezse kalkan ikonu kalır, hata kullanıcıya yansıtılmaz.
  Future<void> _eksikLogolariTamamla() async {
    final sorular = state.questions.whereType<Map<String, dynamic>>().toList();
    final eksikIdler = {
      for (final soru in sorular)
        for (final taraf in ['a', 'b'])
          if (soru['kulup_${taraf}_logo'] == null && soru['kulup_${taraf}_id'] is String) soru['kulup_${taraf}_id'] as String,
    };
    if (eksikIdler.isEmpty) return;

    try {
      final logolar = await _depo.kulupLogolari(eksikIdler.toList());
      if (!ref.mounted || logolar.isEmpty) return;
      state = state.copyWith(questions: [
        for (final soru in state.questions)
          if (soru is Map<String, dynamic>)
            {
              ...soru,
              'kulup_a_logo': soru['kulup_a_logo'] ?? logolar[soru['kulup_a_id']],
              'kulup_b_logo': soru['kulup_b_logo'] ?? logolar[soru['kulup_b_id']],
            }
          else
            soru,
      ]);
    } catch (_) {}
  }

  // Cevap kutusunun altındaki öneri listesi. Tüm oyuncular arasında arar, doğru cevabı ele vermez.
  Future<List<OyuncuOneri>> oyuncuAra(String metin) => _depo.oyuncuAra(metin);

  // Seçilen oyuncuyu sunucuya gönderir; sunucu cevabı kontrol edip skoru yazar.
  // Hata olursa mesajını döndürür, başarılıysa null.
  Future<String?> makeGuess(OyuncuOneri oyuncu) async {
    if (state.status != 'playing' || state.questions.isEmpty || state.gonderiliyor) return null;
    if (_depo.kullaniciId == null) return oturumYokMesaji;

    state = state.copyWith(gonderiliyor: true);

    try {
      final sonuc = await _depo.kesisimCevap(
        oyunId: state.gameId!,
        soruIndex: state.currentIndex,
        oyuncuId: oyuncu.id,
      );
      if (!ref.mounted) return null;

      if (sonuc.sureDoldu) {
        // Süre sunucuda dolmuştu: cevap sayılmadı, oyun o anki skorla bitti
        state = state.copyWith(status: 'completed', sureDoldu: true, score: sonuc.skor, gonderiliyor: true);
      } else {
        final siradaki = sonuc.siradakiSoru;
        // Sıradaki soru cevabın içinde gelir; gelmediyse oyun devam edemez
        final bitti = sonuc.bitti || state.currentIndex + 1 >= state.soruSayisi || siradaki == null;
        state = state.copyWith(
          status: bitti ? 'completed' : 'playing',
          questions: bitti ? null : [...state.questions, siradaki],
          currentIndex: bitti ? state.currentIndex : state.currentIndex + 1,
          score: sonuc.skor,
          lastGuessStatus: sonuc.dogru ? 'correct' : 'wrong',
          sonuclar: [...state.sonuclar, sonuc.dogru],
          cevaplar: [...state.cevaplar, oyuncu.isim],
          // Oyun bittiyse kilit açılmıyor: son soruda ikinci gönderim mümkün olmasın
          gonderiliyor: bitti,
        );
      }
    } on OyunAcikDegil {
      // Kayıt başka bir yerden kapatılmış: oyun artık oynanamaz
      if (!ref.mounted) return null;
      state = state.copyWith(status: 'already_played', gonderiliyor: false);
      return null;
    } catch (e, iz) {
      _hataKaydet(e, iz, OyunIslemi.hamle);
      if (!ref.mounted) return null;
      state = state.copyWith(gonderiliyor: false);
      return gonderimHataMesaji;
    }

    // Bitiş ekranı açıldı; yanlış cevap varsa özette gösterilecek doğru cevapları getiriyoruz
    if (state.status == 'completed') await _bitisOzetiniYukle();
    return null;
  }

  // Ekrandaki sayaç sıfıra inince çağrılır: oyun o anki skorla biter, cevaplanmayan sorular boş kalır.
  // Cevap gönderilirken çağrılırsa yok sayılır; sayaç sıfırda kaldıkça tekrar çağırır.
  Future<void> sureDoldu() async {
    if (state.status != 'playing' || state.gonderiliyor) return;
    await _kapat(sureDoldu: true);
  }

  // Kaydı o anki skorla kapatır (skor sunucuda kalır) ve bitiş ekranını açar
  Future<void> _kapat({required bool sureDoldu}) async {
    state = state.copyWith(gonderiliyor: true);

    if (_depo.kullaniciId != null) {
      try {
        await _depo.oyunuBitir(state.gameId!);
      } catch (_) {
        // Kayıt kapatılamazsa açık kalır; süre sunucuda da dolduğu için sonradan cevap kabul edilmez
      }
    }
    if (!ref.mounted) return;

    state = state.copyWith(status: 'completed', sureDoldu: sureDoldu);
    await _bitisOzetiniYukle();
  }

  // Bitiş özeti: süre dolduysa gelmemiş sorular da gösterilir (bitmiş oyunda sunucu bütün soruları döndürür),
  // yanlış ya da boş kalan sorular için örnek doğru cevaplar. İkisi de ek bilgidir, gelmezse özet yine gösterilir.
  Future<void> _bitisOzetiniYukle() async {
    if (state.questions.length < state.soruSayisi) {
      final sorular = await bitmisOyununSorulari(_depo, state.gameId!);
      if (!ref.mounted) return;
      if (sorular != null && sorular.length >= state.questions.length) state = state.copyWith(questions: sorular);
    }
    await _ornekCevaplariYukle();
  }

  // Örnek doğru cevaplar özete ek bilgidir: gelmezse özet yine gösterilir, hata kullanıcıya yansıtılmaz.
  // Sadece yanlış ya da cevaplanmamış soru varsa gerekir.
  Future<void> _ornekCevaplariYukle() async {
    if (state.sonuclar.length >= state.soruSayisi && !state.sonuclar.contains(false)) return;
    try {
      final ornekler = await _depo.kesisimOrnekCevaplar(state.gameId!);
      if (!ref.mounted) return;
      state = state.copyWith(ornekCevaplar: ornekler);
    } catch (_) {}
  }
}

// Parametre: zorluğun oyun tipi (ör. kesisim_orta) ve seçilen süre
final gameProvider = NotifierProvider.autoDispose.family<GameNotifier, GameState, GunlukOyunSecimi>(GameNotifier.new);
