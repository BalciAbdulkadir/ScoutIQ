import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/puan.dart';
import '../services/oyun_deposu.dart';

// Bitmiş oyunun puanı (038_puan_ve_liderlik.sql). Parametre günlük oyun tipidir (ör. kesisim_zor, bingo).
// Durum: null henüz istenmedi, AsyncLoading yükleniyor, AsyncData(puan) geldi (null: puan yazılmamış),
// AsyncError okunamadı. Bitiş ekranı bunu izler; puan okunamazsa kart gösterilmez, oyun asla bozulmaz.
// Oyunun provider'ı oyun bitince yukle'yi çağırır ve ekran açık kaldıkça bunu dinleyerek canlı tutar.
class OyunPuaniNotifier extends Notifier<AsyncValue<PuanDetayi?>?> {
  final String oyunTipi;

  OyunPuaniNotifier(this.oyunTipi);

  Future<PuanDetayi?>? _yukleme;

  @override
  AsyncValue<PuanDetayi?>? build() => null;

  // Puanı sunucudan okur; ikinci çağrı aynı sonucu bekler. Hata olursa null döner.
  Future<PuanDetayi?> yukle({String? tarih}) => _yukleme ??= _oku(tarih);

  Future<PuanDetayi?> _oku(String? tarih) async {
    state = const AsyncLoading();
    try {
      final puan = await ref.read(oyunDeposuProvider).puanGetir(oyunTipi, tarih: tarih);
      if (ref.mounted) state = AsyncData(puan);
      return puan;
    } catch (e, st) {
      if (ref.mounted) state = AsyncError(e, st);
      return null;
    }
  }
}

final oyunPuaniProvider =
    NotifierProvider.autoDispose.family<OyunPuaniNotifier, AsyncValue<PuanDetayi?>?, String>(OyunPuaniNotifier.new);
