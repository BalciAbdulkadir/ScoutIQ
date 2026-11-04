import 'package:flutter/material.dart';
import '../models/izgara.dart';
import '../theme/renkler.dart';
import '../widgets/oyun_ortak.dart';
import 'izgara_screen.dart';

// Zorluk seçildikten sonra açılan süre seçimi. Seçilen süreyle geri döner (IzgaraAcilisi), geri tuşunda null.
// Süre bütün tahta içindir ve oyun başlayınca değiştirilemez.
class IzgaraSureScreen extends StatelessWidget {
  final IzgaraZorlugu zorluk;

  const IzgaraSureScreen({super.key, required this.zorluk});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Flexible(child: Text('Izgara', overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 10),
            OyunEtiketi(metin: zorluk.ad, renk: IzgaraScreen.zorlukRengi(zorluk)),
          ],
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            const Text(
              'Süreni seç',
              style: TextStyle(color: Renkler.metin, fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              'Süre bütün tahta için geçerli. Oyun başlayınca değiştirilemez; süre dolunca tahta o anki skorunla kapanır.',
              style: TextStyle(color: Renkler.metinIkincil, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 20),
            for (final sure in izgaraSureleri) ...[
              _SureKarti(
                sure: sure,
                onTap: () => Navigator.pop<IzgaraAcilisi>(context, (zorluk: zorluk, sure: sure)),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _SureKarti extends StatelessWidget {
  final int? sure;
  final VoidCallback onTap;

  const _SureKarti({required this.sure, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final sureli = sure != null;

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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Renkler.izgara.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(sureli ? Icons.timer_outlined : Icons.all_inclusive_rounded, color: Renkler.izgara),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sureli ? '$sure saniye' : 'Süre yok',
                      style: const TextStyle(color: Renkler.metin, fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      sureli ? 'Bütün tahtayı $sure saniyede doldur.' : 'Acele yok, istediğin kadar düşün.',
                      style: const TextStyle(color: Renkler.metinIkincil, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded, color: Renkler.metinIkincil),
            ],
          ),
        ),
      ),
    );
  }
}
