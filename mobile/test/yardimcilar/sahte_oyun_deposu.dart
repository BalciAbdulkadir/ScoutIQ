import 'dart:async';

import 'package:mobile/models/bingo.dart';
import 'package:mobile/models/izgara.dart';
import 'package:mobile/models/oyuncu_oneri.dart';
import 'package:mobile/services/oyun_deposu.dart';

// Testler için bellekte çalışan depo. Supabase'e bağlanmaz, yapılan çağrıları kaydeder.
class SahteOyunDeposu implements OyunDeposu {
  @override
  String? kullaniciId = 'kullanici-1';

  String tarih = '2026-10-23';
  bool tarihHataVerir = false;
  bool oyunYuklemeHataVerir = false;

  // Kullanıcının o günkü kaydı: {'skor': int, 'durum': String}
  Map<String, dynamic>? kayit;
  // Kayıttaki ilerleme (cevaplanan sorular). oyunKaydi kayda ekleyerek döndürür.
  List<Map<String, dynamic>> ilerleme = [];

  // Kesişim/Bonservis süresi: başlatılan toplam süre ve sunucuya göre kalan süre (saniye). null: süresiz.
  int? oyunSureToplam;
  int? oyunSureKalan;
  final List<int?> oyunSureIstekleri = [];
  bool oyunSureHataVerir = false;

  // kayitAc çağrıldığında başka bir cihazın kaydı atmış gibi davranılsın mı
  bool kayitAcCakisir = false;

  // kayitAc çağrıldığında kullanıcı bu oyunu bugün başka bir zorlukta oynamış gibi davranılsın mı
  bool baskaModOynandi = false;

  Map<String, dynamic>? oyun = {
    'id': 'oyun-1',
    'soru_verisi': [
      for (var i = 0; i < 5; i++)
        {'kulup_a': 'Kulüp A$i', 'kulup_b': 'Kulüp B$i', 'zorluk': i < 2 ? 'kolay' : (i < 4 ? 'orta' : 'zor')},
    ],
  };

  List<OyuncuOneri> oneriler = const [
    OyuncuOneri(id: 'o-1', isim: 'Arda Güler'),
    OyuncuOneri(id: 'o-2', isim: 'Mesut Özil'),
  ];

  // Doğru kabul edilecek oyuncu ID'leri
  Set<String> dogruCevaplar = {'o-1'};
  bool cevapKontrolHataVerir = false;

  // Doluysa cevap kontrolü bu Completer tamamlanana kadar bekler (çift gönderim testleri için)
  Completer<void>? cevapKontrolBekletici;

  // Oyun bitince sunucunun döndüreceği örnek doğru cevaplar: soru index'i -> oyuncu
  Map<int, String> ornekCevaplar = {
    for (var i = 0; i < 5; i++) i: 'Doğru Oyuncu $i',
  };
  bool ornekCevaplarHataVerir = false;
  int ornekCevaplarSayisi = 0;

  // Doluysa skor yazımı bu Completer tamamlanana kadar bekler
  Completer<void>? skorYazBekletici;
  bool skorYazHataVerir = false;

  // Izgara: oyuncu ID'si -> yerleşeceği hücre. Listede olmayan oyuncu yanlış sayılır.
  Map<String, int> izgaraHucreleri = {'o-1': 4};
  // Sunucudaki tahminler (uygulama yeniden açılınca okunur)
  List<IzgaraTahmini> izgaraTahminListesi = [];
  bool izgaraTahminHataVerir = false;
  int izgaraPesSayisi = 0;
  Map<int, IzgaraOyuncusu> izgaraOrnekleri = {
    for (var i = 0; i < 9; i++) i: IzgaraOyuncusu(isim: 'Örnek Oyuncu $i', fotoUrl: 'https://foto.test/$i.jpg'),
  };

  // Izgara süresi: başlatılan toplam süre ve sunucuya göre kalan süre (saniye). null: süresiz.
  int? izgaraSureToplam;
  int? izgaraSureKalan;
  final List<int?> sureBaslatmaIstekleri = [];
  // Doluysa sunucu süre dolmuş gibi tahmini reddeder
  bool izgaraSuresiDoldu = false;
  bool izgaraSureHataVerir = false;

  // Kulüp ID'si -> logo (Kesişim'de logosu olmayan eski sorular için)
  Map<String, String> logolar = {};
  int logoIstekSayisi = 0;

  // Bingo: destedeki sıra (1'den) -> oyuncunun uyduğu kutular. Listede olmayan oyuncu hiçbir kutuya uymaz.
  Map<int, List<int>> bingoEslesmeleri = {1: [0], 2: [5, 6]};
  int bingoDesteBoyutu = 16;
  // Sunucunun hamleden sonra bildirdiği sıradaki oyuncu: false ise eski sunucu gibi göndermez, uygulama kendisi bulur
  bool bingoSiradakiGonderir = true;
  int bingoKutuSayisi = 12;
  // Sunucudaki hamleler (uygulama yeniden açılınca okunur)
  List<BingoHamlesi> bingoHamleListesi = [];
  bool bingoHamleHataVerir = false;
  // Doluysa sunucu süre dolmuş gibi hamleyi reddeder
  bool bingoSuresiDoldu = false;
  int bingoPesSayisi = 0;
  final List<({int sira, int? hucre})> bingoHamleIstekleri = [];
  Map<int, BingoOyuncusu> bingoOrnekleri = {
    for (var i = 0; i < 12; i++) i: BingoOyuncusu(isim: 'Örnek Oyuncu $i'),
  };

  // Çağrı kayıtları
  int kayitAcSayisi = 0;
  int cevapKontrolSayisi = 0;
  final List<String> arananlar = [];
  final List<({int skor, bool bitti})> yazilanSkorlar = [];
  final List<String> istenenOyunTipleri = []; // gununOyunu ile istenen oyun tipleri
  final List<String> acilanKayitTipleri = []; // kayitAc ile açılan oyun tipleri

  @override
  Future<String> oyunTarihi() async {
    if (tarihHataVerir) throw Exception('bağlantı yok');
    return tarih;
  }

  @override
  Future<Map<String, dynamic>?> oyunKaydi(String kullaniciId, String oyunTipi, String tarih) async =>
      kayit == null ? null : {...kayit!, 'ilerleme': ilerleme};

  @override
  Future<OyunSuresiDurumu?> oyunSureyiBaslat(String oyunTipi, String tarih, {int? sure}) async {
    oyunSureIstekleri.add(sure);
    if (oyunSureHataVerir) throw Exception('bağlantı yok');
    // Gerçek sunucu gibi: süre sadece açık ve süresi olmayan kayda bir kez verilir
    if (sure != null && kayit?['durum'] == 'basladi' && oyunSureToplam == null) {
      oyunSureToplam = sure;
      oyunSureKalan = sure;
    }
    final toplam = oyunSureToplam;
    return toplam == null ? null : OyunSuresiDurumu(toplam: toplam, kalan: oyunSureKalan ?? toplam);
  }

  @override
  Future<Map<String, dynamic>?> gununOyunu(String oyunTipi, String tarih) async {
    istenenOyunTipleri.add(oyunTipi);
    if (oyunYuklemeHataVerir) throw Exception('bağlantı yok');
    return oyun;
  }

  @override
  Future<void> kayitAc({required String kullaniciId, required String oyunId, required String oyunTipi, required String tarih}) async {
    kayitAcSayisi++;
    acilanKayitTipleri.add(oyunTipi);
    if (baskaModOynandi) throw BaskaModOynandi();
    if (kayitAcCakisir) {
      kayit = {'skor': 4, 'durum': 'basladi'};
      throw KayitZatenVar();
    }
    kayit = {'skor': 0, 'durum': 'basladi'};
  }

  @override
  Future<List<OyuncuOneri>> oyuncuAra(String metin) async {
    arananlar.add(metin);
    return oneriler;
  }

  @override
  Future<bool> kesisimCevapKontrol({required String oyunId, required int soruIndex, required String oyuncuId}) async {
    cevapKontrolSayisi++;
    if (cevapKontrolBekletici != null) await cevapKontrolBekletici!.future;
    if (cevapKontrolHataVerir) throw Exception('bağlantı yok');
    return dogruCevaplar.contains(oyuncuId);
  }

  @override
  Future<Map<int, String>> kesisimOrnekCevaplar(String oyunId) async {
    ornekCevaplarSayisi++;
    if (ornekCevaplarHataVerir) throw Exception('bağlantı yok');
    // Gerçek sunucu gibi: oyun bitmeden cevap vermez
    if (kayit?['durum'] != 'tamamlandi') return {};
    return ornekCevaplar;
  }

  @override
  Future<bool> skorYaz({
    required String kullaniciId,
    required String oyunTipi,
    required String tarih,
    required int skor,
    required bool bitti,
    List<Map<String, dynamic>>? ilerleme,
  }) async {
    if (skorYazBekletici != null) await skorYazBekletici!.future;
    if (skorYazHataVerir) throw Exception('bağlantı yok');
    if (kayit?['durum'] != 'basladi') return false;
    yazilanSkorlar.add((skor: skor, bitti: bitti));
    kayit = {'skor': skor, 'durum': bitti ? 'tamamlandi' : 'basladi'};
    if (ilerleme != null) this.ilerleme = ilerleme;
    return true;
  }

  @override
  Future<List<IzgaraTahmini>> izgaraTahminleri(String oyunId) async => izgaraTahminListesi;

  @override
  Future<IzgaraTahminSonucu> izgaraTahmin({required String oyunId, required String oyuncuId}) async {
    if (izgaraTahminHataVerir) throw Exception('bağlantı yok');
    final isim = oneriler.firstWhere((o) => o.id == oyuncuId).isim;
    final dolu = izgaraTahminListesi.where((t) => t.hucre != null).length;

    if (izgaraSuresiDoldu) {
      kayit = {'skor': dolu, 'durum': 'tamamlandi'};
      return IzgaraTahminSonucu(
          dogru: false, sureDoldu: true, oyuncuIsim: isim, skor: dolu, bitti: true);
    }

    if (izgaraTahminListesi.any((t) => t.oyuncuIsim == isim)) {
      return IzgaraTahminSonucu(
        dogru: false, tekrar: true, oyuncuIsim: isim, skor: dolu, bitti: false);
    }

    final hucre = izgaraHucreleri[oyuncuId];
    final bos = hucre != null && !izgaraTahminListesi.any((t) => t.hucre == hucre);
    izgaraTahminListesi = [
      ...izgaraTahminListesi,
      IzgaraTahmini(sira: izgaraTahminListesi.length + 1, oyuncuIsim: isim, hucre: bos ? hucre : null),
    ];
    final skor = dolu + (bos ? 1 : 0);
    // Tahmin hakkı sınırı yoktur: oyun sadece dokuz kutu dolunca biter
    final bitti = skor == 9;
    kayit = {'skor': skor, 'durum': bitti ? 'tamamlandi' : 'basladi'};
    return IzgaraTahminSonucu(
        dogru: bos, hucre: bos ? hucre : null, oyuncuIsim: isim, skor: skor, bitti: bitti);
  }

  @override
  Future<OyunSuresiDurumu?> izgaraSureyiBaslat(String oyunId, {int? sure}) async {
    sureBaslatmaIstekleri.add(sure);
    if (izgaraSureHataVerir) throw Exception('fonksiyon yok');
    // Süre bir kez başlatılır, sonradan değiştirilemez
    if (sure != null && izgaraSureToplam == null) {
      izgaraSureToplam = sure;
      izgaraSureKalan = sure;
    }
    if (izgaraSureToplam == null) return null;
    return OyunSuresiDurumu(toplam: izgaraSureToplam!, kalan: izgaraSureKalan!);
  }

  @override
  Future<int> izgaraPesEt(String oyunId) async {
    izgaraPesSayisi++;
    final skor = izgaraTahminListesi.where((t) => t.hucre != null).length;
    kayit = {'skor': skor, 'durum': 'tamamlandi'};
    return skor;
  }

  @override
  Future<Map<int, IzgaraOyuncusu>> izgaraOrnekCevaplar(String oyunId) async {
    if (kayit?['durum'] != 'tamamlandi') return {};
    return izgaraOrnekleri;
  }

  @override
  Future<Map<String, String>> kulupLogolari(List<String> kulupIdleri) async {
    logoIstekSayisi++;
    return {for (final id in kulupIdleri) if (logolar[id] != null) id: logolar[id]!};
  }

  int get _bingoSkoru => bingoHamleListesi.where((h) => h.dogru).length;

  @override
  Future<List<BingoHamlesi>> bingoHamleleri(String oyunId) async => List.of(bingoHamleListesi);

  Set<int> get _bingoYerlesenler => {for (final h in bingoHamleListesi) if (h.dogru) h.oyuncu};

  int? get _bingoSiradaki => bingoSiradaki(
        desteBoyutu: bingoDesteBoyutu,
        yerlesenler: _bingoYerlesenler,
        son: bingoHamleListesi.isEmpty ? 0 : bingoHamleListesi.last.oyuncu,
      );

  // 023_bingo_sinirsiz_pas.sql'deki bingo_hamle fonksiyonunun basit bir kopyası: destede sıra döner, yanlış kutu
  // kaydedilmez. Kalan oyuncuların hiçbiri boş kutulara uymuyorsa oyun biter.
  @override
  Future<BingoHamleSonucu> bingoHamle({required String oyunId, required int sira, int? hucre}) async {
    bingoHamleIstekleri.add((sira: sira, hucre: hucre));
    if (bingoHamleHataVerir) throw Exception('bağlantı yok');
    if (bingoSuresiDoldu) {
      kayit = {...?kayit, 'skor': _bingoSkoru, 'durum': 'tamamlandi'};
      return BingoHamleSonucu(dogru: false, skor: _bingoSkoru, bitti: true, sureDoldu: true);
    }
    if (sira != bingoHamleListesi.length + 1) throw Exception('Sıra hatalı');
    final oyuncu = _bingoSiradaki!;
    final dogru = hucre != null && (bingoEslesmeleri[oyuncu] ?? const []).contains(hucre);
    if (hucre != null && !dogru) {
      return BingoHamleSonucu(dogru: false, hucre: hucre, skor: _bingoSkoru, bitti: false, siradaki: oyuncu);
    }
    bingoHamleListesi.add(BingoHamlesi(sira: sira, oyuncu: oyuncu, hucre: hucre, dogru: dogru));

    final dolular = {for (final h in bingoHamleListesi) if (h.dogru) h.hucre};
    final yerlesenler = _bingoYerlesenler;
    final uyanVar = [
      for (var o = 1; o <= bingoDesteBoyutu; o++)
        if (!yerlesenler.contains(o)) ...(bingoEslesmeleri[o] ?? const <int>[]),
    ].any((h) => !dolular.contains(h));
    final bitti = _bingoSkoru == bingoKutuSayisi || !uyanVar;
    kayit = {...?kayit, 'skor': _bingoSkoru, 'durum': bitti ? 'tamamlandi' : 'basladi'};
    return BingoHamleSonucu(
      dogru: dogru,
      hucre: hucre,
      skor: _bingoSkoru,
      bitti: bitti,
      siradaki: bitti || !bingoSiradakiGonderir ? null : _bingoSiradaki,
    );
  }

  @override
  Future<int> bingoPesEt(String oyunId) async {
    bingoPesSayisi++;
    kayit = {...?kayit, 'skor': _bingoSkoru, 'durum': 'tamamlandi'};
    return _bingoSkoru;
  }

  @override
  Future<Map<int, BingoOyuncusu>> bingoOrnekCevaplar(String oyunId) async {
    if (kayit?['durum'] != 'tamamlandi') return {};
    final dolular = bingoHamleListesi.where((h) => h.dogru).map((h) => h.hucre).toSet();
    return {for (final e in bingoOrnekleri.entries) if (!dolular.contains(e.key)) e.key: e.value};
  }
}
