import 'package:flutter/material.dart';
import '../providers/hub_provider.dart';
import '../theme/renkler.dart';
import '../theme/yazi.dart';

// Google hesabının fotoğrafı; yoksa ya da yüklenemezse adın baş harfi. Tebeşirle çizilmiş çerçeve içinde.
class KullaniciAvatari extends StatelessWidget {
  final KullaniciBilgisi? kullanici;
  final double yaricap;

  const KullaniciAvatari({super.key, required this.kullanici, required this.yaricap});

  @override
  Widget build(BuildContext context) {
    final fotoUrl = kullanici?.fotoUrl;
    final ad = kullanici?.ilkAd ?? '';

    final avatar = CircleAvatar(
      radius: yaricap,
      backgroundColor: Renkler.yuzey,
      foregroundImage: fotoUrl != null ? NetworkImage(fotoUrl) : null,
      onForegroundImageError: fotoUrl != null ? (_, _) {} : null,
      child: Text(
        ad.isNotEmpty ? ad[0].toUpperCase() : '?',
        style: Yazi.baslik(yaricap * 0.9, kalinlik: FontWeight.w800),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Renkler.kenar, width: 1.5)),
      child: avatar,
    );
  }
}
