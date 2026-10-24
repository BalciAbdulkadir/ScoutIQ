import 'dart:async';

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

  // Doluysa skor yazımı bu Completer tamamlanana kadar bekler
  Completer<void>? skorYazBekletici;
  bool skorYazHataVerir = false;

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
  Future<bool> skorYaz({required String kullaniciId, required String oyunTipi, required String tarih, required int skor, required bool bitti}) async {
    if (skorYazBekletici != null) await skorYazBekletici!.future;
    if (skorYazHataVerir) throw Exception('bağlantı yok');
    if (kayit?['durum'] != 'basladi') return false;
    yazilanSkorlar.add((skor: skor, bitti: bitti));
    kayit = {'skor': skor, 'durum': bitti ? 'tamamlandi' : 'basladi'};
    return true;
  }
}
