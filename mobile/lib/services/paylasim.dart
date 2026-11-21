import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

// Bitiş ekranındaki "Sonucu paylaş" düğmesinin metni. Cevapları ele vermez: sadece hangi soruların/kutuların
// bilindiği renkli karelerle gösterilir, oyuncu isimleri yazmaz. Bu dosyadaki metin fonksiyonları saftır (yan etkisiz).

const playStoreLinki = 'https://play.google.com/store/apps/details?id=com.footylore.app';

const _dogru = '🟩';
const _yanlis = '🟥';
const _bos = '⬛';

// "FootyLore · Izgara · Zor · 60 sn". Zorluksuz oyunda zorluk, süresiz oyunda süre yazmaz.
String paylasimBasligi({required String oyunAdi, String? zorluk, int? sure}) => [
      'FootyLore',
      oyunAdi,
      if (zorluk != null) _zorlukAdi(zorluk),
      if (sure != null && sure > 0) '$sure sn',
    ].join(' · ');

String _zorlukAdi(String zorluk) => switch (zorluk) {
      'kolay' => 'Kolay',
      'orta' => 'Orta',
      'zor' => 'Zor',
      _ => zorluk,
    };

// Ortak son satırlar: liderlik puanı (puanlı bitişte), seri (varsa) ve uygulamanın Play linki
String _metin(String baslik, List<String> govde, int? seri, [int? puan]) => [
      baslik,
      ...govde,
      if (puan != null && puan > 0) '⭐ $puan puan',
      if (seri != null && seri > 0) '🔥 $seri gün seri',
      playStoreLinki,
    ].join('\n');

// Kesişim ve Bonservis: her soru için doğru 🟩, yanlış 🟥, cevaplanmadan biten (süre doldu) ⬛
String _soruSirasi(List<bool> sonuclar, int soruSayisi) => [
      for (var i = 0; i < soruSayisi; i++) i < sonuclar.length ? (sonuclar[i] ? _dogru : _yanlis) : _bos,
    ].join();

String kesisimPaylasimi({required List<bool> sonuclar, int soruSayisi = 5, String? zorluk, int? sure, int? seri, int? puan}) {
  final dogru = sonuclar.where((d) => d).length;
  return _metin(
    paylasimBasligi(oyunAdi: 'Kesişim', zorluk: zorluk, sure: sure),
    ['${_soruSirasi(sonuclar, soruSayisi)}   $dogru/$soruSayisi'],
    seri,
    puan,
  );
}

String bonservisPaylasimi({required List<bool> sonuclar, int soruSayisi = 5, String? zorluk, int? sure, int? seri, int? puan}) {
  final dogru = sonuclar.where((d) => d).length;
  return _metin(
    paylasimBasligi(oyunAdi: 'Bonservis', zorluk: zorluk, sure: sure),
    ['${_soruSirasi(sonuclar, soruSayisi)}   $dogru/$soruSayisi'],
    seri,
    puan,
  );
}

// Kutulu oyunlar: satır satır dolu 🟩, boş ⬛; skor son satırın sonunda
List<String> _kutular({required Set<int> dolu, required int satir, required int sutun}) {
  final satirlar = [
    for (var s = 0; s < satir; s++) [for (var k = 0; k < sutun; k++) dolu.contains(s * sutun + k) ? _dogru : _bos].join(),
  ];
  satirlar[satirlar.length - 1] = '${satirlar.last}   ${dolu.length}/${satir * sutun}';
  return satirlar;
}

// Izgara: 3x3, hücre sırası satır satır (0 sol üst, 8 sağ alt)
String izgaraPaylasimi({required Set<int> doluHucreler, String? zorluk, int? sure, int? seri, int? puan}) => _metin(
      paylasimBasligi(oyunAdi: 'Izgara', zorluk: zorluk, sure: sure),
      _kutular(dolu: doluHucreler, satir: 3, sutun: 3),
      seri,
      puan,
    );

// Bingo: 4 satır 3 sütunluk kart, zorluk modu yok
String bingoPaylasimi({required Set<int> doluKutular, int? sure, int? seri, int? puan}) => _metin(
      paylasimBasligi(oyunAdi: 'Bingo', sure: sure),
      _kutular(dolu: doluKutular, satir: 4, sutun: 3),
      seri,
      puan,
    );

// Top 10: 1'den 10'a satırlar bulundu 🟩 / bulunamadı ⬛ (beşerli iki satır), skor ve kalan canlar ❤️ (giden 🤍)
String top10Paylasimi({required Set<int> bulunanSiralar, required int kalanCan, int toplamCan = 3, int? seri, int? puan}) {
  String satir(int bas) => [for (var s = bas; s < bas + 5; s++) bulunanSiralar.contains(s) ? _dogru : _bos].join();
  final canlar = '${'❤️' * kalanCan}${'🤍' * (toplamCan - kalanCan).clamp(0, toplamCan)}';
  return _metin(
    paylasimBasligi(oyunAdi: 'Top 10'),
    [satir(1), '${satir(6)}   ${bulunanSiralar.length}/10', canlar],
    seri,
    puan,
  );
}

// Telefonun paylaşım penceresi. Testlerde sahtesi verilir.
abstract class Paylasici {
  Future<void> paylas(String metin);
}

class SistemPaylasici implements Paylasici {
  const SistemPaylasici();

  @override
  Future<void> paylas(String metin) async {
    await SharePlus.instance.share(ShareParams(text: metin));
  }
}

final paylasiciProvider = Provider<Paylasici>((ref) => const SistemPaylasici());
