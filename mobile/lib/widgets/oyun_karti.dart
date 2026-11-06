import 'package:flutter/material.dart';
import '../models/oyun_modu.dart';
import '../theme/renkler.dart';
import '../theme/yazi.dart';
import 'tebesir.dart';

// Ana menüdeki oyun kutucuğu. Dört hâli var: oynanmadı ("Oyna"), yarım kaldı ("Devam et", sarı kesik kenar),
// bitti (soluk, köşesinde tebeşirle daire içine alınmış skor) ve yakında (silik, kesik kenar).
class OyunKarti extends StatelessWidget {
  final OyunModu mod;
  final int? bugunkuSkor; // null ise bugün henüz oynanmadı
  final String? oynananZorluk; // Zorluklu modlarda bugün oynanan zorluğun adı (ör. "Orta")
  final bool devamEdiyor; // Yarım kalan oyun var: "Oyna" yerine "Devam et"
  final VoidCallback? onTap;

  const OyunKarti({
    super.key,
    required this.mod,
    required this.bugunkuSkor,
    this.onTap,
    this.oynananZorluk,
    this.devamEdiyor = false,
  });

  bool get _yakinda => mod.durum == OyunDurumu.yakinda;
  bool get _bitti => bugunkuSkor != null && !devamEdiyor;

  String get _skorMetni => mod.maksimumSkor != null ? '$bugunkuSkor/${mod.maksimumSkor}' : '$bugunkuSkor';

  @override
  Widget build(BuildContext context) {
    final icerik = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ikon(),
            const SizedBox(width: 8),
            // Bitmiş kutucukta sağ üst köşe damgaya ayrılır. Dar ekranda yazı küçülür, taşmaz.
            if (!_bitti)
              Expanded(
                child: Align(
                  alignment: Alignment.topRight,
                  child: FittedBox(fit: BoxFit.scaleDown, child: _sagUst()),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          Yazi.buyuk(mod.baslik),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Yazi.baslik(19, renk: _yakinda ? Renkler.metinSoluk : Renkler.metin),
        ),
        const SizedBox(height: 5),
        Text(
          mod.aciklama,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: _yakinda ? Renkler.metinSoluk : Renkler.metinIkincil,
            fontSize: 12,
            height: 1.3,
          ),
        ),
        if (!_yakinda) ...[
          const SizedBox(height: 10),
          _etiketler(),
        ],
      ],
    );

    final kutu = TebesirKutusu(
      kenarRengi: devamEdiyor ? Renkler.vurgu : Renkler.kenar,
      kesik: devamEdiyor || _yakinda,
      dolgu: _yakinda ? null : const Color(0x08FFFFFF),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: _bitti
          ? Stack(
              clipBehavior: Clip.none,
              children: [
                Opacity(opacity: 0.5, child: icerik),
                Positioned(top: -6, right: -6, child: TebesirDamga(metin: _skorMetni)),
              ],
            )
          : icerik,
    );

    if (_yakinda) return kutu;

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        splashColor: Renkler.vurgu.withValues(alpha: 0.08),
        highlightColor: Renkler.vurgu.withValues(alpha: 0.05),
        child: kutu,
      ),
    );
  }

  Widget _ikon() {
    final cizim = mod.cizim;
    if (cizim != null) return TebesirIkonu(cizim: cizim, soluk: _yakinda);
    return Icon(mod.ikon, size: 30, color: _yakinda ? Renkler.metinSoluk : Renkler.metin);
  }

  Widget _sagUst() {
    if (_yakinda) return Text('YAKINDA', style: Yazi.etiket(boyut: 9.5, renk: Renkler.metinSoluk));
    if (mod.durum != OyunDurumu.aktif) {
      return const Text('Hazırlanıyor', style: TextStyle(color: Renkler.metinSoluk, fontSize: 12));
    }
    // Elle yazılıp altı çizilmiş "Oyna"
    return Container(
      padding: const EdgeInsets.only(bottom: 1),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Renkler.vurgu, width: 1.6))),
      child: Text(devamEdiyor ? 'Devam et' : 'Oyna', style: Yazi.tebesir(16, renk: Renkler.vurgu)),
    );
  }

  Widget _etiketler() {
    if (_bitti) return TebesirEtiket(oynananZorluk ?? 'Bitti', secili: true);
    if (devamEdiyor && oynananZorluk != null) return TebesirEtiket(oynananZorluk!, secili: true);
    if (mod.zorluklu) {
      return const Wrap(
        spacing: 4,
        children: [TebesirEtiket('K'), TebesirEtiket('O'), TebesirEtiket('Z')],
      );
    }
    return const TebesirEtiket('Tek mod', kesik: true);
  }
}
