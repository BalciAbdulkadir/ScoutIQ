import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'hatirlatma.dart';

// Bir oyun oynanırken bitince yapılanlar (oyunların provider'ları çağırır; bitmiş oyunu açmak sayılmaz):
// - Bugünün akşam hatırlatması silinir: bugün bir oyun bitti
// - Bildirim izni ilk biten oyundan sonra bir kez istenir (açılışta değil)
class OyunSonu {
  final Hatirlatma _hatirlatma;

  OyunSonu(this._hatirlatma);

  Future<void> oyunBitti({required String gunlukOyunTipi, required int skor}) async {
    try {
      await _hatirlatma.bugunuIptalEt();
      if (await _hatirlatma.acikMi() && !await _hatirlatma.izinSoruldu()) {
        await _hatirlatma.izinIste();
      }
    } catch (_) {
      // Hatırlatma oyunu asla bozmasın
    }
  }
}

final oyunSonuProvider = Provider<OyunSonu>((ref) => OyunSonu(ref.watch(hatirlatmaProvider)));
