import 'package:flutter/material.dart';
import '../theme/renkler.dart';
import '../theme/yazi.dart';
import 'kulup_logosu.dart';
import 'tebesir.dart';

// Önizlemede kuralların üstünde duran küçük örnek: oyunun bir anının tebeşirle çizilmiş hâli.
// Örneklerdeki oyuncular gerçekten o kutulara uyar. Logolar Transfermarkt'tan, bayraklar flagcdn'den link olarak gelir;
// yüklenemezse KulupLogosu yedek ikonu gösterir.
class OyunOrnegi extends StatelessWidget {
  final TebesirCizimi cizim;

  const OyunOrnegi({super.key, required this.cizim});

  @override
  Widget build(BuildContext context) {
    return TebesirKutusu(
      dolgu: const Color(0x0DFFFFFF),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(Yazi.buyuk('Örnek'), style: Yazi.etiket(boyut: 10, renk: Renkler.metinSoluk)),
          const SizedBox(height: 10),
          switch (cizim) {
            TebesirCizimi.kesisim => const _KesisimOrnegi(),
            TebesirCizimi.bonservis => const _BonservisOrnegi(),
            TebesirCizimi.izgara => const _IzgaraOrnegi(),
            TebesirCizimi.bingo => const _BingoOrnegi(),
          },
        ],
      ),
    );
  }
}

String _kulup(int id) => 'https://tmssl.akamaized.net/images/wappen/head/$id.png';
String _tm(String kod) => 'https://tmssl.akamaized.net/images/logo/header/$kod.png';
String _bayrak(String kod) => 'https://flagcdn.com/w160/$kod.png';

// Kesişim: iki kulüp ve ikisinde de oynamış oyuncu
class _KesisimOrnegi extends StatelessWidget {
  const _KesisimOrnegi();

  @override
  Widget build(BuildContext context) {
    Widget kulup(String ad, int id) => Column(
          children: [
            KulupLogosu(logoUrl: _kulup(id), boyut: 46),
            const SizedBox(height: 6),
            Text(ad, style: const TextStyle(color: Renkler.metinIkincil, fontSize: 12)),
          ],
        );

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            kulup('Real Madrid', 418),
            Text('+', style: Yazi.tebesir(28, renk: Renkler.vurgu)),
            kulup('Juventus', 506),
          ],
        ),
        const SizedBox(height: 12),
        const _OyuncuEtiketi(isim: 'Cristiano Ronaldo', dogru: true, buyuk: true),
      ],
    );
  }
}

// Bonservis: üstteki oyuncunun toplamı açık, alttakininki tahmin edilir
class _BonservisOrnegi extends StatelessWidget {
  const _BonservisOrnegi();

  @override
  Widget build(BuildContext context) {
    Widget satir(String ad, String bedel, {bool gizli = false}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: Renkler.yuzeyYuksek,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Renkler.kenar),
          ),
          child: Row(
            children: [
              const Icon(Icons.person_rounded, size: 20, color: Renkler.metinSoluk),
              const SizedBox(width: 8),
              Expanded(child: Text(ad, style: const TextStyle(color: Renkler.metin, fontSize: 13.5))),
              Text(bedel, style: Yazi.tebesir(18, renk: gizli ? Renkler.vurgu : Renkler.metin)),
            ],
          ),
        );

    Widget buton(String metin, IconData ikon, {bool dolu = false}) => Expanded(
          child: Container(
            height: 34,
            decoration: BoxDecoration(
              color: dolu ? Renkler.vurgu : null,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: dolu ? Renkler.vurgu : Renkler.kenar, width: 1.3),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(ikon, size: 15, color: dolu ? Renkler.arkaPlan : Renkler.metin),
                const SizedBox(width: 4),
                Text(metin, style: Yazi.baslik(14, kalinlik: FontWeight.w900, renk: dolu ? Renkler.arkaPlan : Renkler.metin)),
              ],
            ),
          ),
        );

    return Column(
      children: [
        satir('1. oyuncu', '95 mn €'),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text('vs', style: Yazi.tebesir(15, renk: Renkler.metinSoluk)),
        ),
        satir('2. oyuncu', '?', gizli: true),
        const SizedBox(height: 10),
        Row(
          children: [
            buton('DAHA AZ', Icons.arrow_downward_rounded),
            const SizedBox(width: 8),
            buton('DAHA FAZLA', Icons.arrow_upward_rounded, dolu: true),
          ],
        ),
      ],
    );
  }
}

// Izgara: satır ve sütun başlıkları kulüp, bazı kutular dolu
class _IzgaraOrnegi extends StatelessWidget {
  const _IzgaraOrnegi();

  static const _sutunlar = [(46, 'Inter'), (506, 'Juventus'), (985, 'Man Utd')];
  static const _satirlar = [(418, 'Real Madrid'), (131, 'Barcelona'), (5, 'Milan')];
  // [satır][sütun]; null boş kutu
  static const _dolu = [
    ['Figo', 'Ronaldo', 'Beckham'],
    ["Eto'o", null, null],
    ['İbrahimović', null, null],
  ];

  @override
  Widget build(BuildContext context) {
    const yukseklik = 50.0;

    Widget baslik(int id, String ad) => SizedBox(
          height: yukseklik,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              KulupLogosu(logoUrl: _kulup(id), boyut: 28),
              const SizedBox(height: 3),
              Text(ad, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Renkler.metinSoluk, fontSize: 9.5)),
            ],
          ),
        );

    Widget kutu(String? isim) => Container(
          height: yukseklik,
          margin: const EdgeInsets.all(2),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: isim == null ? null : Renkler.basari.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: isim == null ? Renkler.kenar : Renkler.basari.withValues(alpha: 0.6)),
          ),
          child: isim == null
              ? null
              : FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(isim, style: Yazi.tebesir(14, renk: Renkler.metin)),
                ),
        );

    return Table(
      columnWidths: const {0: FlexColumnWidth(0.9)},
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(children: [
          const SizedBox(height: yukseklik, child: Center(child: TebesirIkonu(cizim: TebesirCizimi.izgara, boyut: 26))),
          for (final (id, ad) in _sutunlar) baslik(id, ad),
        ]),
        for (final (i, (id, ad)) in _satirlar.indexed)
          TableRow(children: [
            baslik(id, ad),
            for (final isim in _dolu[i]) kutu(isim),
          ]),
      ],
    );
  }
}

// Bingo: sıradaki oyuncu ve 4x3 kart; bazı kutular dolu
class _BingoOrnegi extends StatelessWidget {
  const _BingoOrnegi();

  static final _kutular = <(String, String, String?)>[
    ('Real Madrid', _kulup(418), 'Ronaldo'),
    ('Barcelona', _kulup(131), null),
    ('Bayern', _kulup(27), null),
    ('Brezilya', _bayrak('br'), 'Neymar'),
    ('Fransa', _bayrak('fr'), null),
    ('Portekiz', _bayrak('pt'), null),
    ('Bundesliga', _tm('l1'), null),
    ('Ligue 1', _tm('fr1'), null),
    ('Chelsea', _kulup(631), null),
    ('Ş. Ligi', _tm('cl'), null),
    ('Dünya Kupası', _tm('fiwc'), null),
    ('Premier Lig şamp.', _tm('gb1'), null),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(Yazi.buyuk('Sıradaki'), style: Yazi.etiket(boyut: 10, renk: Renkler.vurgu)),
            const SizedBox(width: 8),
            const Expanded(child: _OyuncuEtiketi(isim: 'Kylian Mbappé')),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Renkler.kenar),
              ),
              child: const Text('Pas', style: TextStyle(color: Renkler.metinIkincil, fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          childAspectRatio: 2.3,
          children: [
            for (final (ad, logo, oyuncu) in _kutular)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                decoration: BoxDecoration(
                  color: oyuncu == null ? null : Renkler.basari.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: oyuncu == null ? Renkler.kenar : Renkler.basari.withValues(alpha: 0.6)),
                ),
                child: Row(
                  children: [
                    KulupLogosu(logoUrl: logo, boyut: 22),
                    const SizedBox(width: 5),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: oyuncu == null
                            ? Text(ad, style: const TextStyle(color: Renkler.metinIkincil, fontSize: 11))
                            : Text(oyuncu, style: Yazi.tebesir(14, renk: Renkler.metin)),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// Oyuncu adı rozeti; doğruysa yeşil tikli
class _OyuncuEtiketi extends StatelessWidget {
  final String isim;
  final bool dogru;
  final bool buyuk;

  const _OyuncuEtiketi({required this.isim, this.dogru = false, this.buyuk = false});

  @override
  Widget build(BuildContext context) {
    final renk = dogru ? Renkler.basari : Renkler.vurgu;
    return Center(
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: buyuk ? 7 : 5),
        decoration: BoxDecoration(
          color: renk.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: renk.withValues(alpha: 0.7)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(dogru ? Icons.check_rounded : Icons.person_rounded, size: buyuk ? 18 : 15, color: renk),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                isim,
                overflow: TextOverflow.ellipsis,
                style: Yazi.tebesir(buyuk ? 19 : 16, renk: Renkler.metin),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
