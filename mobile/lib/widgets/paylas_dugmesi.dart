import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/hub_provider.dart';
import '../services/analitik.dart';
import '../services/paylasim.dart';
import '../theme/renkler.dart';

// Bitiş ekranındaki "Sonucu paylaş" düğmesi. Metin bilinen seriyle kurulur (services/paylasim.dart),
// telefonun paylaşım penceresi açılır ve analitiğe sonuc_paylasildi gider.
class PaylasDugmesi extends ConsumerWidget {
  final String oyun; // kesisim, bonservis, izgara, bingo, top10
  final String Function(int? seri) metin;

  const PaylasDugmesi({super.key, required this.oyun, required this.metin});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Seri bitiş ekranı açılırken yüklenmeye başlar; basıldığında hâlâ gelmediyse beklenir, okunamazsa yazılmaz
    final seriDurumu = ref.watch(seriProvider);
    return OutlinedButton.icon(
      onPressed: () async {
        int? seri = seriDurumu.value;
        try {
          seri ??= await ref.read(seriProvider.future).timeout(const Duration(seconds: 3));
        } catch (_) {}
        try {
          await ref.read(paylasiciProvider).paylas(metin(seri));
          ref.read(analitikProvider).sonucPaylasildi(oyunTipi: oyun);
        } catch (_) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(const SnackBar(content: Text('Paylaşım açılamadı.')));
        }
      },
      style: OutlinedButton.styleFrom(
        foregroundColor: Renkler.vurgu,
        side: const BorderSide(color: Renkler.vurgu, width: 1.4),
        minimumSize: const Size.fromHeight(50),
      ),
      icon: const Icon(Icons.share_rounded),
      label: const Text('Sonucu paylaş'),
    );
  }
}
