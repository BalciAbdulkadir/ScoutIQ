import 'dart:async';

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

  // kayitAc çağrıldığında başka bir cihazın kaydı atmış gibi davranılsın mı
  bool kayitAcCakisir = false;

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
  Map<int, String> izgaraOrnekleri = {for (var i = 0; i < 9; i++) i: 'Örnek Oyuncu $i'};

  // Çağrı kayıtları
  int kayitAcSayisi = 0;
  int cevapKontrolSayisi = 0;
  final List<String> arananlar = [];
  final List<({int skor, bool bitti})> yazilanSkorlar = [];
  bool yarimKayitKapatildi = false;

  @override
  Future<String> oyunTarihi() async {
    if (tarihHataVerir) throw Exception('bağlantı yok');
    return tarih;
  }

  @override
  Future<Map<String, dynamic>?> oyunKaydi(String kullaniciId, String oyunTipi, String tarih) async => kayit;

  @override
  Future<void> yarimKaydiKapat(String kullaniciId, String oyunTipi, String tarih) async {
    yarimKayitKapatildi = true;
    if (kayit?['durum'] == 'basladi') kayit = {...kayit!, 'durum': 'tamamlandi'};
  }

  @override
  Future<Map<String, dynamic>?> gununOyunu(String oyunTipi, String tarih) async {
    if (oyunYuklemeHataVerir) throw Exception('bağlantı yok');
    return oyun;
  }

  @override
  Future<void> kayitAc({required String kullaniciId, required String oyunId, required String oyunTipi, required String tarih}) async {
    kayitAcSayisi++;
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
  Future<bool> skorYaz({required String kullaniciId, required String oyunTipi, required String tarih, required int skor, required bool bitti}) async {
    if (skorYazBekletici != null) await skorYazBekletici!.future;
    if (skorYazHataVerir) throw Exception('bağlantı yok');
    if (kayit?['durum'] != 'basladi') return false;
    yazilanSkorlar.add((skor: skor, bitti: bitti));
    kayit = {'skor': skor, 'durum': bitti ? 'tamamlandi' : 'basladi'};
    return true;
  }

  @override
  Future<List<IzgaraTahmini>> izgaraTahminleri(String oyunId) async => izgaraTahminListesi;

  @override
  Future<IzgaraTahminSonucu> izgaraTahmin({required String oyunId, required String oyuncuId}) async {
    if (izgaraTahminHataVerir) throw Exception('bağlantı yok');
    final isim = oneriler.firstWhere((o) => o.id == oyuncuId).isim;
    final dolu = izgaraTahminListesi.where((t) => t.hucre != null).length;

    if (izgaraTahminListesi.any((t) => t.oyuncuIsim == isim)) {
      return IzgaraTahminSonucu(
        dogru: false, tekrar: true, oyuncuIsim: isim, kalanHak: 9 - izgaraTahminListesi.length, skor: dolu, bitti: false);
    }

    final hucre = izgaraHucreleri[oyuncuId];
    final bos = hucre != null && !izgaraTahminListesi.any((t) => t.hucre == hucre);
    izgaraTahminListesi = [
      ...izgaraTahminListesi,
      IzgaraTahmini(sira: izgaraTahminListesi.length + 1, oyuncuIsim: isim, hucre: bos ? hucre : null),
    ];
    final skor = dolu + (bos ? 1 : 0);
    final kalan = 9 - izgaraTahminListesi.length;
    final bitti = kalan == 0 || skor == 9;
    kayit = {'skor': skor, 'durum': bitti ? 'tamamlandi' : 'basladi'};
    return IzgaraTahminSonucu(
        dogru: bos, hucre: bos ? hucre : null, oyuncuIsim: isim, kalanHak: kalan, skor: skor, bitti: bitti);
  }

  @override
  Future<int> izgaraPesEt(String oyunId) async {
    izgaraPesSayisi++;
    final skor = izgaraTahminListesi.where((t) => t.hucre != null).length;
    kayit = {'skor': skor, 'durum': 'tamamlandi'};
    return skor;
  }

  @override
  Future<Map<int, String>> izgaraOrnekCevaplar(String oyunId) async {
    if (kayit?['durum'] != 'tamamlandi') return {};
    return izgaraOrnekleri;
  }
}
