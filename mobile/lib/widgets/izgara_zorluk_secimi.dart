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
        sureler: mod.sureSecenekleri,
        onizleme: mod.onizleme,
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

// Ana menüde zorluk modu olmayan bir oyunun (Bingo) kutucuğuna dokununca çağrılır.
// - Bugün başlandıysa sorulmadan açılır: yarımsa sunucudaki kalan süresiyle kaldığı yerden, bittiyse sonucuyla.
// - Yoksa sadece süre seçilir (oyunun süre seçenekleriyle) ve oyun açılır.
// Dönünce ana menü tazelenir.
Future<void> tekModluOyunuAc(
  BuildContext context,
  WidgetRef ref,
  OyunModu mod,
  Widget Function(String oyunTipi, int? sure) ekran,
) async {
  final oyunTipi = mod.tip!;
  var sure = OyunSuresi.suresiz;
  bool baslandi;

  try {
    baslandi = await ref.read(bugunkuModProvider(oyunTipi).future) != null;
  } catch (_) {
    baslandi = false; // Bilinmiyorsa seçim gösterilir; başlanmış oyunda sunucudaki süre geçerli olur
  }
  if (!context.mounted) return;

  if (!baslandi) {
    final secim = await showModalBottomSheet<ZorlukSureSecimi>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => ZorlukSureSecimSayfasi(
        oyunAdi: mod.baslik,
        cizim: mod.cizim ?? TebesirCizimi.kesisim,
        sureler: mod.sureSecenekleri,
        onizleme: mod.onizleme,
      ),
    );
    if (secim == null || !context.mounted) return;
    sure = secim.sure;
  }

  await Navigator.push(context, MaterialPageRoute(builder: (context) => ekran(oyunTipi, sure.saniye)));
  if (!context.mounted) return;
  ref.invalidate(bugunOynananlarProvider);
  ref.invalidate(bugunkuModProvider(oyunTipi));
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
        onizleme: oyunModlari.firstWhere((m) => m.tip == 'izgara').onizleme,
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

// Oyun başlamadan açılan alt sayfa. Önizleme verildiyse önce oyunun kuralları gösterilir.
// Zorluklu oyunda sonra 3 zorluktan biri, ardından süre seçilir. Zorluksuz oyunda (Bingo) sadece süre seçilir.
class ZorlukSureSecimSayfasi extends StatefulWidget {
  final String oyunAdi;
  final TebesirCizimi cizim;
  final List<({String ad, String aciklama})>? zorluklar; // null: zorluksuz oyun
  final List<OyunSuresi> sureler; // Seçilebilen süreler
  final OyunOnizlemesi? onizleme; // Doluysa sayfa kurallarla açılır

  const ZorlukSureSecimSayfasi({
    super.key,
    required this.oyunAdi,
    required this.cizim,
    this.zorluklar,
    this.sureler = OyunSuresi.values,
    this.onizleme,
  });

  @override
  State<ZorlukSureSecimSayfasi> createState() => _ZorlukSureSecimSayfasiState();
}

class _ZorlukSureSecimSayfasiState extends State<ZorlukSureSecimSayfasi> {
  int? _zorluk;
  OyunSuresi? _sure;
  late bool _onizlemede = widget.onizleme != null;

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
            child: _onizlemede
                ? _onizlemeAdimi(widget.onizleme!)
                : zorluksuz || zorluk != null
                    ? _sureAdimi(zorluk)
                    : _zorlukAdimi(),
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

  // Seçim adımından kurallara geri dönüş
  Widget _kurallaraDon() {
    if (widget.onizleme == null) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        onPressed: () => setState(() => _onizlemede = true),
        style: TextButton.styleFrom(foregroundColor: Renkler.metinIkincil, padding: EdgeInsets.zero),
        child: const Text('← Kurallara dön'),
      ),
    );
  }

  // Oyunun önizlemesi: ne olduğu, numaralı kurallar ve puanlama. Uzun metin kaydırılır, buton hep altta durur.
  Widget _onizlemeAdimi(OyunOnizlemesi onizleme) {
    final zorluksuz = widget.zorluklar == null;
    return ConstrainedBox(
      key: const ValueKey('onizleme'),
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.78),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _baslik(aciklama: zorluksuz ? 'Tek mod · günde bir kart' : 'Kolay, Orta ya da Zor · günde bir zorluk'),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 16),
                  Text(onizleme.ozet, style: const TextStyle(color: Renkler.metin, fontSize: 15, height: 1.45)),
                  _adim('Nasıl oynanır'),
                  for (final (i, kural) in onizleme.kurallar.indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 26,
                            child: Text('${i + 1}', style: Yazi.tebesir(20, renk: Renkler.vurgu)),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                kural,
                                style: const TextStyle(color: Renkler.metinIkincil, fontSize: 14, height: 1.4),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 6),
                  TebesirKutusu(
                    kesik: true,
                    kenarRengi: Renkler.vurgu,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        Text(Yazi.buyuk('Puan'), style: Yazi.etiket(renk: Renkler.vurgu)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            onizleme.puanlama,
                            style: const TextStyle(color: Renkler.metin, fontSize: 14, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Her oyun günde bir kez oynanır. Oyundan çıksan da kaldığın yerden devam edersin.',
                    style: TextStyle(color: Renkler.metinSoluk, fontSize: 12.5, height: 1.35),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => setState(() => _onizlemede = false),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: Text(Yazi.buyuk(zorluksuz ? 'Anladım · süre seç' : 'Anladım · zorluk seç')),
          ),
        ],
      ),
    );
  }

  Widget _zorlukAdimi() {
    final zorluklar = widget.zorluklar!;
    return Column(
      key: const ValueKey('zorluk'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _baslik(aciklama: 'Bugün yalnızca bir zorluk oynayabilirsin.'),
        _kurallaraDon(),
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

    final dar = widget.sureler.length == 3;

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
              padding: EdgeInsets.symmetric(horizontal: dar ? 8 : 14, vertical: 12),
              // Üç kutu yan yana durunca sayı ve etiket alt alta yazılır, dar kutuya sığsın
              child: Flex(
                direction: dar ? Axis.vertical : Axis.horizontal,
                crossAxisAlignment: dar ? CrossAxisAlignment.center : CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(saniye == null ? '∞' : '$saniye', style: Yazi.tebesir(30, renk: secili ? Renkler.vurgu : Renkler.metin)),
                  if (!dar) const SizedBox(width: 6),
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
        if (zorlukAdi == null) _kurallaraDon(),
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
        // Üç ya da daha az seçenek tek satırda, dört seçenek iki satırda
        for (final (i, satir) in _satirlar(widget.sureler).indexed) ...[
          if (i > 0) const SizedBox(height: 8),
          Row(children: [
            for (final (j, s) in satir.indexed) ...[
              if (j > 0) const SizedBox(width: 8),
              sureKutusu(s),
            ],
          ]),
        ],
        const SizedBox(height: 14),
        Text(
          zorlukAdi == null
              ? 'Süre bütün oyun içindir ve oyundan çıksan da işler. Süre bitmediyse kaldığın yerden devam edersin.'
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

List<List<OyunSuresi>> _satirlar(List<OyunSuresi> sureler) =>
    sureler.length <= 3 ? [sureler] : [for (var i = 0; i < sureler.length; i += 2) sureler.skip(i).take(2).toList()];

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
