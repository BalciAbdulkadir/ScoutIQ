import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/hatirlatma.dart';
import '../theme/renkler.dart';
import '../theme/yazi.dart';

// Bildirim izni. Android'in kendi izin penceresi (Android 13+) uygulamanın temasını almaz; o yüzden kullanıcı önce
// tahta temalı bu sayfayı görür, sistem penceresi sadece "Bildirimleri aç"a dokununca açılır.
// Ana menü, bugün bir oyun bitmişse (ilk biten oyundan sonra) bir kez çağırır. Sayfa açılmaz:
//   - hatırlatma Hesap sayfasında kapatıldıysa,
//   - daha önce sorulduysa,
//   - telefon zaten izin veriyorsa (Android 12 ve öncesi, ya da izin önceden verilmiş). Bu durumda sorulmuş sayılır.
// "Şimdi değil" ya da sayfayı aşağı kaydırmak da sorulmuş sayılır; izin sonra Hesap sayfasındaki anahtarla istenir.

// Ana menü her çizimde çağırabilir: bu oturumda bakıldıysa hemen döner, bakılırken ikinci kez açılmaz
bool _bakiliyor = false;
bool _bakildi = false;

@visibleForTesting
void bildirimIzniBakildiSifirla() => _bakildi = false;

Future<void> bildirimIzniniSor(BuildContext context, WidgetRef ref) async {
  if (_bakiliyor || _bakildi) return;
  _bakiliyor = true;
  try {
    final hatirlatma = ref.read(hatirlatmaProvider);
    _bakildi = true;
    if (!await hatirlatma.acikMi() || await hatirlatma.izinSoruldu()) return;
    if (await hatirlatma.izinVar()) {
      await hatirlatma.izinSorulduIsaretle();
      return;
    }
    if (!context.mounted) {
      _bakildi = false; // Ana menü kapandı: bir dahaki açılışta sorulur
      return;
    }

    unawaited(hatirlatma.izinSorulduIsaretle()); // Sayfa bir kez gösterilir; nasıl kapanırsa kapansın sorulmuş sayılır
    final ac = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const BildirimIzniSayfasi(),
    );
    if (ac == true) await hatirlatma.izinIste();
  } catch (_) {
    // İzin sorusu ana menüyü asla bozmasın
  } finally {
    _bakiliyor = false;
  }
}

class BildirimIzniSayfasi extends StatelessWidget {
  const BildirimIzniSayfasi({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(Yazi.buyuk('Serini kaçırma'), style: Yazi.baslik(26, kalinlik: FontWeight.w900)),
            const SizedBox(height: 10),
            const Text(
              "O gün hiç oynamadıysan akşam 20.00'de tek bir hatırlatma gönderelim. Başka bildirim yok.",
              style: TextStyle(color: Renkler.metinIkincil, fontSize: 15, height: 1.4),
            ),
            const SizedBox(height: 16),
            const _OrnekBildirim(),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: Text(Yazi.buyuk('Bildirimleri aç')),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              style: TextButton.styleFrom(foregroundColor: Renkler.metinIkincil, minimumSize: const Size.fromHeight(44)),
              child: const Text('Şimdi değil'),
            ),
            const SizedBox(height: 2),
            const Text(
              "Sonra telefonun izin penceresi açılır, oradan 'İzin ver'e dokun. Hesap sayfasından istediğin zaman kapatabilirsin.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Renkler.metinSoluk, fontSize: 12.5, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

// Gelecek bildirimin tahta üstünde çizilmiş örneği: simgesi ve metni gerçek bildirimle aynıdır
class _OrnekBildirim extends StatelessWidget {
  const _OrnekBildirim();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      decoration: BoxDecoration(
        color: Renkler.yuzeyYuksek,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Renkler.kenar, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: bildirimRengi,
              shape: BoxShape.circle,
              border: Border.all(color: Renkler.kenar),
            ),
            child: const Icon(Icons.sports_soccer, size: 22, color: Renkler.metin),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Flexible(
                      child: Text(
                        'FootyLore',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Renkler.metin, fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('· 20:00', style: TextStyle(color: Renkler.metinSoluk.withValues(alpha: 0.9), fontSize: 12.5)),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  hatirlatmaMetni(null),
                  style: const TextStyle(color: Renkler.metinIkincil, fontSize: 13.5, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
