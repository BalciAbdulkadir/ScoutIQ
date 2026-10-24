import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/oyun_modu.dart';
import '../providers/hub_provider.dart';
import '../services/auth_service.dart';
import '../theme/renkler.dart';
import '../widgets/gunluk_kart.dart';
import '../widgets/oyun_karti.dart';
import 'game_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _modaTiklandi(BuildContext context, WidgetRef ref, OyunModu mod) async {
    if (mod.tip == 'kesisim') {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const GameScreen()),
      );
      // Oyundan dönünce skoru ve "tamamlandı" durumunu tazeleyelim
      if (!context.mounted) return;
      ref.invalidate(bugunOynananlarProvider);
      return;
    }

    final mesaj = mod.durum == OyunDurumu.hazirlaniyor
        ? '${mod.baslik} hazırlanıyor, çok yakında burada!'
        : 'Bu mod henüz aktif değil!';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mesaj)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final oynananlar = ref.watch(bugunOynananlarProvider);
    final skorlar = oynananlar.hasValue ? oynananlar.requireValue : const <String, int>{};

    final gunlukModlar = oyunModlari.where((m) => m.durum != OyunDurumu.yakinda).toList();
    final yakindakiModlar = oyunModlari.where((m) => m.durum == OyunDurumu.yakinda).toList();

    // İlerleme sadece şu an oynanabilen modlar üzerinden hesaplanır
    final aktifModlar = oyunModlari.where((m) => m.durum == OyunDurumu.aktif);
    final tamamlanan = aktifModlar.where((m) => skorlar.containsKey(m.tip)).length;

    return Scaffold(
      backgroundColor: Renkler.arkaPlan,
      body: SafeArea(
        child: RefreshIndicator(
          color: Renkler.vurgu,
          backgroundColor: Renkler.kart,
          onRefresh: () => ref.refresh(bugunOynananlarProvider.future),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              const _UstBar(),
              const SizedBox(height: 24),
              GunlukKart(tamamlanan: tamamlanan, toplam: aktifModlar.length),
              const SizedBox(height: 32),
              const _BolumBasligi('Bugünün Oyunları'),
              const SizedBox(height: 12),
              for (final mod in gunlukModlar)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: OyunKarti(
                    mod: mod,
                    bugunkuSkor: skorlar[mod.tip],
                    onTap: () => _modaTiklandi(context, ref, mod),
                  ),
                ),
              const SizedBox(height: 20),
              const _BolumBasligi('Yakında'),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.95,
                children: [
                  for (final mod in yakindakiModlar)
                    YakindaKarti(mod: mod, onTap: () => _modaTiklandi(context, ref, mod)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Kullanıcının Google fotoğrafı, adı ve çıkış butonu
class _UstBar extends StatelessWidget {
  const _UstBar();

  @override
  Widget build(BuildContext context) {
    final kullanici = Supabase.instance.client.auth.currentUser;
    final bilgiler = kullanici?.userMetadata ?? const {};
    final tamAd = (bilgiler['full_name'] ?? bilgiler['name'] ?? kullanici?.email?.split('@').first ?? 'Futbolsever') as String;
    final ad = tamAd.split(' ').first;
    final fotoUrl = (bilgiler['avatar_url'] ?? bilgiler['picture']) as String?;

    return Row(
      children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: Renkler.kart,
          foregroundImage: fotoUrl != null ? NetworkImage(fotoUrl) : null,
          onForegroundImageError: fotoUrl != null ? (_, _) {} : null,
          child: Text(
            ad.isNotEmpty ? ad[0].toUpperCase() : '?',
            style: const TextStyle(color: Renkler.vurgu, fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Tekrar hoş geldin', style: TextStyle(color: Renkler.soluk, fontSize: 13)),
              Text(
                ad,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        const Row(
          children: [
            Icon(Icons.sports_soccer, color: Renkler.vurgu, size: 20),
            SizedBox(width: 6),
            Text(
              'ScoutIQ',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1),
            ),
          ],
        ),
        IconButton(
          tooltip: 'Çıkış yap',
          icon: const Icon(Icons.logout, color: Renkler.soluk),
          onPressed: () async {
            await AuthService().signOut();
          },
        ),
      ],
    );
  }
}

class _BolumBasligi extends StatelessWidget {
  final String metin;

  const _BolumBasligi(this.metin);

  @override
  Widget build(BuildContext context) {
    return Text(
      metin,
      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
    );
  }
}
