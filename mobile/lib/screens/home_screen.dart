import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/oyun_modu.dart';
import '../models/puan.dart';
import '../providers/hub_provider.dart';
import '../services/hatirlatma.dart';
import '../theme/renkler.dart';
import '../theme/yazi.dart';
import '../widgets/gunluk_kart.dart';
import '../widgets/izgara_zorluk_secimi.dart';
import '../widgets/kullanici_avatari.dart';
import '../widgets/oyun_karti.dart';
import '../widgets/logo.dart';
import '../widgets/tebesir.dart';
import 'bingo_screen.dart';
import 'bonservis_screen.dart';
import 'game_screen.dart';
import 'liderlik_screen.dart';
import 'profil_screen.dart';
import 'top10_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _modaTiklandi(BuildContext context, WidgetRef ref, OyunModu mod) async {
    // Her oyunda önce zorluk seçilir (bugün bir zorluk açıldıysa o açılır). Izgara'da zorluktan sonra süre de seçilir.
    final Widget Function(String oyunTipi, int? sure)? ekran = switch (mod.tip) {
      'kesisim' => (oyunTipi, sure) => GameScreen(oyunTipi: oyunTipi, sure: sure),
      'bonservis' => (oyunTipi, sure) => BonservisScreen(oyunTipi: oyunTipi, sure: sure),
      'bingo' => (oyunTipi, sure) => BingoScreen(oyunTipi: oyunTipi, sure: sure),
      'top10' => (oyunTipi, sure) => Top10Screen(oyunTipi: oyunTipi, sure: sure),
      _ => null,
    };
    if (mod.tip == 'izgara') return izgaraAc(context, ref);
    if (ekran != null) {
      return mod.zorluklu ? zorlukluOyunuAc(context, ref, mod, ekran) : tekModluOyunuAc(context, ref, mod, ekran);
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
    final bugunkuIzgara = ref.watch(bugunkuIzgaraProvider).value;
    final seri = ref.watch(seriProvider).value ?? 0;
    final bugunkuPuan = ref.watch(bugunkuPuanProvider).value ?? 0;

    // Seri ya da bugünkü sonuçlar değişince akşam hatırlatmaları yeniden kurulur
    ref.listen(seriProvider, (_, yeni) {
      final guncelSeri = yeni.value;
      if (guncelSeri == null) return;
      final bugunBitirdi = (ref.read(bugunOynananlarProvider).value ?? const {}).isNotEmpty;
      ref.read(hatirlatmaProvider).planla(seri: guncelSeri, bugunBitirdi: bugunBitirdi).catchError((_) {});
    });

    // Zorluklu oyunun bugün açılmış zorluğu (yarım ya da bitmiş)
    BugunkuMod? bugunku(OyunModu mod) {
      if (mod.tip == 'izgara') {
        return bugunkuIzgara == null ? null : (zorluk: bugunkuIzgara.zorluk.index, bitti: bugunkuIzgara.bitti);
      }
      // Zorluk modu olmayan oyunda da (Bingo) bugünkü kayıt okunur: yarım kalan oyunda "Devam et" yazar
      return mod.tip != null && mod.durum == OyunDurumu.aktif ? ref.watch(bugunkuModProvider(mod.tip!)).value : null;
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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Text(
                          kullanici != null ? 'Merhaba, ${kullanici.ilkAd}' : 'Merhaba',
                          style: Yazi.tebesir(26, kalinlik: FontWeight.w400),
                        ),
                      ),
                      if (bugunkuPuan > 0) BugunkuPuanRozeti(puan: bugunkuPuan),
                      if (seri > 0) SeriRozeti(seri: seri),
                    ],
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
      devamEdiyor: bugunku != null && !bugunku.bitti,
      onTap: () => _modaTiklandi(context, ref, mod),
    );
  }
}

// Logo ve profil fotoğrafı. Fotoğrafa dokununca hesap sayfası açılır (çıkış, gizlilik, hesap silme).
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
          tooltip: 'Sıralama',
          onPressed: () => liderligiAc(context),
          icon: const Icon(Icons.emoji_events_outlined, color: Renkler.metin, size: 26),
        ),
        IconButton(
          tooltip: 'Hesap',
          onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const ProfilScreen())),
          icon: KullaniciAvatari(kullanici: kullanici, yaricap: 17),
        ),
      ],
    );
  }
}

void liderligiAc(BuildContext context) =>
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const LiderlikScreen()));

// Bugün biten oyunların puan toplamı, tebeşirle "⭐ 316". Dokununca sıralama "Bugün" sekmesiyle açılır.
class BugunkuPuanRozeti extends StatelessWidget {
  final int puan;

  const BugunkuPuanRozeti({super.key, required this.puan});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Bugün $puan puan, sıralamayı aç',
      child: ExcludeSemantics(
        child: InkWell(
          onTap: () => liderligiAc(context),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 4),
            child: Text('⭐ ${binlik(puan)}', style: Yazi.tebesir(22, renk: Renkler.vurgu)),
          ),
        ),
      ),
    );
  }
}

// Seri: art arda oyun bitirilen gün sayısı, tebeşirle "🔥 6 gün". Puan değildir.
class SeriRozeti extends StatelessWidget {
  final int seri;

  const SeriRozeti({super.key, required this.seri});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$seri günlük seri',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 4),
          child: Text('🔥 $seri gün', style: Yazi.tebesir(22, renk: Renkler.vurgu)),
        ),
      ),
    );
  }
}
