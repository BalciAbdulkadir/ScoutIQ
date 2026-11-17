import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/oyuncu_oneri.dart';
import '../theme/renkler.dart';
import '../theme/yazi.dart';
import 'oyuncu_fotografi.dart';

// Gönderilen tahminin sonucu. Yazma alanı buna göre sallanır, renklenir ya da sessizce temizlenir.
enum TahminSonucu { dogru, yanlis, notr }

// Sunucuya gidemeyen gönderim (bağlantı, oturum): mesajı alanın altında gösterilir, seçim kalır
class TahminHatasi {
  final String mesaj;
  const TahminHatasi(this.mesaj);
}

// Oyuncu yazma alanı ve altındaki öneri listesi. Kesişim ve Izgara ortak kullanır.
// Tahtaya çekilmiş tebeşir çizgisi üstüne el yazısıyla yazılır; cevap sadece listeden seçilir.
// Seçilen oyuncu fotoğraflı bir etikete dönüşür, Gönder butonuyla gönderilir (yanlış satıra dokunmak tahmin harcamasın).
class OyuncuArama extends StatefulWidget {
  final Color renk;
  final bool gonderiliyor;
  // Tüm oyuncular arasında arar, doğru cevabı ele vermez
  final Future<List<OyuncuOneri>> Function(String metin) ara;
  // Seçilen oyuncuyu gönderir. Sonuç alan geri bildirimini belirler; TahminHatasi fırlatırsa mesajı gösterilir.
  final Future<TahminSonucu> Function(OyuncuOneri oyuncu) gonder;
  // Bu oyunda zaten kullanılmış oyuncu isimleri (Izgara'da tahtadakiler): listede soluk durur, seçilemez
  final Set<String> kullanilanlar;
  final String kullanildiEtiketi;

  const OyuncuArama({
    super.key,
    required this.renk,
    required this.gonderiliyor,
    required this.ara,
    required this.gonder,
    this.kullanilanlar = const {},
    this.kullanildiEtiketi = 'tahtada',
  });

  @override
  State<OyuncuArama> createState() => _OyuncuAramaState();
}

enum _Geribildirim { yok, dogru, yanlis }

class _OyuncuAramaState extends State<OyuncuArama> with SingleTickerProviderStateMixin {
  static const _enFazlaOneri = 6;
  static const _aramaBeklemesi = Duration(milliseconds: 250);
  static const _geribildirimSuresi = Duration(milliseconds: 900);

  final TextEditingController _controller = TextEditingController();
  final FocusNode _odak = FocusNode();
  final GlobalKey _alanAnahtari = GlobalKey();
  late final AnimationController _sallanma =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  List<OyuncuOneri> _oneriler = [];
  String _aranan = ''; // Önerilerin geldiği arama; vurgu buna göre yapılır
  OyuncuOneri? _secilen;
  bool _araniyor = false;
  String? _hata; // Alanın altındaki kırmızı tebeşir mesajı
  _Geribildirim _geribildirim = _Geribildirim.yok;
  Timer? _aramaZamanlayici;
  Timer? _geribildirimZamanlayici;
  Timer? _kaydirmaZamanlayici;
  int _aramaNo = 0; // Geç gelen eski arama sonuçlarının yenilerinin üstüne yazılmasını engeller

  bool get _kilitli => widget.gonderiliyor || _geribildirim != _Geribildirim.yok;

  @override
  void initState() {
    super.initState();
    _odak.addListener(() {
      if (_odak.hasFocus) _gorunureKaydir();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _aramaZamanlayici?.cancel();
    _geribildirimZamanlayici?.cancel();
    _kaydirmaZamanlayici?.cancel();
    _sallanma.dispose();
    _odak.dispose();
    _controller.dispose();
    super.dispose();
  }

  // Klavye açılırken alan ve liste ekranın üst kısmına kaydırılır ki öneriler klavyenin altında kalmasın
  void _gorunureKaydir() {
    _kaydirmaZamanlayici?.cancel();
    _kaydirmaZamanlayici = Timer(const Duration(milliseconds: 320), () {
      final alan = _alanAnahtari.currentContext;
      if (!mounted || alan == null || !alan.mounted || !_odak.hasFocus) return;
      Scrollable.ensureVisible(
        alan,
        alignment: 0.04,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _metinDegisti(String metin) {
    _aramaZamanlayici?.cancel();
    final arama = metin.trim();
    setState(() => _hata = null);

    if (arama.length < 2) {
      _aramaNo++;
      setState(() {
        _oneriler = [];
        _aranan = '';
        _araniyor = false;
      });
      return;
    }

    setState(() => _araniyor = true);
    // Her tuşta sunucuya gitmemek için yazmanın bitmesini kısaca bekliyoruz
    _aramaZamanlayici = Timer(_aramaBeklemesi, () => _ara(arama));
  }

  Future<void> _ara(String arama) async {
    final buArama = ++_aramaNo;
    try {
      final sonuc = await widget.ara(arama);
      if (!mounted || buArama != _aramaNo) return;
      setState(() {
        _oneriler = sonuc.take(_enFazlaOneri).toList();
        _aranan = arama;
        _araniyor = false;
      });
      _gorunureKaydir();
    } catch (_) {
      if (!mounted || buArama != _aramaNo) return;
      setState(() {
        _oneriler = [];
        _aranan = arama;
        _araniyor = false;
        _hata = 'Arama yapılamadı. Bağlantını kontrol et.';
      });
    }
  }

  bool _kullanildi(OyuncuOneri oyuncu) => widget.kullanilanlar.contains(oyuncu.isim);

  void _oyuncuSec(OyuncuOneri oyuncu) {
    if (_kilitli || _kullanildi(oyuncu)) return;
    HapticFeedback.selectionClick();
    _aramaZamanlayici?.cancel();
    _aramaNo++;
    _controller.clear();
    _odak.unfocus();
    setState(() {
      _secilen = oyuncu;
      _oneriler = [];
      _aranan = '';
      _araniyor = false;
      _hata = null;
    });
  }

  // Klavyedeki tuş: listedeki ilk uygun oyuncuyu seçer
  void _klavyedenGonder() {
    final ilk = _oneriler.where((o) => !_kullanildi(o)).firstOrNull;
    if (ilk != null) {
      _oyuncuSec(ilk);
    } else if (!_araniyor) {
      setState(() => _hata = 'Listeden bir oyuncu seç.');
    }
  }

  void _secimiKaldir() {
    if (_kilitli) return;
    setState(() {
      _secilen = null;
      _hata = null;
    });
    // Yazma alanı bir sonraki karede yeniden kurulur, odak ondan sonra verilir
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _odak.requestFocus();
    });
  }

  void _metniTemizle() {
    _controller.clear();
    _metinDegisti('');
  }

  Future<void> _gonder() async {
    final secilen = _secilen;
    if (secilen == null || _kilitli) return;

    TahminSonucu sonuc;
    try {
      sonuc = await widget.gonder(secilen);
    } on TahminHatasi catch (h) {
      if (mounted) setState(() => _hata = h.mesaj);
      return;
    }
    if (!mounted) return;

    if (sonuc == TahminSonucu.notr) {
      setState(() => _secilen = null);
      return;
    }

    final dogru = sonuc == TahminSonucu.dogru;
    if (dogru) {
      HapticFeedback.lightImpact();
    } else {
      HapticFeedback.heavyImpact();
      _sallanma.forward(from: 0);
    }
    setState(() => _geribildirim = dogru ? _Geribildirim.dogru : _Geribildirim.yanlis);

    // İsim kısa bir an yeşil ya da üstü çizili kalır, sonra alan bir sonraki tahmin için boşalır
    _geribildirimZamanlayici?.cancel();
    _geribildirimZamanlayici = Timer(_geribildirimSuresi, () {
      if (!mounted) return;
      setState(() {
        _secilen = null;
        _geribildirim = _Geribildirim.yok;
      });
    });
  }

  Color get _cizgiRengi => switch (_geribildirim) {
        _Geribildirim.dogru => Renkler.basari,
        _Geribildirim.yanlis => Renkler.hata,
        _Geribildirim.yok when _hata != null => Renkler.hata,
        _Geribildirim.yok when _odak.hasFocus || _secilen != null => widget.renk,
        _ => Renkler.kenar,
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedBuilder(
          animation: _sallanma,
          builder: (context, child) {
            // Sönümlenen sağ-sol sallanma
            final t = _sallanma.value;
            final kayma = math.sin(t * math.pi * 5) * 8 * (1 - t);
            return Transform.translate(offset: Offset(kayma, 0), child: child);
          },
          child: _TebesirCizgisi(
            key: _alanAnahtari,
            renk: _cizgiRengi,
            kesik: !_odak.hasFocus && _secilen == null && _hata == null,
            child: _secilen == null ? _yaziAlani() : _secimEtiketi(_secilen!),
          ),
        ),
        _altMesaj(),
        if (_secilen == null)
          _oneriListesi()
        // Geri bildirim sırasında buton kaybolur: isim kısa bir an kalır, sonra alan boşalır
        else if (_geribildirim == _Geribildirim.yok)
          _gonderButonu(),
      ],
    );
  }

  Widget _yaziAlani() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            focusNode: _odak,
            enabled: !_kilitli,
            style: Yazi.tebesir(24),
            cursorColor: widget.renk,
            cursorWidth: 2.5,
            cursorRadius: const Radius.circular(2),
            // Oyuncu isimleri sözlükte yok: klavyenin düzeltmesi ve kelime önerileri isimleri bozar
            autocorrect: false,
            enableSuggestions: false,
            smartDashesType: SmartDashesType.disabled,
            smartQuotesType: SmartQuotesType.disabled,
            keyboardType: TextInputType.name,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onChanged: _metinDegisti,
            onSubmitted: (_) => _klavyedenGonder(),
            // Klavye tuşu odağı kaybettirmesin: liste açık kalır
            onEditingComplete: () {},
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              filled: false,
              contentPadding: const EdgeInsets.fromLTRB(2, 10, 0, 8),
              hintText: 'oyuncu yaz…',
              hintStyle: Yazi.tebesir(24, renk: Renkler.metinSoluk, kalinlik: FontWeight.w400),
            ),
          ),
        ),
        ValueListenableBuilder(
          valueListenable: _controller,
          builder: (context, deger, _) {
            if (_araniyor) {
              return Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: widget.renk),
                ),
              );
            }
            if (deger.text.isEmpty) return const SizedBox(width: 40);
            return IconButton(
              tooltip: 'Temizle',
              onPressed: _metniTemizle,
              icon: const Icon(Icons.close_rounded, color: Renkler.metinSoluk, size: 20),
            );
          },
        ),
      ],
    );
  }

  // Seçilen oyuncu: fotoğraflı tebeşir etiketi. Yanlışsa isim kırmızı tebeşirle çizilir, doğruysa yeşile döner.
  Widget _secimEtiketi(OyuncuOneri oyuncu) {
    final renk = switch (_geribildirim) {
      _Geribildirim.dogru => Renkler.basari,
      _Geribildirim.yanlis => Renkler.hata,
      _Geribildirim.yok => widget.renk,
    };

    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 8),
      child: Row(
        children: [
          Flexible(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.fromLTRB(4, 4, 6, 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: renk, width: 1.6),
                color: renk.withValues(alpha: 0.08),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OyuncuFotografi.yuvarlak(
                    isim: oyuncu.isim,
                    fotoUrl: oyuncu.fotoUrl,
                    boyut: 32,
                    harfRengi: renk,
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: _CizilenYazi(
                      metin: oyuncu.isim,
                      stil: Yazi.tebesir(21, renk: renk),
                      cizili: _geribildirim == _Geribildirim.yanlis,
                    ),
                  ),
                  const SizedBox(width: 2),
                  if (_geribildirim == _Geribildirim.dogru)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.check_rounded, color: Renkler.basari, size: 20),
                    )
                  else if (_geribildirim == _Geribildirim.yanlis)
                    const SizedBox(width: 10)
                  else
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: IconButton(
                        tooltip: 'Seçimi kaldır',
                        padding: EdgeInsets.zero,
                        onPressed: _kilitli ? null : _secimiKaldir,
                        icon: const Icon(Icons.close_rounded, color: Renkler.metinIkincil, size: 18),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _altMesaj() {
    final String? metin;
    final Color renk;
    if (_hata != null) {
      metin = _hata;
      renk = Renkler.hata;
    } else if (_secilen != null && _geribildirim == _Geribildirim.yok) {
      metin = 'Değiştirmek için × ile kaldır.';
      renk = Renkler.metinSoluk;
    } else {
      metin = null;
      renk = Renkler.metinSoluk;
    }

    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      alignment: Alignment.topLeft,
      child: metin == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: 6, left: 2),
              child: Text(
                metin,
                style: _hata != null
                    ? Yazi.tebesir(16, renk: renk)
                    : TextStyle(color: renk, fontSize: 13),
              ),
            ),
    );
  }

  Widget _gonderButonu() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: FilledButton(
        onPressed: _kilitli ? null : _gonder,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          backgroundColor: widget.renk,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: widget.gonderiliyor
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: Renkler.metinSoluk),
              )
            : Text(Yazi.buyuk('Gönder'), style: Yazi.baslik(20, kalinlik: FontWeight.w900, renk: Renkler.arkaPlan)),
      ),
    );
  }

  Widget _oneriListesi() {
    final metin = _controller.text.trim();
    final Widget icerik;

    if (metin.length < 2) {
      icerik = const SizedBox(width: double.infinity);
    } else if (_araniyor && _oneriler.isEmpty) {
      icerik = const _IskeletListe(key: ValueKey('iskelet'));
    } else if (_oneriler.isEmpty) {
      icerik = Padding(
        key: const ValueKey('bos'),
        padding: const EdgeInsets.only(top: 12, left: 2),
        child: Text.rich(
          TextSpan(children: [
            TextSpan(text: 'Bu isimde kimse yok. ', style: Yazi.tebesir(16, renk: Renkler.metinIkincil)),
            const TextSpan(text: 'Soyadıyla ya da farklı yazımla dene.'),
          ]),
          style: const TextStyle(color: Renkler.metinSoluk, fontSize: 13),
        ),
      );
    } else {
      icerik = _OneriKarti(
        key: const ValueKey('liste'),
        oneriler: _oneriler,
        aranan: _aranan,
        renk: widget.renk,
        kullanildi: _kullanildi,
        kullanildiEtiketi: widget.kullanildiEtiketi,
        onSec: _oyuncuSec,
        soluk: _araniyor,
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 160),
      layoutBuilder: (mevcut, onceki) => Stack(
        alignment: Alignment.topCenter,
        children: [...onceki, ?mevcut],
      ),
      child: icerik,
    );
  }
}

// Alanın altındaki tebeşir çizgisi: hafif dalgalı, iki katmanlı (tebeşirin pürüzü). Boşken kesik ve soluk.
class _TebesirCizgisi extends StatelessWidget {
  final Color renk;
  final bool kesik;
  final Widget child;

  const _TebesirCizgisi({super.key, required this.renk, required this.kesik, required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: renk),
      duration: const Duration(milliseconds: 220),
      builder: (context, cizgiRengi, child) => CustomPaint(
        foregroundPainter: _CizgiCizeri(cizgiRengi ?? renk, kesik),
        child: child,
      ),
      child: Padding(padding: const EdgeInsets.only(bottom: 4), child: child),
    );
  }
}

class _CizgiCizeri extends CustomPainter {
  final Color renk;
  final bool kesik;

  _CizgiCizeri(this.renk, this.kesik);

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height - 2;
    final yol = Path()..moveTo(0, y);
    // Elle çekilmiş gibi çok hafif dalga
    for (double x = 0; x <= size.width; x += 6) {
      yol.lineTo(x, y + math.sin(x / 37) * 0.8 + math.sin(x / 11) * 0.3);
    }

    final ana = Paint()
      ..color = renk
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    final puruz = Paint()
      ..color = renk.withValues(alpha: renk.a * 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;

    if (!kesik) {
      canvas.drawPath(yol, ana);
      canvas.drawPath(yol.shift(const Offset(0, 1.6)), puruz);
      return;
    }

    // Kesik çizgi: 22 birim çizgi, 6 birim boşluk
    for (final metrik in yol.computeMetrics()) {
      for (double d = 0; d < metrik.length; d += 28) {
        canvas.drawPath(metrik.extractPath(d, math.min(d + 22, metrik.length)), ana);
      }
    }
  }

  @override
  bool shouldRepaint(_CizgiCizeri eski) => eski.renk != renk || eski.kesik != kesik;
}

// Yanlış tahminde ismin üstünü soldan sağa çizen kırmızı tebeşir
class _CizilenYazi extends StatelessWidget {
  final String metin;
  final TextStyle stil;
  final bool cizili;

  const _CizilenYazi({required this.metin, required this.stil, required this.cizili});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: cizili ? 1 : 0),
      duration: Duration(milliseconds: cizili ? 280 : 0),
      curve: Curves.easeOutCubic,
      builder: (context, oran, child) => CustomPaint(foregroundPainter: _UstCizgiCizeri(oran), child: child),
      child: Text(metin, maxLines: 1, overflow: TextOverflow.ellipsis, style: stil),
    );
  }
}

class _UstCizgiCizeri extends CustomPainter {
  final double oran;

  _UstCizgiCizeri(this.oran);

  @override
  void paint(Canvas canvas, Size size) {
    if (oran <= 0) return;
    final kalem = Paint()
      ..color = Renkler.hata
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    // Hafif eğik, ismin biraz dışına taşan çizgi
    final bas = Offset(-3, size.height * 0.62);
    final son = Offset(size.width + 3, size.height * 0.48);
    canvas.drawLine(bas, Offset.lerp(bas, son, oran)!, kalem);
  }

  @override
  bool shouldRepaint(_UstCizgiCizeri eski) => eski.oran != oran;
}

// Öneri listesi: tahtanın üstünde duran kart. İlk satır hafif vurgulu (klavyedeki tuş onu seçer).
class _OneriKarti extends StatelessWidget {
  final List<OyuncuOneri> oneriler;
  final String aranan;
  final Color renk;
  final bool Function(OyuncuOneri) kullanildi;
  final String kullanildiEtiketi;
  final void Function(OyuncuOneri) onSec;
  final bool soluk; // Yeni arama sürerken eski sonuçlar

  const _OneriKarti({
    super.key,
    required this.oneriler,
    required this.aranan,
    required this.renk,
    required this.kullanildi,
    required this.kullanildiEtiketi,
    required this.onSec,
    required this.soluk,
  });

  @override
  Widget build(BuildContext context) {
    final ilkUygun = oneriler.indexWhere((o) => !kullanildi(o));

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: AnimatedOpacity(
        opacity: soluk ? 0.6 : 1,
        duration: const Duration(milliseconds: 150),
        child: Material(
          color: Renkler.yuzeyYuksek,
          elevation: 2,
          shadowColor: Colors.black26,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: Renkler.kenar, width: 1.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Column(
              children: [
                for (var i = 0; i < oneriler.length; i++)
                  _OneriSatiri(
                    oyuncu: oneriler[i],
                    aranan: aranan,
                    renk: renk,
                    one: i == ilkUygun,
                    kullanildi: kullanildi(oneriler[i]),
                    kullanildiEtiketi: kullanildiEtiketi,
                    onTap: () => onSec(oneriler[i]),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OneriSatiri extends StatelessWidget {
  final OyuncuOneri oyuncu;
  final String aranan;
  final Color renk;
  final bool one;
  final bool kullanildi;
  final String kullanildiEtiketi;
  final VoidCallback onTap;

  const _OneriSatiri({
    required this.oyuncu,
    required this.aranan,
    required this.renk,
    required this.one,
    required this.kullanildi,
    required this.kullanildiEtiketi,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final aralik = eslesmeAraligi(oyuncu.isim, aranan);
    const temel = TextStyle(color: Renkler.metin, fontSize: 16, fontWeight: FontWeight.w500);

    final isim = Text.rich(
      aralik == null
          ? TextSpan(text: oyuncu.isim)
          : TextSpan(children: [
              TextSpan(text: oyuncu.isim.substring(0, aralik.start)),
              TextSpan(
                text: oyuncu.isim.substring(aralik.start, aralik.end),
                style: TextStyle(color: renk, fontWeight: FontWeight.w700),
              ),
              TextSpan(text: oyuncu.isim.substring(aralik.end)),
            ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: kullanildi
          ? temel.copyWith(decoration: TextDecoration.lineThrough, decorationColor: Renkler.metinSoluk)
          : temel,
    );

    return Opacity(
      opacity: kullanildi ? 0.45 : 1,
      child: Material(
        color: one ? renk.withValues(alpha: 0.10) : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: kullanildi ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                OyuncuFotografi(isim: oyuncu.isim, fotoUrl: oyuncu.fotoUrl, boyut: 28),
                const SizedBox(width: 12),
                Expanded(child: isim),
                if (kullanildi)
                  Text(Yazi.buyuk(kullanildiEtiketi), style: Yazi.etiket(boyut: 11, renk: Renkler.metinSoluk))
                else if (one)
                  Icon(Icons.keyboard_return_rounded, size: 16, color: renk.withValues(alpha: 0.7)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Arama sürerken gösterilen soluk satırlar
class _IskeletListe extends StatelessWidget {
  const _IskeletListe({super.key});

  @override
  Widget build(BuildContext context) {
    Widget satir(double genislik) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 36,
                decoration: BoxDecoration(color: Renkler.kenar.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(5)),
              ),
              const SizedBox(width: 12),
              FractionallySizedBox(
                widthFactor: genislik,
                child: Container(
                  height: 12,
                  decoration: BoxDecoration(color: Renkler.kenar.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(6)),
                ),
              ),
            ],
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Renkler.yuzeyYuksek,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Renkler.kenar, width: 1.5),
        ),
        child: Column(children: [satir(0.5), satir(0.38), satir(0.44)]),
      ),
    );
  }
}

// İsimde aramayla eşleşen bölüm. Arama sunucudaki gibi büyük/küçük harf, aksan ve Türkçe harf farkını,
// boşluk ve noktalamayı yok sayar ("ozil" -> "Özil", "vandijk" -> "van Dijk"). Kelime başındaki eşleşme önce gelir.
({int start, int end})? eslesmeAraligi(String isim, String aranan) {
  final arama = _sadelestir(aranan).metin;
  if (arama.isEmpty) return null;
  final (:metin, :konumlar) = _sadelestir(isim);

  int? bulunan;
  for (var i = metin.indexOf(arama); i >= 0; i = metin.indexOf(arama, i + 1)) {
    final asil = konumlar[i];
    final kelimeBasi = asil == 0 || !_harfMi(isim[asil - 1]);
    if (kelimeBasi) {
      bulunan = i;
      break;
    }
    bulunan ??= i;
  }
  if (bulunan == null) return null;
  return (start: konumlar[bulunan], end: konumlar[bulunan + arama.length - 1] + 1);
}

bool _harfMi(String k) => _sadelestir(k).metin.isNotEmpty;

const _harfKarsiliklari = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a', 'ā': 'a', 'ą': 'a', 'æ': 'ae',
  'ç': 'c', 'ć': 'c', 'č': 'c', 'ď': 'd', 'đ': 'd', 'ð': 'd',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e', 'ę': 'e', 'ě': 'e',
  'ğ': 'g', 'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i', 'ı': 'i', 'ī': 'i', 'ł': 'l', 'ľ': 'l',
  'ñ': 'n', 'ń': 'n', 'ň': 'n', 'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', 'ø': 'o', 'ő': 'o', 'œ': 'oe',
  'ř': 'r', 'ş': 's', 'ś': 's', 'š': 's', 'ș': 's', 'ß': 'ss', 'ť': 't', 'ț': 't', 'þ': 'th',
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ū': 'u', 'ů': 'u', 'ű': 'u', 'ý': 'y', 'ÿ': 'y',
  'ž': 'z', 'ź': 'z', 'ż': 'z',
};

// Sadeleştirilmiş metin ve her karakterinin asıl metindeki yeri
({String metin, List<int> konumlar}) _sadelestir(String s) {
  final metin = StringBuffer();
  final konumlar = <int>[];
  for (var i = 0; i < s.length; i++) {
    var k = s[i];
    k = k == 'İ' ? 'i' : k.toLowerCase();
    final karsilik = _harfKarsiliklari[k] ?? k;
    for (final c in karsilik.split('')) {
      if (RegExp(r'[a-z0-9]').hasMatch(c)) {
        metin.write(c);
        konumlar.add(i);
      }
    }
  }
  return (metin: metin.toString(), konumlar: konumlar);
}
