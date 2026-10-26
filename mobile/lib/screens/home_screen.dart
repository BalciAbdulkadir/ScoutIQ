import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/oyun_modu.dart';
import '../providers/hub_provider.dart';
import '../services/auth_service.dart';
import '../theme/renkler.dart';
import '../widgets/gunluk_kart.dart';
import '../widgets/oyun_karti.dart';
import 'bonservis_screen.dart';
import 'game_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _modaTiklandi(BuildContext context, WidgetRef ref, OyunModu mod) async {
    final Widget? oyunEkrani = switch (mod.tip) {
      'kesisim' => const GameScreen(),
      'bonservis' => const BonservisScreen(),
      _ => null,
    };

    if (oyunEkrani != null) {
      await Navigator.push(context, MaterialPageRoute(builder: (context) => oyunEkrani));
      // Oyundan dönünce skoru ve "tamamlandı" durumunu tazeleyelim
      if (!context.mounted) return;
      ref.invalidate(bugunOynananlarProvider);
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('${mod.baslik} henüz hazır değil.')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final oynananlar = ref.watch(bugunOynananlarProvider);
    final skorlar = oynananlar.hasValue ? oynananlar.requireValue : const <String, int>{};
    final kullanici = ref.watch(kullaniciProvider);

    final gunlukModlar = oyunModlari.where((m) => m.durum != OyunDurumu.yakinda).toList();
    final yakindakiModlar = oyunModlari.where((m) => m.durum == OyunDurumu.yakinda).toList();

    // İlerleme sadece şu an oynanabilen modlar üzerinden hesaplanır
    final aktifModlar = oyunModlari.where((m) => m.durum == OyunDurumu.aktif);
    final tamamlanan = aktifModlar.where((m) => skorlar.containsKey(m.tip)).length;

    // Ana menüde AppBar yok: durum çubuğu simgelerinin koyu zeminde açık renk olduğunu kendimiz söylüyoruz
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: SafeArea(
          child: RefreshIndicator(
            color: Renkler.basari,
            backgroundColor: Renkler.yuzey,
            onRefresh: () => ref.refresh(bugunOynananlarProvider.future),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                _UstBar(kullanici: kullanici),
                const SizedBox(height: 24),
                Text(
                  kullanici != null ? 'Merhaba, ${kullanici.ilkAd}' : 'Merhaba',
                  style: const TextStyle(color: Renkler.metin, fontSize: 26, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(tarihMetni(turkiyeSaati()), style: const TextStyle(color: Renkler.metinIkincil, fontSize: 15)),
                const SizedBox(height: 20),
                GunlukKart(tamamlanan: tamamlanan, toplam: aktifModlar.length),
                const SizedBox(height: 28),
                const _BolumBasligi('Oyunlar'),
                for (final mod in gunlukModlar)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: OyunKarti(
                      mod: mod,
                      bugunkuSkor: skorlar[mod.tip],
                      onTap: () => _modaTiklandi(context, ref, mod),
                    ),
                  ),
                if (yakindakiModlar.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const _BolumBasligi('Yakında'),
                  YakindaListesi(modlar: yakindakiModlar),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Logo ve profil fotoğrafı. Fotoğrafa dokununca hesap menüsü açılır.
class _UstBar extends StatelessWidget {
  final KullaniciBilgisi? kullanici;

  const _UstBar({required this.kullanici});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.sports_soccer, color: Renkler.basari, size: 22),
        const SizedBox(width: 8),
        const Text(
          'ScoutIQ',
          style: TextStyle(color: Renkler.metin, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 0.3),
        ),
        const Spacer(),
        IconButton(
          tooltip: 'Hesap',
          onPressed: () => _hesapMenusunuAc(context),
          icon: _Avatar(kullanici: kullanici, yaricap: 17),
        ),
      ],
    );
  }

  void _hesapMenusunuAc(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Renkler.yuzey,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: _Avatar(kullanici: kullanici, yaricap: 20),
                title: Text(
                  kullanici?.ad ?? '',
                  style: const TextStyle(color: Renkler.metin, fontWeight: FontWeight.w600),
                ),
                subtitle: kullanici?.eposta != null
                    ? Text(kullanici!.eposta!, style: const TextStyle(color: Renkler.metinIkincil))
                    : null,
              ),
              const Divider(indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.logout_rounded, color: Renkler.hata),
                title: const Text(
                  'Çıkış yap',
                  style: TextStyle(color: Renkler.hata, fontWeight: FontWeight.w600),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  if (await _cikisOnayla(context)) {
                    await AuthService().signOut();
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _cikisOnayla(BuildContext context) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Renkler.yuzey,
        title: const Text('Çıkış yapılsın mı?', style: TextStyle(color: Renkler.metin)),
        content: const Text(
          'Tekrar oynamak için Google hesabınla yeniden giriş yapman gerekecek.',
          style: TextStyle(color: Renkler.metinIkincil),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Renkler.hata),
            child: const Text('Çıkış yap'),
          ),
        ],
      ),
    );
    return onay ?? false;
  }
}

class _Avatar extends StatelessWidget {
  final KullaniciBilgisi? kullanici;
  final double yaricap;

  const _Avatar({required this.kullanici, required this.yaricap});

  @override
  Widget build(BuildContext context) {
    final fotoUrl = kullanici?.fotoUrl;
    final ad = kullanici?.ilkAd ?? '';

    return CircleAvatar(
      radius: yaricap,
      backgroundColor: Renkler.yuzeyYuksek,
      foregroundImage: fotoUrl != null ? NetworkImage(fotoUrl) : null,
      onForegroundImageError: fotoUrl != null ? (_, _) {} : null,
      child: Text(
        ad.isNotEmpty ? ad[0].toUpperCase() : '?',
        style: TextStyle(color: Renkler.basari, fontWeight: FontWeight.w700, fontSize: yaricap * 0.8),
      ),
    );
  }
}

class _BolumBasligi extends StatelessWidget {
  final String metin;

  const _BolumBasligi(this.metin);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 10),
      child: Text(
        metin.toUpperCase(),
        style: const TextStyle(
          color: Renkler.metinSoluk,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
