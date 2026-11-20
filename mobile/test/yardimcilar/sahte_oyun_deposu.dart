import 'dart:async';

import 'package:mobile/models/bingo.dart';
import 'package:mobile/models/bonservis_sorusu.dart';
import 'package:mobile/models/kesisim.dart';
import 'package:mobile/models/izgara.dart';
import 'package:mobile/models/oyuncu_oneri.dart';
import 'package:mobile/models/top10.dart';
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

  // Doluysa sunucunun skoru yazması (Kesişim cevabı, Bonservis tahmini, oyunu bitirme) bu Completer tamamlanana kadar bekler
  Completer<void>? skorYazBekletici;
  bool skorYazHataVerir = false;
  // Bonservis: sunucunun bonservisBedelleri ile döndürdüğü bedeller sorulsun mu
  int bonservisBedelIstekSayisi = 0;
  int oyunuBitirSayisi = 0;

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

  // Top 10: listedeki oyuncular, sıra -> (oyuncu ID'si, oyuncu). Listede olmayan oyuncu yanlış sayılır.
  Map<int, (String, Top10Oyuncusu)> top10Listesi = {
    3: ('o-1', const Top10Oyuncusu(isim: 'Arda Güler', deger: '30 M€')),
    for (var i = 1; i <= 10; i++)
      if (i != 3) i: ('liste-$i', Top10Oyuncusu(isim: 'Liste Oyuncusu $i', deger: '${20 - i} M€')),
  };
  // Sunucudaki tahminler (uygulama yeniden açılınca okunur)
  List<Top10Tahmini> top10TahminListesi = [];
  bool top10TahminHataVerir = false;
  int top10PesSayisi = 0;

  // Çağrı kayıtları
  int kayitAcSayisi = 0;
  int cevapKontrolSayisi = 0;
  final List<String> arananlar = [];
  // Sunucunun yazdığı skorlar (034_skor_sunucuda.sql: skor artık sadece sunucuda yazılır)
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

  // Sunucunun açık kaydı alması: kayıt yoksa ya da kapalıysa OyunAcikDegil; süre dolduysa kaydı kapatır (acik_kaydi_al)
  bool _sureDolduysaKapat() {
    if (kayit?['durum'] != 'basladi') throw OyunAcikDegil();
    if (oyunSureKalan != null && oyunSureKalan! <= 0) {
      kayit = {...kayit!, 'durum': 'tamamlandi'};
      return true;
    }
    return false;
  }

  void _skoruYaz(int skor, bool bitti) {
    yazilanSkorlar.add((skor: skor, bitti: bitti));
    kayit = {'skor': skor, 'durum': bitti ? 'tamamlandi' : 'basladi'};
  }

  int get _kayitSkoru => (kayit?['skor'] as int?) ?? 0;

  int get _soruSayisi => ((oyun?['soru_verisi'] as List?) ?? const []).length;

  // 034_skor_sunucuda.sql'deki kesisim_cevap fonksiyonunun basit bir kopyası
  @override
  Future<KesisimCevapSonucu> kesisimCevap({required String oyunId, required int soruIndex, required String oyuncuId}) async {
    cevapKontrolSayisi++;
    if (cevapKontrolBekletici != null) await cevapKontrolBekletici!.future;
    if (cevapKontrolHataVerir) throw Exception('bağlantı yok');
    if (skorYazBekletici != null) await skorYazBekletici!.future;
    if (skorYazHataVerir) throw Exception('bağlantı yok');

    if (_sureDolduysaKapat()) return KesisimCevapSonucu(dogru: false, skor: _kayitSkoru, bitti: true, sureDoldu: true);
    if (soruIndex != ilerleme.length) throw Exception('Sıra hatalı');

    final dogru = dogruCevaplar.contains(oyuncuId);
    final isim = oneriler.firstWhere((o) => o.id == oyuncuId, orElse: () => OyuncuOneri(id: oyuncuId, isim: oyuncuId)).isim;
    final skor = _kayitSkoru + (dogru ? 2 : 0);
    ilerleme = [...ilerleme, {'dogru': dogru, 'cevap': isim}];
    final bitti = ilerleme.length >= _soruSayisi;
    _skoruYaz(skor, bitti);
    return KesisimCevapSonucu(dogru: dogru, skor: skor, bitti: bitti);
  }

  // 034_skor_sunucuda.sql'deki bonservis_tahmin fonksiyonunun basit bir kopyası. Bedeller soru verisinden okunur.
  @override
  Future<BonservisTahminSonucu> bonservisTahmin({required String oyunId, required int soruIndex, required bool dahaFazla}) async {
    if (skorYazBekletici != null) await skorYazBekletici!.future;
    if (skorYazHataVerir) throw Exception('bağlantı yok');

    if (_sureDolduysaKapat()) return BonservisTahminSonucu(dogru: false, skor: _kayitSkoru, bitti: true, sureDoldu: true);
    if (soruIndex != ilerleme.length) throw Exception('Sıra hatalı');

    final soru = (oyun!['soru_verisi'] as List)[soruIndex] as Map<String, dynamic>;
    final referans = (soru['oyuncu_a_bonservis'] as num).toInt();
    final rakip = _rakipBedeli(soruIndex)!;
    final dogru = dahaFazla == (rakip > referans);
    final skor = _kayitSkoru + (dogru ? 2 : 0);
    ilerleme = [...ilerleme, {'dogru': dogru}];
    final bitti = ilerleme.length >= _soruSayisi;
    _skoruYaz(skor, bitti);
    return BonservisTahminSonucu(dogru: dogru, rakipBonservis: rakip, skor: skor, bitti: bitti);
  }

  // Sunucudaki bonservis_cevaplari tablosu: testler doldurmazsa soru verisindeki eski usul bedel kullanılır
  Map<int, int> bonservisCevaplari = {};

  int? _rakipBedeli(int soruIndex) {
    final soru = (oyun!['soru_verisi'] as List)[soruIndex] as Map<String, dynamic>;
    return bonservisCevaplari[soruIndex] ?? (soru['oyuncu_b_bonservis'] as num?)?.toInt();
  }

  @override
  Future<Map<int, int>> bonservisBedelleri(String oyunId) async {
    bonservisBedelIstekSayisi++;
    final kadar = kayit?['durum'] == 'tamamlandi' ? _soruSayisi : ilerleme.length;
    return {
      for (var i = 0; i < kadar; i++)
        if (_rakipBedeli(i) != null) i: _rakipBedeli(i)!,
    };
  }

  @override
  Future<void> oyunuBitir(String oyunId) async {
    oyunuBitirSayisi++;
    if (skorYazBekletici != null) await skorYazBekletici!.future;
    if (skorYazHataVerir) throw Exception('bağlantı yok');
    if (kayit?['durum'] != 'basladi') return;
    _skoruYaz(_kayitSkoru, true);
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

  int get _top10Skoru => top10TahminListesi.where((t) => t.sira != null).length;

  @override
  Future<List<Top10Tahmini>> top10Tahminleri(String oyunId) async => List.of(top10TahminListesi);

  int get _top10KalanCan => top10Can - top10TahminListesi.where((t) => t.sira == null).length;

  // 031_top10_can.sql'deki top10_tahmin fonksiyonunun basit bir kopyası: isim eşleşmesi, tekrar sayılmaz ve can götürmez,
  // yanlış tahmin bir can götürür; 10 bulununca ya da canlar bitince biter
  @override
  Future<Top10TahminSonucu> top10Tahmin({required String oyunId, required String oyuncuId}) async {
    if (top10TahminHataVerir) throw Exception('bağlantı yok');
    final isim = oneriler.firstWhere((o) => o.id == oyuncuId, orElse: () => OyuncuOneri(id: oyuncuId, isim: oyuncuId)).isim;
    if (top10TahminListesi.any((t) => t.oyuncuIsim == isim)) {
      return Top10TahminSonucu(
          dogru: false, tekrar: true, oyuncuIsim: isim, skor: _top10Skoru, kalanCan: _top10KalanCan, bitti: false);
    }
    final bulunan = top10Listesi.entries.where((e) => e.value.$2.isim == isim).map((e) => e.key).firstOrNull;
    top10TahminListesi.add(Top10Tahmini(oyuncuIsim: isim, sira: bulunan));
    final bitti = _top10Skoru == top10Boyu || _top10KalanCan <= 0;
    kayit = {...?kayit, 'skor': _top10Skoru, 'durum': bitti ? 'tamamlandi' : 'basladi'};
    return Top10TahminSonucu(
      dogru: bulunan != null,
      sira: bulunan,
      deger: bulunan == null ? null : top10Listesi[bulunan]!.$2.deger,
      oyuncuIsim: isim,
      skor: _top10Skoru,
      kalanCan: _top10KalanCan,
      bitti: bitti,
    );
  }

  @override
  Future<int> top10PesEt(String oyunId) async {
    top10PesSayisi++;
    kayit = {...?kayit, 'skor': _top10Skoru, 'durum': 'tamamlandi'};
    return _top10Skoru;
  }

  // Oyun bitmediyse sadece bulunanlar, bittiyse bütün liste
  @override
  Future<Map<int, Top10Oyuncusu>> top10Cevaplar(String oyunId) async {
    final bitti = kayit?['durum'] == 'tamamlandi';
    final bulunanlar = {for (final t in top10TahminListesi) ?t.sira};
    return {
      for (final e in top10Listesi.entries)
        if (bitti || bulunanlar.contains(e.key)) e.key: e.value.$2,
    };
  }
}
