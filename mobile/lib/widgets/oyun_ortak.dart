import 'package:flutter/material.dart';
import '../theme/renkler.dart';

// Oyun ekranlarının ortak parçaları: ilerleme çubuğu ve bitiş ekranı.
// Kesişim ve Bonservis aynı parçaları kullanır ki iki oyun aynı uygulamanın parçası gibi görünsün.

// Soru başına bir parça: doğru yeşil, yanlış kırmızı, sıradaki soru modun renginde.
class OyunIlerlemesi extends StatelessWidget {
  final int soruSayisi;
  final int mevcutSoru; // 0'dan başlar
  final List<bool> sonuclar;
  final Color renk;
  final String sagMetin; // ör. "4 puan"

  const OyunIlerlemesi({
    super.key,
    required this.soruSayisi,
    required this.mevcutSoru,
    required this.sonuclar,
    required this.renk,
    required this.sagMetin,
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
                  height: 4,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
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
            Text(
              'Soru ${mevcutSoru + 1}/$soruSayisi',
              style: const TextStyle(color: Renkler.metinIkincil, fontSize: 13, fontWeight: FontWeight.w500),
            ),
            Text(
              sagMetin,
              style: const TextStyle(color: Renkler.metin, fontSize: 13, fontWeight: FontWeight.w600),
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
      child: const Text(
        'VS',
        style: TextStyle(color: Renkler.metinIkincil, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.5),
      ),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: renk.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
      child: Text(
        metin.toUpperCase(),
        style: TextStyle(color: renk, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8),
      ),
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
          baslik,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Renkler.metin, fontSize: 26, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              skor,
              style: TextStyle(
                color: renk,
                fontSize: 56,
                fontWeight: FontWeight.w800,
                height: 1,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 8),
            Text(skorAciklamasi, style: const TextStyle(color: Renkler.metinIkincil, fontSize: 16)),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'Yeni oyun gece yarısı açılıyor.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Renkler.metinSoluk, fontSize: 14),
        ),
        const SizedBox(height: 32),
        const Text(
          'ÖZET',
          style: TextStyle(color: Renkler.metinSoluk, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.2),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(color: Renkler.yuzey, borderRadius: BorderRadius.circular(14)),
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
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('Ana menüye dön', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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
