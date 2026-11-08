import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/izgara.dart';
import '../models/oyun_modu.dart';
import '../providers/hub_provider.dart';
import '../screens/izgara_screen.dart';
import '../theme/renkler.dart';
import '../theme/yazi.dart';
import 'tebesir.dart';

// Ana menüde Kesişim, Bonservis ya da Bingo kutucuğuna dokununca çağrılır. ekran, seçilen zorluğun oyun tipi ve süreyle
// oyun ekranını kurar.
// - Bugün bir zorluk açıldıysa sorulmadan o zorluk açılır: yarımsa sunucudaki kalan süresiyle kaldığı yerden,
//   bittiyse sonucuyla. Her oyunda günde tek zorluk oynanır, sunucu da buna izin vermez (019_zorluk_modlari.sql).
// - Yoksa önce zorluk, sonra süre seçilir ve oyun açılır.
// Dönünce ana menü tazelenir.
Future<void> zorlukluOyunuAc(
  BuildContext context,
  WidgetRef ref,
  OyunModu mod,
  Widget Function(String oyunTipi, int? sure) ekran,
) async {
  final oyun = mod.tip!;
  final altTipler = mod.altTipler!;
  int? zorluk;
  OyunSuresi sure = OyunSuresi.suresiz;

  try {
    zorluk = (await ref.read(bugunkuModProvider(oyun).future))?.zorluk;
  } catch (_) {
    // Bilinmiyorsa seçim gösterilir; sunucu ikinci bir zorluğun başlatılmasına zaten izin vermez
  }
  if (!context.mounted) return;

  if (zorluk == null) {
    final secim = await showModalBottomSheet<ZorlukSureSecimi>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => ZorlukSureSecimSayfasi(
        oyunAdi: mod.baslik,
        cizim: mod.cizim ?? TebesirCizimi.kesisim,
        zorluklar: [
          for (var i = 0; i < altTipler.length; i++) (ad: zorlukAdlari[i], aciklama: mod.zorlukAciklamalari?[i] ?? ''),
        ],
      ),
    );
    if (secim == null || !context.mounted) return;
    zorluk = secim.zorluk!;
    sure = secim.sure;
  }

  final oyunTipi = altTipler[zorluk];
  await Navigator.push(context, MaterialPageRoute(builder: (context) => ekran(oyunTipi, sure.saniye)));
  if (!context.mounted) return;
  ref.invalidate(bugunOynananlarProvider);
  ref.invalidate(bugunkuModProvider(oyun));
}

// Ana menüde Izgara kutucuğuna dokununca çağrılır.
// - Bugün bir tahtaya başlandıysa sorulmadan o tahta açılır: yarımsa kaldığı yerden (sunucudaki kalan süresiyle),
//   bittiyse sonucuyla. Zorluklu oyunlarda günde tek zorluk oynanır, sunucu da buna izin vermez (019).
// - Yoksa önce zorluk, sonra süre seçilir ve tahta açılır.
// Dönünce ana menü tazelenir.
Future<void> izgaraAc(BuildContext context, WidgetRef ref) async {
  IzgaraZorlugu? acilacak;
  OyunSuresi sure = OyunSuresi.suresiz;

  try {
    acilacak = (await ref.read(bugunkuIzgaraProvider.future))?.zorluk;
  } catch (_) {
    // Bilinmiyorsa seçim gösterilir; sunucu ikinci bir Izgara'nın başlatılmasına zaten izin vermez
  }
  if (!context.mounted) return;

  if (acilacak == null) {
    final secim = await showModalBottomSheet<ZorlukSureSecimi>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => ZorlukSureSecimSayfasi(
        oyunAdi: 'Izgara',
        cizim: TebesirCizimi.izgara,
        zorluklar: [for (final z in IzgaraZorlugu.values) (ad: z.ad, aciklama: z.aciklama)],
      ),
    );
    if (secim == null || !context.mounted) return;
    acilacak = IzgaraZorlugu.values[secim.zorluk!];
    sure = secim.sure;
  }

  final zorluk = acilacak;
  await Navigator.push(context, MaterialPageRoute(builder: (context) => IzgaraScreen(zorluk: zorluk, sure: sure.saniye)));
  if (!context.mounted) return;
  ref.invalidate(bugunOynananlarProvider);
  ref.invalidate(bugunkuModProvider('izgara'));
  ref.invalidate(bugunkuIzgaraProvider);
}

// Seçim sayfasının sonucu: zorluğun sırası (0 kolay, 1 orta, 2 zor; zorluksuz oyunda null) ve süre
typedef ZorlukSureSecimi = ({int? zorluk, OyunSuresi sure});

// Oyun başlamadan açılan alt sayfa. Zorluklu oyunda (Izgara) iki adımlıdır: önce 3 zorluktan biri,
// sonra 4 süreden biri. Zorluksuz oyunda (Kesişim, Bonservis) sadece süre seçilir.
class ZorlukSureSecimSayfasi extends StatefulWidget {
  final String oyunAdi;
  final TebesirCizimi cizim;
  final List<({String ad, String aciklama})>? zorluklar; // null: zorluksuz oyun

  const ZorlukSureSecimSayfasi({super.key, required this.oyunAdi, required this.cizim, this.zorluklar});

  @override
  State<ZorlukSureSecimSayfasi> createState() => _ZorlukSureSecimSayfasiState();
}

class _ZorlukSureSecimSayfasiState extends State<ZorlukSureSecimSayfasi> {
  int? _zorluk;
  OyunSuresi? _sure;

  @override
  Widget build(BuildContext context) {
    final zorluk = _zorluk;
    final zorluksuz = widget.zorluklar == null;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: zorluksuz || zorluk != null ? _sureAdimi(zorluk) : _zorlukAdimi(),
          ),
        ),
      ),
    );
  }

  Widget _baslik({required String aciklama, String? secilenZorluk}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TebesirIkonu(cizim: widget.cizim, boyut: 38),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(child: Text(Yazi.buyuk(widget.oyunAdi), style: Yazi.baslik(26, kalinlik: FontWeight.w900))),
                  if (secilenZorluk != null) ...[
                    const SizedBox(width: 8),
                    TebesirEtiket(secilenZorluk, secili: true),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(aciklama, style: const TextStyle(color: Renkler.metinIkincil, fontSize: 13.5, height: 1.35)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _adim(String metin) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 10),
        child: Text(Yazi.buyuk(metin), style: Yazi.etiket(renk: Renkler.vurgu)),
      );

  Widget _zorlukAdimi() {
    final zorluklar = widget.zorluklar!;
    return Column(
      key: const ValueKey('zorluk'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _baslik(aciklama: 'Bugün yalnızca bir zorluk oynayabilirsin.'),
        _adim('1 · Zorluk seç'),
        for (var i = 0; i < zorluklar.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _SecimSatiri(
            baslik: zorluklar[i].ad,
            aciklama: zorluklar[i].aciklama,
            onTap: () => setState(() => _zorluk = i),
          ),
        ],
      ],
    );
  }

  Widget _sureAdimi(int? zorluk) {
    final sure = _sure;
    final zorlukAdi = zorluk == null ? null : widget.zorluklar![zorluk].ad;

    Widget sureKutusu(OyunSuresi s) {
      final secili = s == sure;
      final saniye = s.saniye;
      return Expanded(
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () => setState(() => _sure = s),
            borderRadius: BorderRadius.circular(6),
            child: TebesirKutusu(
              kenarRengi: secili ? Renkler.vurgu : Renkler.kenar,
              dolgu: secili ? Renkler.vurgu.withValues(alpha: 0.08) : null,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(saniye == null ? '∞' : '$saniye', style: Yazi.tebesir(30, renk: secili ? Renkler.vurgu : Renkler.metin)),
                  const SizedBox(width: 6),
                  Text(Yazi.buyuk(saniye == null ? 'süresiz' : 'saniye'), style: Yazi.etiket(boyut: 10)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      key: const ValueKey('sure'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _baslik(aciklama: 'Süreyi seç, sonra başla.', secilenZorluk: zorlukAdi),
        if (zorlukAdi != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() {
                _zorluk = null;
                _sure = null;
              }),
              style: TextButton.styleFrom(foregroundColor: Renkler.metinIkincil, padding: EdgeInsets.zero),
              child: const Text('← Zorluğu değiştir'),
            ),
          ),
        _adim(zorlukAdi == null ? 'Süre seç' : '2 · Süre seç'),
        Row(children: [sureKutusu(OyunSuresi.values[0]), const SizedBox(width: 8), sureKutusu(OyunSuresi.values[1])]),
        const SizedBox(height: 8),
        Row(children: [sureKutusu(OyunSuresi.values[2]), const SizedBox(width: 8), sureKutusu(OyunSuresi.values[3])]),
        const SizedBox(height: 14),
        Text(
          zorlukAdi == null
              ? 'Süre bütün sorular içindir ve oyundan çıksan da işler. Süre bitmediyse kaldığın yerden devam edersin.'
              : 'Başladıktan sonra bugün başka zorluk ya da süre seçilemez. Süre oyundan çıksan da işler; '
                  'bitmediyse kaldığın yerden devam edersin.',
          style: const TextStyle(color: Renkler.metinSoluk, fontSize: 12.5, height: 1.35),
        ),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: sure == null ? null : () => Navigator.pop(context, (zorluk: zorluk, sure: sure)),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          child: Text(
            sure == null
                ? 'SÜRE SEÇ'
                : Yazi.buyuk(zorlukAdi == null ? '${sure.ad} başla' : '$zorlukAdi · ${sure.ad} başla'),
          ),
        ),
      ],
    );
  }
}

class _SecimSatiri extends StatelessWidget {
  final String baslik;
  final String aciklama;
  final VoidCallback onTap;

  const _SecimSatiri({required this.baslik, required this.aciklama, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: TebesirKutusu(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(Yazi.buyuk(baslik), style: Yazi.baslik(19)),
                    const SizedBox(height: 4),
                    Text(aciklama, style: const TextStyle(color: Renkler.metinIkincil, fontSize: 12.5)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text('→', style: Yazi.tebesir(20, renk: Renkler.metinIkincil)),
            ],
          ),
        ),
      ),
    );
  }
}
