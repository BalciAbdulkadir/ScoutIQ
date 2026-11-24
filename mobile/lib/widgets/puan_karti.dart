import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/puan.dart';
import '../providers/puan_provider.dart';
import '../screens/liderlik_screen.dart';
import '../services/oyun_deposu.dart';
import '../theme/renkler.dart';
import '../theme/yazi.dart';
import 'takma_ad_sayfasi.dart';

// Bitiş ekranındaki puan (038_puan_ve_liderlik.sql). Parametre günlük oyun tipidir (ör. kesisim_zor).
// - Puan gelene kadar küçük bir yükleniyor göstergesi; okunamazsa hiçbir şey gösterilmez (oyunu asla bozmasın).
// - Puanlıysa tebeşir çerçeveli kart: "+316 puan" ve "Sıralamaya bak →". Puanın nasıl hesaplandığı burada
//   gösterilmez, kural ekranında kısaca anlatılır.
// - Süresiz oynandıysa tek satır soluk açıklama.
// Kullanıcının ilk puanlı oyununda takma ad bir kez sorulur.
class PuanKarti extends ConsumerStatefulWidget {
  final String oyunTipi;

  const PuanKarti({super.key, required this.oyunTipi});

  @override
  ConsumerState<PuanKarti> createState() => _PuanKartiState();
}

class _PuanKartiState extends ConsumerState<PuanKarti> {
  bool _takmaAdBakildi = false;

  // Takma ad hiç seçilmediyse ve daha önce sorulmadıysa bir kez sorulur
  Future<void> _takmaAdiSor() async {
    final soru = ref.read(takmaAdSorusuProvider);
    try {
      if (await soru.soruldu()) return;
      final profil = await ref.read(oyunDeposuProvider).profilGetir();
      if (!profil.varsayilan || !mounted) return;
      await soru.isaretle();
      if (mounted) await takmaAdSayfasiniAc(context);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final durum = ref.watch(oyunPuaniProvider(widget.oyunTipi));
    final puan = durum?.value;

    if (durum == null || durum.hasError || (!durum.isLoading && puan == null)) return const SizedBox.shrink();

    if (durum.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: Center(
          child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Renkler.vurgu)),
        ),
      );
    }

    if (puan!.puansiz) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          puansizMetni(puan),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Renkler.metinSoluk, fontSize: 14, height: 1.4),
        ),
      );
    }

    if (!_takmaAdBakildi) {
      _takmaAdBakildi = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _takmaAdiSor());
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      decoration: BoxDecoration(
        color: Renkler.yuzey,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Renkler.kenar, width: 1.5),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('+${binlik(puan.puan!)}', style: Yazi.tebesir(44, renk: Renkler.vurgu)),
              const SizedBox(width: 8),
              Text('puan', style: Yazi.tebesir(18, renk: Renkler.metinIkincil, kalinlik: FontWeight.w400)),
            ],
          ),
          TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const LiderlikScreen(donem: LiderlikDonemi.gun)),
            ),
            style: TextButton.styleFrom(foregroundColor: Renkler.vurgu),
            child: const Text('Sıralamaya bak →'),
          ),
        ],
      ),
    );
  }
}

// Puansız bitişin açıklaması: süresiz oyun ya da cansız Top 10 (045)
String puansizMetni(PuanDetayi puan) => puan.suresiz
    ? 'Süresiz oynadın, bu oyun tabloya girmez.'
    : puan.cansiz
        ? 'Cansız oynadın, bu oyun tabloya girmez.'
        : 'Bu oyundan puan alamadın.';
