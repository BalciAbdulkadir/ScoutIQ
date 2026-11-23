import 'package:mobile/services/hatirlatma.dart';

// Testler için: bildirim kurmaz, çağrıları kaydeder
class SahteHatirlatma implements Hatirlatma {
  bool acik = true;
  bool izinSorulduMu = false;
  int izinIstekSayisi = 0;
  bool izinVarMi = false; // Telefon izin veriyor mu
  int bugunIptalSayisi = 0;
  final List<({int seri, bool bugunBitirdi})> planlar = [];

  @override
  Future<bool> acikMi() async => acik;

  @override
  Future<void> ayarla(bool acik) async {
    this.acik = acik;
    if (acik) await izinIste();
  }

  @override
  Future<void> planla({required int seri, required bool bugunBitirdi}) async =>
      planlar.add((seri: seri, bugunBitirdi: bugunBitirdi));

  @override
  Future<void> bugunuIptalEt() async => bugunIptalSayisi++;

  @override
  Future<void> izinIste() async {
    izinIstekSayisi++;
    izinSorulduMu = true;
  }

  @override
  Future<bool> izinSoruldu() async => izinSorulduMu;

  @override
  Future<void> izinSorulduIsaretle() async => izinSorulduMu = true;

  @override
  Future<bool> izinVar() async => izinVarMi;
}
