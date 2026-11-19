import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/oyun_modu.dart';
import 'analitik.dart';

// "Uygulamayı puanla" isteği: Play'in kendi değerlendirme penceresi (in_app_review).
// Kullanıcı 3 farklı gün oyun bitirdikten sonra, iyi sonuç aldığı bir oyunun bitişinde bir kez sorulur.
// Gösterildiyse bir daha gösterilmez. Bitirilen günler cihazda tutulur.

const puanlamaIcinGunSayisi = 3;
const iyiSonucOrani = 0.7;

// İyi sonuç: oyunun en yüksek skorunun en az %70'i (Kesişim/Bonservis 8/10, Izgara 7/9, Bingo 9/12, Top 10 7/10)
bool iyiSonuc(String gunlukOyunTipi, int skor) {
  final oyun = oyunVeZorluk(gunlukOyunTipi).oyun;
  final maksimum = oyunModlari.where((m) => m.tip == oyun).firstOrNull?.maksimumSkor;
  if (maksimum == null || maksimum <= 0) return false;
  return skor >= maksimum * iyiSonucOrani;
}

abstract class PuanlamaDeposu {
  Future<Set<String>> bitirilenGunler(); // yyyy-MM-dd (Türkiye saati)
  Future<void> gunEkle(String gun);
  Future<bool> soruldu();
  Future<void> sorulduIsaretle();
}

class YerelPuanlamaDeposu implements PuanlamaDeposu {
  static const _gunlerAnahtari = 'puanlama_bitirilen_gunler';
  static const _sorulduAnahtari = 'puanlama_soruldu';

  @override
  Future<Set<String>> bitirilenGunler() async =>
      ((await SharedPreferences.getInstance()).getStringList(_gunlerAnahtari) ?? const []).toSet();

  @override
  Future<void> gunEkle(String gun) async {
    final tercihler = await SharedPreferences.getInstance();
    final gunler = {...?tercihler.getStringList(_gunlerAnahtari), gun}.toList()..sort();
    // Sadece eşiğe kadar olan günler gerekir; liste büyümesin
    await tercihler.setStringList(_gunlerAnahtari, gunler.skip(gunler.length > 10 ? gunler.length - 10 : 0).toList());
  }

  @override
  Future<bool> soruldu() async => (await SharedPreferences.getInstance()).getBool(_sorulduAnahtari) ?? false;

  @override
  Future<void> sorulduIsaretle() async => (await SharedPreferences.getInstance()).setBool(_sorulduAnahtari, true);
}

// Testlerde ve varsayılan olarak: bellekte tutar
class BellekPuanlamaDeposu implements PuanlamaDeposu {
  final Set<String> gunler = {};
  bool sorulduMu = false;

  @override
  Future<Set<String>> bitirilenGunler() async => {...gunler};

  @override
  Future<void> gunEkle(String gun) async => gunler.add(gun);

  @override
  Future<bool> soruldu() async => sorulduMu;

  @override
  Future<void> sorulduIsaretle() async => sorulduMu = true;
}

abstract class PuanlamaPenceresi {
  Future<void> ac();
}

// Play'in değerlendirme penceresi. Play gösterip göstermeyeceğine kendisi karar verir (kota, cihaz).
class PlayPuanlamaPenceresi implements PuanlamaPenceresi {
  const PlayPuanlamaPenceresi();

  @override
  Future<void> ac() async {
    final inceleme = InAppReview.instance;
    if (await inceleme.isAvailable()) await inceleme.requestReview();
  }
}

class BosPuanlamaPenceresi implements PuanlamaPenceresi {
  const BosPuanlamaPenceresi();

  @override
  Future<void> ac() async {}
}

class PuanlamaIstegi {
  final PuanlamaDeposu _depo;
  final PuanlamaPenceresi _pencere;

  PuanlamaIstegi(this._depo, this._pencere);

  // Bir oyun bitti. bugun: oyun günü (yyyy-MM-dd, Türkiye saati). Pencere açıldıysa true.
  Future<bool> oyunBitti({required String gunlukOyunTipi, required int skor, required String bugun}) async {
    await _depo.gunEkle(bugun);
    if (await _depo.soruldu()) return false;
    if ((await _depo.bitirilenGunler()).length < puanlamaIcinGunSayisi) return false;
    if (!iyiSonuc(gunlukOyunTipi, skor)) return false;

    await _depo.sorulduIsaretle();
    await _pencere.ac();
    return true;
  }
}

// main.dart gerçek depo ve Play penceresiyle ezer
final puanlamaProvider =
    Provider<PuanlamaIstegi>((ref) => PuanlamaIstegi(BellekPuanlamaDeposu(), const BosPuanlamaPenceresi()));
