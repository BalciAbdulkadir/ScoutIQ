import 'package:flutter/material.dart';
import '../models/oyun_modu.dart';
import '../theme/renkler.dart';
import '../theme/yazi.dart';
import 'oyun_ornekleri.dart';
import 'tebesir.dart';

// Bir oyunun kuralları: örnek çizim, kısa anlatım, numaralı kurallar ve puanlama.
// Oyun başlamadan açılan önizlemede ve oyun ekranındaki "?" düğmesiyle açılan sayfada aynı içerik gösterilir.
class OyunKurallari extends StatelessWidget {
  final OyunOnizlemesi onizleme;
  final TebesirCizimi cizim;

  const OyunKurallari({super.key, required this.onizleme, required this.cizim});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        OyunOrnegi(cizim: cizim),
        const SizedBox(height: 14),
        Text(onizleme.ozet, style: const TextStyle(color: Renkler.metin, fontSize: 15, height: 1.45)),
        Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 10),
          child: Text(Yazi.buyuk('Nasıl oynanır'), style: Yazi.etiket(renk: Renkler.vurgu)),
        ),
        for (final (i, kural) in onizleme.kurallar.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 26, child: Text('${i + 1}', style: Yazi.tebesir(20, renk: Renkler.vurgu))),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(kural, style: const TextStyle(color: Renkler.metinIkincil, fontSize: 14, height: 1.4)),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 6),
        TebesirKutusu(
          kesik: true,
          kenarRengi: Renkler.vurgu,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Text(Yazi.buyuk('Puan'), style: Yazi.etiket(renk: Renkler.vurgu)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  onizleme.puanlama,
                  style: const TextStyle(color: Renkler.metin, fontSize: 14, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Her oyun günde bir kez oynanır. Oyundan çıksan da kaldığın yerden devam edersin.',
          style: TextStyle(color: Renkler.metinSoluk, fontSize: 12.5, height: 1.35),
        ),
      ],
    );
  }
}

// Oyun ekranının üstündeki "?" düğmesi: oyunun kurallarını alt sayfada tekrar açar. Oyun bu sırada sürer.
class KurallarDugmesi extends StatelessWidget {
  final String oyun; // Hub'daki oyun tipi: kesisim, bonservis, izgara, bingo, top10

  const KurallarDugmesi({super.key, required this.oyun});

  @override
  Widget build(BuildContext context) {
    final mod = oyunModlari.where((m) => m.tip == oyun).firstOrNull;
    if (mod?.onizleme == null) return const SizedBox.shrink();

    return IconButton(
      tooltip: 'Nasıl oynanır',
      onPressed: () => kurallariGoster(context, mod!),
      icon: const Icon(Icons.help_outline_rounded, color: Renkler.metinIkincil),
    );
  }
}

Future<void> kurallariGoster(BuildContext context, OyunModu mod) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  TebesirIkonu(cizim: mod.cizim ?? TebesirCizimi.kesisim, boyut: 38),
                  const SizedBox(width: 12),
                  Expanded(child: Text(Yazi.buyuk(mod.baslik), style: Yazi.baslik(26, kalinlik: FontWeight.w900))),
                ],
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: OyunKurallari(onizleme: mod.onizleme!, cizim: mod.cizim ?? TebesirCizimi.kesisim),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: Text(Yazi.buyuk('Oyuna dön')),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
