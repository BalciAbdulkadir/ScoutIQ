import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/izgara.dart';
import '../providers/hub_provider.dart';
import '../screens/izgara_screen.dart';
import '../theme/renkler.dart';
import 'oyun_ortak.dart';

// Hub'da Izgara kartına dokununca çağrılır. Yarım kalan bir tahta varsa zorluk ve süre sorulmadan o tahta
// kaldığı yerden (kalan süresiyle) açılır; yoksa zorluk ve süre seçimi gösterilir. Dönünce hub tazelenir.
Future<void> izgaraAc(BuildContext context, WidgetRef ref) async {
  IzgaraAcilisi? secilen;
  try {
    final devamEden = await ref.read(devamEdenIzgaraProvider.future);
    if (devamEden != null) secilen = (zorluk: devamEden, sure: null);
  } catch (_) {
    // Bilinmiyorsa zorluk seçimi gösterilir; yarım tahta seçilince yine kaldığı yerden açılır
  }
  if (!context.mounted) return;

  secilen ??= await showModalBottomSheet<IzgaraAcilisi>(
    context: context,
    backgroundColor: Renkler.yuzey,
    showDragHandle: true,
    // Süre ve zorluk birlikte varsayılan yarım ekrana sığmıyor: içerik kadar uzar, küçük ekranda kaydırılır
    isScrollControlled: true,
    builder: (context) => const IzgaraZorlukSecimi(),
  );
  if (secilen == null || !context.mounted) return;

  final acilis = secilen;
  await Navigator.push(
    context,
    MaterialPageRoute(builder: (context) => IzgaraScreen(zorluk: acilis.zorluk, sure: acilis.sure)),
  );
  if (!context.mounted) return;
  ref.invalidate(bugunOynananlarProvider);
  ref.invalidate(devamEdenIzgaraProvider);
}

class IzgaraZorlukSecimi extends ConsumerStatefulWidget {
  const IzgaraZorlukSecimi({super.key});

  @override
  ConsumerState<IzgaraZorlukSecimi> createState() => _IzgaraZorlukSecimiState();
}

class _IzgaraZorlukSecimiState extends ConsumerState<IzgaraZorlukSecimi> {
  int? _sure; // Seçilen süre; null: süre yok

  @override
  Widget build(BuildContext context) {
    final oynananlar = ref.watch(bugunOynananlarProvider);
    final skorlar = oynananlar.hasValue ? oynananlar.requireValue : const <String, int>{};

    return SafeArea(
      child: SingleChildScrollView(
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
              'Her zorluk ayrı bir tahta, her biri günde bir kez oynanır.',
              style: TextStyle(color: Renkler.metinIkincil, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 16),
            const Text(
              'SÜRE',
              style: TextStyle(color: Renkler.metinSoluk, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.2),
            ),
            const SizedBox(height: 8),
            _SureSecimi(secilen: _sure, onSecildi: (sure) => setState(() => _sure = sure)),
            const SizedBox(height: 18),
            const Text(
              'ZORLUK',
              style: TextStyle(color: Renkler.metinSoluk, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.2),
            ),
            const SizedBox(height: 8),
            for (final zorluk in IzgaraZorlugu.values) ...[
              _ZorlukSatiri(
                zorluk: zorluk,
                skor: skorlar[zorluk.oyunTipi],
                onSecildi: () => Navigator.pop<IzgaraAcilisi>(context, (zorluk: zorluk, sure: _sure)),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

// Süre yok / 30 / 60 / 90 sn. Süre bütün tahta içindir, oyun başlayınca değiştirilemez.
class _SureSecimi extends StatelessWidget {
  final int? secilen;
  final ValueChanged<int?> onSecildi;

  const _SureSecimi({required this.secilen, required this.onSecildi});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < izgaraSureleri.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: _SureSecenegi(sure: izgaraSureleri[i], secili: izgaraSureleri[i] == secilen, onTap: onSecildi)),
        ],
      ],
    );
  }
}

class _SureSecenegi extends StatelessWidget {
  final int? sure;
  final bool secili;
  final ValueChanged<int?> onTap;

  const _SureSecenegi({required this.sure, required this.secili, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: secili ? Renkler.izgara.withValues(alpha: 0.16) : Renkler.yuzeyYuksek,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: secili ? Renkler.izgara : Renkler.kenar),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onTap(sure),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Text(
            izgaraSureMetni(sure),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: secili ? Renkler.metin : Renkler.metinIkincil,
              fontSize: 13,
              fontWeight: secili ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _ZorlukSatiri extends StatelessWidget {
  final IzgaraZorlugu zorluk;
  final int? skor; // null: bugün bitirilmedi
  final VoidCallback onSecildi;

  const _ZorlukSatiri({required this.zorluk, required this.skor, required this.onSecildi});

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
        onTap: onSecildi,
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
