import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/hub_provider.dart';
import 'hatirlatma.dart';
import 'puanlama.dart';

// Bir oyun oynanırken bitince yapılanlar (oyunların provider'ları çağırır; bitmiş oyunu açmak sayılmaz):
// - Bugünün akşam hatırlatması silinir: bugün bir oyun bitti
// - Bildirim izni ilk biten oyundan sonra bir kez istenir (açılışta değil)
// - 3 farklı gün oyun bitirildikten sonra iyi sonuçlu bir oyunda bir kez "uygulamayı puanla" sorulur
class OyunSonu {
  final Hatirlatma _hatirlatma;
  final PuanlamaIstegi _puanlama;
  final String Function() _bugun;

  OyunSonu(this._hatirlatma, this._puanlama, {String Function()? bugun}) : _bugun = bugun ?? bugununTarihi;

  Future<void> oyunBitti({required String gunlukOyunTipi, required int skor}) async {
    try {
      await _hatirlatma.bugunuIptalEt();
      if (await _hatirlatma.acikMi() && !await _hatirlatma.izinSoruldu()) {
        await _hatirlatma.izinIste();
      }
    } catch (_) {
      // Hatırlatma oyunu asla bozmasın
    }
    try {
      await _puanlama.oyunBitti(gunlukOyunTipi: gunlukOyunTipi, skor: skor, bugun: _bugun());
    } catch (_) {}
  }
}

final oyunSonuProvider =
    Provider<OyunSonu>((ref) => OyunSonu(ref.watch(hatirlatmaProvider), ref.watch(puanlamaProvider)));
