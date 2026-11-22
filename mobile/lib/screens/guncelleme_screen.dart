import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/paylasim.dart';
import '../services/surum_kontrolu.dart';
import '../theme/renkler.dart';
import '../theme/yazi.dart';
import '../widgets/logo.dart';
import '../widgets/tebesir.dart';

// Açılışta, girişten önce sürüm kontrolü (041_yayin_oncesi.sql). Kontrol sürerken bekleme ekranı, güncelleme
// gerekiyorsa "Güncelleme gerekli" sayfası, değilse (ya da sunucuya ulaşılamadıysa) uygulamanın kendisi açılır.
class SurumKapisi extends ConsumerWidget {
  final Widget child;

  const SurumKapisi({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final durum = ref.watch(zorunluGuncellemeProvider);
    return durum.when(
      data: (mesaj) => mesaj == null ? child : GuncellemeScreen(mesaj: mesaj),
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => child,
    );
  }
}

// Tam ekran, kapatılamaz: geri tuşu çalışmaz, uygulamaya geçilemez. Tek çıkış yolu Play'den güncellemek.
class GuncellemeScreen extends ConsumerWidget {
  final String mesaj;

  const GuncellemeScreen({super.key, required this.mesaj});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopScope(
      canPop: false,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          body: TahtaZemini(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Spacer(flex: 3),
                    const Center(child: FootyLoreLogo(genislik: 240)),
                    const SizedBox(height: 40),
                    Text(
                      Yazi.buyuk('Güncelleme gerekli'),
                      textAlign: TextAlign.center,
                      style: Yazi.baslik(30, kalinlik: FontWeight.w900),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      mesaj,
                      textAlign: TextAlign.center,
                      style: Yazi.tebesir(20, renk: Renkler.metinIkincil, kalinlik: FontWeight.w400),
                    ),
                    const Spacer(flex: 4),
                    FilledButton.icon(
                      onPressed: () => _playiAc(context, ref),
                      icon: const Icon(Icons.system_update_rounded),
                      label: Text(Yazi.buyuk('Güncelle')),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _playiAc(BuildContext context, WidgetRef ref) async {
    final acildi = await ref.read(baglantiAciciProvider)(Uri.parse(playStoreLinki));
    if (!acildi && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Play Store açılamadı: $playStoreLinki')),
      );
    }
  }
}
