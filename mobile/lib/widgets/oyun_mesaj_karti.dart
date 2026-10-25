import 'package:flutter/material.dart';
import '../theme/renkler.dart';

// Oyun ekranlarında oyun yerine gösterilen durum mesajı (oyun yok, bugün oynandı, bağlantı sorunu...)
class OyunMesajKarti extends StatelessWidget {
  final IconData ikon;
  final String baslik;
  final String aciklama;
  final VoidCallback? onTekrarDene; // Doluysa ana menü butonunun yanında "Tekrar dene" de çıkar

  const OyunMesajKarti({
    super.key,
    required this.ikon,
    required this.baslik,
    required this.aciklama,
    this.onTekrarDene,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(color: Renkler.yuzey, shape: BoxShape.circle),
              child: Icon(ikon, size: 32, color: Renkler.metinIkincil),
            ),
            const SizedBox(height: 20),
            Text(
              baslik,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Renkler.metin),
            ),
            const SizedBox(height: 8),
            Text(
              aciklama,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, height: 1.4, color: Renkler.metinIkincil),
            ),
            const SizedBox(height: 28),
            if (onTekrarDene != null) ...[
              FilledButton(
                onPressed: onTekrarDene,
                style: FilledButton.styleFrom(minimumSize: const Size(200, 48)),
                child: const Text('Tekrar dene', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 8),
            ],
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(foregroundColor: Renkler.metinIkincil, minimumSize: const Size(200, 48)),
              child: const Text('Ana menüye dön'),
            ),
          ],
        ),
      ),
    );
  }
}
