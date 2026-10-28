import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/izgara.dart';
import '../providers/hub_provider.dart';
import '../screens/izgara_screen.dart';
import '../theme/renkler.dart';
import 'oyun_ortak.dart';

// Hub'da Izgara kartına dokununca açılan zorluk seçimi. Seçilen tahta açılır, dönünce hub tazelenir.
Future<void> izgaraZorlukSecimiAc(BuildContext context, WidgetRef ref) async {
  final secilen = await showModalBottomSheet<IzgaraZorlugu>(
    context: context,
    backgroundColor: Renkler.yuzey,
    showDragHandle: true,
    builder: (context) => const IzgaraZorlukSecimi(),
  );
  if (secilen == null || !context.mounted) return;

  await Navigator.push(context, MaterialPageRoute(builder: (context) => IzgaraScreen(zorluk: secilen)));
  if (!context.mounted) return;
  ref.invalidate(bugunOynananlarProvider);
}

class IzgaraZorlukSecimi extends ConsumerWidget {
  const IzgaraZorlukSecimi({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final oynananlar = ref.watch(bugunOynananlarProvider);
    final skorlar = oynananlar.hasValue ? oynananlar.requireValue : const <String, int>{};

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Izgara',
              style: TextStyle(color: Renkler.metin, fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            const Text(
              'Her zorluk ayrı bir tahta, her biri günde bir kez oynanır. 9 tahmin hakkın var.',
              style: TextStyle(color: Renkler.metinIkincil, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 16),
            for (final zorluk in IzgaraZorlugu.values) ...[
              _ZorlukSatiri(zorluk: zorluk, skor: skorlar[zorluk.oyunTipi]),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _ZorlukSatiri extends StatelessWidget {
  final IzgaraZorlugu zorluk;
  final int? skor; // null: bugün bitirilmedi

  const _ZorlukSatiri({required this.zorluk, required this.skor});

  @override
  Widget build(BuildContext context) {
    final renk = IzgaraScreen.zorlukRengi(zorluk);

    return Material(
      color: Renkler.yuzeyYuksek,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Renkler.kenar),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.pop(context, zorluk),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OyunEtiketi(metin: zorluk.ad, renk: renk),
                    const SizedBox(height: 6),
                    Text(zorluk.aciklama, style: const TextStyle(color: Renkler.metinIkincil, fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (skor != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$skor/9',
                      style: const TextStyle(color: Renkler.metin, fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.check_circle, color: Renkler.basari, size: 16),
                  ],
                )
              else
                const Icon(Icons.chevron_right_rounded, color: Renkler.metinIkincil),
            ],
          ),
        ),
      ),
    );
  }
}
