import 'package:flutter/material.dart';
import '../models/oyun_modu.dart';
import '../theme/renkler.dart';

// Hub'daki oynanabilir (veya hazırlanan) oyun kartı
class OyunKarti extends StatelessWidget {
  final OyunModu mod;
  final int? bugunkuSkor; // null ise bugün henüz oynanmadı
  final VoidCallback onTap;

  const OyunKarti({super.key, required this.mod, required this.bugunkuSkor, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Renkler.yuzey,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Renkler.kenar),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: mod.renk.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(mod.ikon, color: mod.renk, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mod.baslik,
                      style: const TextStyle(color: Renkler.metin, fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      mod.aciklama,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Renkler.metinIkincil, fontSize: 13, height: 1.35),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _DurumEtiketi(mod: mod, bugunkuSkor: bugunkuSkor),
            ],
          ),
        ),
      ),
    );
  }
}

class _DurumEtiketi extends StatelessWidget {
  final OyunModu mod;
  final int? bugunkuSkor;

  const _DurumEtiketi({required this.mod, required this.bugunkuSkor});

  @override
  Widget build(BuildContext context) {
    if (bugunkuSkor != null) {
      final skorMetni = mod.maksimumSkor != null ? '$bugunkuSkor/${mod.maksimumSkor}' : '$bugunkuSkor';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            skorMetni,
            style: const TextStyle(color: Renkler.metin, fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, color: Renkler.basari, size: 13),
              SizedBox(width: 4),
              Text('Bitti', style: TextStyle(color: Renkler.basari, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      );
    }

    if (mod.durum == OyunDurumu.aktif) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(color: mod.renk, borderRadius: BorderRadius.circular(8)),
        child: const Text(
          'Oyna',
          style: TextStyle(color: Renkler.arkaPlan, fontSize: 14, fontWeight: FontWeight.w700),
        ),
      );
    }

    return const Text('Hazırlanıyor', style: TextStyle(color: Renkler.metinSoluk, fontSize: 13));
  }
}

// Hub'ın altındaki "Yakında" listesi: dokunulamaz, sadece bilgi verir
class YakindaListesi extends StatelessWidget {
  final List<OyunModu> modlar;

  const YakindaListesi({super.key, required this.modlar});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Renkler.kenar),
      ),
      child: Column(
        children: [
          for (var i = 0; i < modlar.length; i++) ...[
            if (i > 0) const Divider(indent: 16, endIndent: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(modlar[i].ikon, color: Renkler.metinSoluk, size: 22),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          modlar[i].baslik,
                          style: const TextStyle(color: Renkler.metinIkincil, fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          modlar[i].aciklama,
                          style: const TextStyle(color: Renkler.metinSoluk, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
