import 'package:flutter/material.dart';
import '../models/oyun_modu.dart';
import '../theme/renkler.dart';

// Oynanabilir (veya hazırlanan) modlar için tam genişlikte kart
class OyunKarti extends StatelessWidget {
  final OyunModu mod;
  final int? bugunkuSkor; // null ise bugün henüz oynanmadı
  final VoidCallback onTap;

  const OyunKarti({super.key, required this.mod, required this.bugunkuSkor, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final aktif = mod.durum == OyunDurumu.aktif;
    final oynandi = bugunkuSkor != null;

    return Material(
      color: Renkler.kart,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: aktif && !oynandi ? mod.renk.withValues(alpha: 0.5) : Renkler.kartKenar,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: mod.renk.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(mod.ikon, color: mod.renk, size: 30),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mod.baslik,
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      mod.aciklama,
                      style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.3),
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
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, color: Renkler.vurgu, size: 22),
          const SizedBox(height: 4),
          Text(skorMetni, style: const TextStyle(color: Renkler.vurgu, fontWeight: FontWeight.bold)),
        ],
      );
    }

    if (mod.durum == OyunDurumu.aktif) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(color: mod.renk, borderRadius: BorderRadius.circular(20)),
        child: const Text('Oyna', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(20)),
      child: const Text(
        'Hazırlanıyor',
        style: TextStyle(color: Renkler.soluk, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }
}

// Henüz aktif olmayan modlar için küçük kart
class YakindaKarti extends StatelessWidget {
  final OyunModu mod;
  final VoidCallback onTap;

  const YakindaKarti({super.key, required this.mod, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Renkler.kart.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(mod.ikon, color: Colors.white38, size: 30),
              const SizedBox(height: 10),
              Text(
                mod.baslik,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text('Yakında', style: TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}
