import 'dart:async';

import 'package:flutter/material.dart';
import '../theme/renkler.dart';
import '../theme/yazi.dart';

// Oyun ekranlarının ortak parçaları: ilerleme çubuğu ve bitiş ekranı.
// Kesişim ve Bonservis aynı parçaları kullanır ki iki oyun aynı uygulamanın parçası gibi görünsün.

// Soru başına bir parça: doğru yeşil, yanlış kırmızı, sıradaki soru modun renginde.
class OyunIlerlemesi extends StatelessWidget {
  final int soruSayisi;
  final int mevcutSoru; // 0'dan başlar
  final List<bool> sonuclar;
  final Color renk;
  final String sagMetin; // ör. "4 puan"
  final Widget? sayac; // Süreli oyunda ortada geri sayım

  const OyunIlerlemesi({
    super.key,
    required this.soruSayisi,
    required this.mevcutSoru,
    required this.sonuclar,
    required this.renk,
    required this.sagMetin,
    this.sayac,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < soruSayisi; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  height: 3,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(1.5),
                    color: switch (i < sonuclar.length ? sonuclar[i] : null) {
                      true => Renkler.basari,
                      false => Renkler.hata,
                      // Sıradaki soru nötr renkte: modun rengi (ör. Kesişim yeşili) "doğru" ile karışmasın
                      null => i == mevcutSoru ? Renkler.metinIkincil : Renkler.kenar,
                    },
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Soru ${mevcutSoru + 1}/$soruSayisi',
                style: Yazi.tebesir(16, renk: Renkler.metinIkincil, kalinlik: FontWeight.w400),
              ),
            ),
            ?sayac,
            Expanded(
              child: Text(sagMetin, textAlign: TextAlign.end, style: Yazi.tebesir(16, renk: Renkler.vurgu)),
            ),
          ],
        ),
      ],
    );
  }
}

// İki taraf arasındaki küçük "VS" rozeti
class VsRozeti extends StatelessWidget {
  const VsRozeti({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Renkler.arkaPlan,
        border: Border.all(color: Renkler.kenar, width: 1.5),
      ),
      child: Text('VS', style: Yazi.baslik(14, renk: Renkler.vurgu, kalinlik: FontWeight.w900)),
    );
  }
}

// Soru başındaki küçük etiket (ör. zorluk)
class OyunEtiketi extends StatelessWidget {
  final String metin;
  final Color renk;

  const OyunEtiketi({super.key, required this.metin, required this.renk});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 3, 7, 2),
      // Tebeşirle çizilmiş çerçeve
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: renk, width: 1.5),
      ),
      child: Text(Yazi.buyuk(metin), style: Yazi.etiket(boyut: 11, renk: renk)),
    );
  }
}

// Skor oranına göre bitiş başlığı
String bitisBasligi(int dogru, int toplam) {
  if (toplam == 0) return 'Oyun bitti';
  final oran = dogru / toplam;
  if (oran == 1) return 'Kusursuz';
  if (oran >= 0.6) return 'Çok iyi';
  if (oran >= 0.4) return 'İyi iş';
  if (dogru > 0) return 'Fena değil';
  return 'Bugün olmadı';
}

// Oyun bitince gösterilen özet: skor, başlık ve soru soru sonuçlar
class OyunBitisEkrani extends StatelessWidget {
  final String skor; // ör. "6/10"
  final String skorAciklamasi; // ör. "puan"
  final String baslik;
  final Color renk;
  final List<Widget> ozetSatirlari;

  const OyunBitisEkrani({
    super.key,
    required this.skor,
    required this.skorAciklamasi,
    required this.baslik,
    required this.renk,
    required this.ozetSatirlari,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        const SizedBox(height: 12),
        Text(
          Yazi.buyuk(baslik),
          textAlign: TextAlign.center,
          style: Yazi.baslik(38, kalinlik: FontWeight.w900),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            // Skor tahtaya elle yazılır
            Text(skor, style: Yazi.tebesir(60, renk: renk)),
            const SizedBox(width: 8),
            Text(skorAciklamasi, style: Yazi.tebesir(20, renk: Renkler.metinIkincil, kalinlik: FontWeight.w400)),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'yeni oyun gece yarısı tahtaya yazılır',
          textAlign: TextAlign.center,
          style: Yazi.tebesir(16, renk: Renkler.metinSoluk, kalinlik: FontWeight.w400),
        ),
        const SizedBox(height: 32),
        Text('ÖZET', style: Yazi.etiket(boyut: 12)),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Renkler.kenar, width: 1.5),
          ),
          child: Column(
            children: [
              for (var i = 0; i < ozetSatirlari.length; i++) ...[
                if (i > 0) const Divider(indent: 16, endIndent: 16),
                ozetSatirlari[i],
              ],
            ],
          ),
        ),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          child: const Text('Ana menüye dön'),
        ),
      ],
    );
  }
}

// Özet listesindeki bir satır: solda doğru/yanlış işareti, ortada soru, sağda ayrıntı
class OzetSatiri extends StatelessWidget {
  final bool? dogru; // null: soru cevaplanmadı
  final String baslik;
  final String? altBaslik;
  final String? dogruCevap; // Doluysa altBaslik'ın altında yeşil "Doğru cevap: ..." satırı çıkar
  final Widget? sag;

  const OzetSatiri({super.key, required this.dogru, required this.baslik, this.altBaslik, this.dogruCevap, this.sag});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(
            switch (dogru) {
              true => Icons.check_circle_rounded,
              false => Icons.cancel_rounded,
              null => Icons.remove_circle_outline_rounded,
            },
            size: 20,
            color: switch (dogru) {
              true => Renkler.basari,
              false => Renkler.hata,
              null => Renkler.metinSoluk,
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  baslik,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Renkler.metin, fontSize: 14, fontWeight: FontWeight.w600, height: 1.3),
                ),
                if (altBaslik != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    altBaslik!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Renkler.metinIkincil, fontSize: 13),
                  ),
                ],
                if (dogruCevap != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Doğru cevap: $dogruCevap',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Renkler.basari, fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
          if (sag != null) ...[const SizedBox(width: 12), sag!],
        ],
      ),
    );
  }
}

// Geri sayım: süreli oyunlarda (Izgara, Kesişim, Bonservis) gösterilir. Sayaç sadece gösterir ve sıfıra inince
// haber verir. Cevap gönderilirken süre dolarsa bildirim reddedilir, sayaç sıfırda kaldıkça tekrar denenir.
class SureSayaci extends StatefulWidget {
  final DateTime bitisZamani;
  final VoidCallback onBitti;

  const SureSayaci({super.key, required this.bitisZamani, required this.onBitti});

  @override
  State<SureSayaci> createState() => _SureSayaciState();
}

class _SureSayaciState extends State<SureSayaci> {
  Timer? _zamanlayici;
  late int _kalan = _hesapla();

  int _hesapla() {
    final ms = widget.bitisZamani.difference(DateTime.now()).inMilliseconds;
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }

  @override
  void initState() {
    super.initState();
    _zamanlayici = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final kalan = _hesapla();
      if (kalan != _kalan) setState(() => _kalan = kalan);
      if (kalan == 0) widget.onBitti();
    });
  }

  @override
  void dispose() {
    _zamanlayici?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final azKaldi = _kalan <= 10;
    final metin = '${_kalan ~/ 60}:${(_kalan % 60).toString().padLeft(2, '0')}';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.timer_outlined, size: 16, color: azKaldi ? Renkler.hata : Renkler.metinIkincil),
        const SizedBox(width: 4),
        Text(
          metin,
          style: Yazi.baslik(20, renk: azKaldi ? Renkler.hata : Renkler.metin).copyWith(fontFeatures: Yazi.sabitRakam),
        ),
      ],
    );
  }
}
