import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/izgara.dart';
import '../providers/hub_provider.dart';
import '../screens/izgara_screen.dart';
import '../screens/izgara_sure_screen.dart';
import '../theme/renkler.dart';
import 'oyun_ortak.dart';

// Hub'da Izgara kartına dokununca çağrılır. Kullanıcı günde tek bir Izgara oynar (kolay, orta ya da zor):
// bugün bir tahtaya başladıysa zorluk ve süre sorulmadan o tahta açılır (yarımsa kalan süresiyle, bittiyse sonucuyla).
// Başlamadıysa önce zorluk, sonra ayrı ekranda süre seçilir. Dönünce hub tazelenir.
Future<void> izgaraAc(BuildContext context, WidgetRef ref) async {
  IzgaraAcilisi? acilis;
  try {
    final bugunku = await ref.read(bugunkuIzgaraProvider.future);
    if (bugunku != null) acilis = (zorluk: bugunku.zorluk, sure: null);
  } catch (_) {
    // Bilinmiyorsa seçim gösterilir; sunucu ikinci bir Izgara'nın başlatılmasına zaten izin vermez
  }
  if (!context.mounted) return;

  if (acilis == null) {
    final zorluk = await showModalBottomSheet<IzgaraZorlugu>(
      context: context,
      backgroundColor: Renkler.yuzey,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => const IzgaraZorlukSecimi(),
    );
    if (zorluk == null || !context.mounted) return;

    acilis = await Navigator.push<IzgaraAcilisi>(
      context,
      MaterialPageRoute(builder: (context) => IzgaraSureScreen(zorluk: zorluk)),
    );
    if (acilis == null || !context.mounted) return;
  }

  final secilen = acilis;
  await Navigator.push(
    context,
    MaterialPageRoute(builder: (context) => IzgaraScreen(zorluk: secilen.zorluk, sure: secilen.sure)),
  );
  if (!context.mounted) return;
  ref.invalidate(bugunOynananlarProvider);
  ref.invalidate(bugunkuIzgaraProvider);
}

// Zorluk seçimi. Seçilen zorlukla kapanır.
class IzgaraZorlukSecimi extends StatelessWidget {
  const IzgaraZorlukSecimi({super.key});

  @override
  Widget build(BuildContext context) {
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
              'Günde tek bir Izgara oynayabilirsin. Seçtiğin zorluk bugünün tahtası olur.',
              style: TextStyle(color: Renkler.metinIkincil, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 16),
            for (final zorluk in IzgaraZorlugu.values) ...[
              _ZorlukSatiri(zorluk: zorluk, onSecildi: () => Navigator.pop<IzgaraZorlugu>(context, zorluk)),
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
  final VoidCallback onSecildi;

  const _ZorlukSatiri({required this.zorluk, required this.onSecildi});

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
              const Icon(Icons.chevron_right_rounded, color: Renkler.metinIkincil),
            ],
          ),
        ),
      ),
    );
  }
}
