import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/oyun_modu.dart';
import '../providers/hub_provider.dart';
import '../services/auth_service.dart';
import '../theme/renkler.dart';
import '../theme/yazi.dart';
import '../widgets/gunluk_kart.dart';
import '../widgets/izgara_zorluk_secimi.dart';
import '../widgets/oyun_karti.dart';
import '../widgets/logo.dart';
import '../widgets/tebesir.dart';
import 'bonservis_screen.dart';
import 'game_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _modaTiklandi(BuildContext context, WidgetRef ref, OyunModu mod) async {
    // Her oyunda önce zorluk seçilir (bugün bir zorluk açıldıysa o açılır). Izgara'da zorluktan sonra süre de seçilir.
    final Widget Function(String oyunTipi, int? sure)? ekran = switch (mod.tip) {
      'kesisim' => (oyunTipi, sure) => GameScreen(oyunTipi: oyunTipi, sure: sure),
      'bonservis' => (oyunTipi, sure) => BonservisScreen(oyunTipi: oyunTipi, sure: sure),
      _ => null,
    };
    if (mod.tip == 'izgara') return izgaraAc(context, ref);
    if (ekran != null) return zorlukluOyunuAc(context, ref, mod, ekran);

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('${mod.baslik} henüz hazır değil.')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final oynananlar = ref.watch(bugunOynananlarProvider);
    final skorlar = oynananlar.hasValue ? oynananlar.requireValue : const <String, int>{};
    final kullanici = ref.watch(kullaniciProvider);
    final bugunkuIzgara = ref.watch(bugunkuIzgaraProvider).value;

    // Zorluklu oyunun bugün açılmış zorluğu (yarım ya da bitmiş)
    BugunkuMod? bugunku(OyunModu mod) {
      if (mod.tip == 'izgara') {
        return bugunkuIzgara == null ? null : (zorluk: bugunkuIzgara.zorluk.index, bitti: bugunkuIzgara.bitti);
      }
      return mod.zorluklu ? ref.watch(bugunkuModProvider(mod.tip!)).value : null;
    }

    // Oynanabilenler önce, yakındakiler en sonda; hepsi tek bir ızgarada, kategorisiz
    final modlar = [
      ...oyunModlari.where((m) => m.durum != OyunDurumu.yakinda),
      ...oyunModlari.where((m) => m.durum == OyunDurumu.yakinda),
    ];

    // İlerleme oyun sayar: zorluklu bir oyunda herhangi bir zorluk bittiyse o oyun bugünlük bitmiştir
    final aktifModlar = oyunModlari.where((m) => m.durum == OyunDurumu.aktif).toList();
    final tamamlanan = aktifModlar.where((m) => m.oyunTipleri.any(skorlar.containsKey)).length;

    final kutucuklar = [
      for (final mod in modlar) _kutucuk(context, ref, mod, skorlar, bugunku(mod)),
    ];

    // Ana menüde AppBar yok: durum çubuğu simgelerinin koyu zeminde açık renk olduğunu kendimiz söylüyoruz
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: TahtaZemini(
          child: SafeArea(
            child: RefreshIndicator(
              color: Renkler.vurgu,
              backgroundColor: Renkler.yuzey,
              onRefresh: () {
                ref.invalidate(bugunkuModProvider);
                ref.invalidate(bugunkuIzgaraProvider);
                return ref.refresh(bugunOynananlarProvider.future);
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 32),
                children: [
                  _UstBar(kullanici: kullanici),
                  const SizedBox(height: 14),
                  Text(
                    kullanici != null ? 'Merhaba, ${kullanici.ilkAd}' : 'Merhaba',
                    style: Yazi.tebesir(26, kalinlik: FontWeight.w400),
                  ),
                  const SizedBox(height: 16),
                  GunlukSerit(tamamlanan: tamamlanan, toplam: aktifModlar.length),
                  const SizedBox(height: 18),
                  // İki sütunlu ızgara: yan yana iki kutucuk aynı boyda durur
                  for (var i = 0; i < kutucuklar.length; i += 2)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: kutucuklar[i]),
                            const SizedBox(width: 10),
                            Expanded(child: i + 1 < kutucuklar.length ? kutucuklar[i + 1] : const SizedBox()),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 14),
                  Text(
                    'gece yarısı tahta silinir, yeni oyunlar yazılır',
                    textAlign: TextAlign.center,
                    style: Yazi.tebesir(15, renk: Renkler.metinSoluk, kalinlik: FontWeight.w400),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _kutucuk(
    BuildContext context,
    WidgetRef ref,
    OyunModu mod,
    Map<String, int> skorlar,
    BugunkuMod? bugunku,
  ) {
    if (mod.zorluklu) {
      // Zorluklu oyunda günde tek zorluk oynanır: bugün açılan zorluk kutucukta gösterilir.
      // Yarım kalan oyunda "Devam et", bitmiş oyunda o zorluğun skoru yazar.
      final altTipler = mod.altTipler!;
      final devamEdiyor = bugunku != null && !bugunku.bitti;
      final oynanan = devamEdiyor ? -1 : altTipler.indexWhere(skorlar.containsKey);
      return OyunKarti(
        mod: mod,
        bugunkuSkor: oynanan >= 0 ? skorlar[altTipler[oynanan]] : null,
        oynananZorluk: oynanan >= 0 ? zorlukAdlari[oynanan] : (bugunku != null ? zorlukAdlari[bugunku.zorluk] : null),
        devamEdiyor: devamEdiyor,
        onTap: () => _modaTiklandi(context, ref, mod),
      );
    }
    return OyunKarti(
      mod: mod,
      bugunkuSkor: skorlar[mod.tip],
      onTap: () => _modaTiklandi(context, ref, mod),
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
        const FootyLoreLogo(),
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
        title: const Text('Çıkış yapılsın mı?'),
        content: const Text('Tekrar oynamak için Google hesabınla yeniden giriş yapman gerekecek.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(foregroundColor: Renkler.metinIkincil),
            child: const Text('Vazgeç'),
          ),
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
    // Tebeşirle çizilmiş çerçeve
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Renkler.kenar, width: 1.5)),
      child: avatar,
    );
  }
}
