import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../theme/renkler.dart';
import '../theme/yazi.dart';

// Taktik tahtasının tebeşir parçaları: oyun çizimleri, çentikler, skor damgası, kesik çizgiler.

// Her oyunun ana menüdeki kendi tebeşir çizimi
enum TebesirCizimi { kesisim, bonservis, izgara, bingo }

class TebesirIkonu extends StatelessWidget {
  final TebesirCizimi cizim;
  final double boyut;
  final bool soluk; // Yakındaki oyunlar ve bitmiş kutucuklar için

  const TebesirIkonu({super.key, required this.cizim, this.boyut = 34, this.soluk = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: boyut,
      height: boyut,
      child: CustomPaint(painter: _IkonCizeri(cizim, soluk)),
    );
  }
}

class _IkonCizeri extends CustomPainter {
  final TebesirCizimi cizim;
  final bool soluk;

  _IkonCizeri(this.cizim, this.soluk);

  @override
  void paint(Canvas canvas, Size size) {
    // Çizimler 44x44'lük bir tahtaya göre yazıldı, boyuta göre ölçeklenir
    final o = size.width / 44;
    canvas.scale(o);

    final beyaz = Paint()
      ..color = soluk ? Renkler.metinSoluk : Renkler.metin
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final sari = Paint()
      ..color = soluk ? Renkler.metinSoluk : Renkler.vurgu
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round;

    switch (cizim) {
      case TebesirCizimi.kesisim:
        canvas.drawCircle(const Offset(17, 22), 11, beyaz);
        canvas.drawCircle(const Offset(27, 22), 11, beyaz);
        for (var y = 13.5; y < 30.5; y += 5) {
          canvas.drawLine(Offset(22, y), Offset(22, math.min(y + 2, 30.5)), sari);
        }
      case TebesirCizimi.bonservis:
        canvas.drawPath(
          Path()
            ..moveTo(14, 32)
            ..lineTo(14, 12)
            ..moveTo(9, 17)
            ..lineTo(14, 12)
            ..lineTo(19, 17),
          beyaz,
        );
        canvas.drawPath(
          Path()
            ..moveTo(30, 12)
            ..lineTo(30, 32)
            ..moveTo(25, 27)
            ..lineTo(30, 32)
            ..lineTo(35, 27),
          sari,
        );
      case TebesirCizimi.izgara:
        canvas.drawPath(
          Path()
            ..moveTo(8, 17)
            ..lineTo(36, 17)
            ..moveTo(8, 27)
            ..lineTo(36, 27)
            ..moveTo(17, 8)
            ..lineTo(17, 36)
            ..moveTo(27, 8)
            ..lineTo(27, 36),
          beyaz,
        );
        canvas.drawPath(
          Path()
            ..moveTo(10, 10.5)
            ..lineTo(14, 14.5)
            ..moveTo(14, 10.5)
            ..lineTo(10, 14.5),
          sari,
        );
        canvas.drawCircle(const Offset(31.5, 31.5), 2.6, sari);
      case TebesirCizimi.bingo:
        // Oyundaki kart gibi 4 satır, 3 sütun
        for (final x in [11.0, 22.0, 33.0]) {
          for (final y in [7.0, 17.0, 27.0, 37.0]) {
            canvas.drawCircle(Offset(x, y), 2.8, beyaz);
          }
        }
    }
  }

  @override
  bool shouldRepaint(_IkonCizeri eski) => eski.cizim != cizim || eski.soluk != soluk;
}

// Günlük ilerleme: biten her oyun için sarı, kalan her oyun için soluk bir tebeşir çentiği
class TebesirCentikleri extends StatelessWidget {
  final int toplam;
  final int biten;

  const TebesirCentikleri({super.key, required this.toplam, required this.biten});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < toplam; i++)
          Padding(
            padding: const EdgeInsets.only(right: 5),
            child: Transform.rotate(
              angle: 0.1,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 2.2,
                height: 17,
                decoration: BoxDecoration(
                  color: i < biten ? Renkler.vurgu : Renkler.kenar,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// Biten oyunun skoru: tebeşirle yazılıp elle daire içine alınmış gibi
class TebesirDamga extends StatelessWidget {
  final String metin;
  final double genislik;

  const TebesirDamga({super.key, required this.metin, this.genislik = 64});

  @override
  Widget build(BuildContext context) {
    final yukseklik = genislik * 0.64;
    return Transform.rotate(
      angle: -0.16,
      child: SizedBox(
        width: genislik,
        height: yukseklik,
        child: CustomPaint(
          painter: _DamgaCizeri(),
          child: Center(
            child: Text(metin, style: Yazi.tebesir(genislik * 0.32, renk: Renkler.vurgu)),
          ),
        ),
      ),
    );
  }
}

class _DamgaCizeri extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // 62x40'lık taslaktan ölçeklenir: bir kez dolanıp başlangıcı geçen el çizimi bir oval
    final sx = size.width / 62;
    final sy = size.height / 40;
    final yol = Path()
      ..moveTo(9 * sx, 23 * sy)
      ..cubicTo(5 * sx, 9 * sy, 50 * sx, 3 * sy, 56 * sx, 17 * sy)
      ..cubicTo(61 * sx, 31 * sy, 22 * sx, 39 * sy, 10 * sx, 29 * sy)
      ..cubicTo(5 * sx, 25 * sy, 11 * sx, 13 * sy, 24 * sx, 10 * sy);
    canvas.drawPath(
      yol,
      Paint()
        ..color = Renkler.vurgu
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.7
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_DamgaCizeri eski) => false;
}

// Yatay tebeşir kesik çizgisi (bölüm ayırıcı)
class KesikCizgi extends StatelessWidget {
  final Color renk;

  const KesikCizgi({super.key, this.renk = Renkler.kenar});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1.5,
      width: double.infinity,
      child: CustomPaint(painter: _KesikCizgiCizeri(renk)),
    );
  }
}

class _KesikCizgiCizeri extends CustomPainter {
  final Color renk;

  _KesikCizgiCizeri(this.renk);

  @override
  void paint(Canvas canvas, Size size) {
    final kalem = Paint()
      ..color = renk
      ..strokeWidth = size.height;
    for (var x = 0.0; x < size.width; x += 9) {
      canvas.drawLine(Offset(x, size.height / 2), Offset(math.min(x + 5, size.width), size.height / 2), kalem);
    }
  }

  @override
  bool shouldRepaint(_KesikCizgiCizeri eski) => eski.renk != renk;
}

// Kenarı tebeşirle çizilmiş kutu. Kesik kenar "yarım kaldı" ya da "yakında" demektir.
class TebesirKutusu extends StatelessWidget {
  final Widget child;
  final Color kenarRengi;
  final bool kesik;
  final Color? dolgu;
  final EdgeInsetsGeometry padding;
  final double kose;

  const TebesirKutusu({
    super.key,
    required this.child,
    this.kenarRengi = Renkler.kenar,
    this.kesik = false,
    this.dolgu,
    this.padding = const EdgeInsets.all(12),
    this.kose = 6,
  });

  @override
  Widget build(BuildContext context) {
    if (!kesik) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: padding,
        decoration: BoxDecoration(
          color: dolgu,
          borderRadius: BorderRadius.circular(kose),
          border: Border.all(color: kenarRengi, width: 1.5),
        ),
        child: child,
      );
    }
    return CustomPaint(
      painter: _KesikKenarCizeri(kenarRengi, kose),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(color: dolgu, borderRadius: BorderRadius.circular(kose)),
        child: child,
      ),
    );
  }
}

class _KesikKenarCizeri extends CustomPainter {
  final Color renk;
  final double kose;

  _KesikKenarCizeri(this.renk, this.kose);

  @override
  void paint(Canvas canvas, Size size) {
    final kalem = Paint()
      ..color = renk
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final cerceve = RRect.fromRectAndRadius((Offset.zero & size).deflate(0.75), Radius.circular(kose));
    for (final olcu in (Path()..addRRect(cerceve)).computeMetrics()) {
      for (var d = 0.0; d < olcu.length; d += 9) {
        canvas.drawPath(olcu.extractPath(d, math.min(d + 5, olcu.length)), kalem);
      }
    }
  }

  @override
  bool shouldRepaint(_KesikKenarCizeri eski) => eski.renk != renk || eski.kose != kose;
}

// Ekranların arkasındaki tahta: üstten hafif ışık alan koyu yeşil
class TahtaZemini extends StatelessWidget {
  final Widget child;

  const TahtaZemini({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -1.1),
          radius: 1.3,
          colors: [Renkler.arkaPlanAcik, Renkler.arkaPlan],
        ),
      ),
      child: child,
    );
  }
}

// Küçük büyük harfli tebeşir etiketi: "K", "ORTA · 60 SN", "TEK MOD"
class TebesirEtiket extends StatelessWidget {
  final String metin;
  final bool secili;
  final bool kesik;

  const TebesirEtiket(this.metin, {super.key, this.secili = false, this.kesik = false});

  @override
  Widget build(BuildContext context) {
    final renk = secili ? Renkler.vurgu : Renkler.metinIkincil;
    return TebesirKutusu(
      kenarRengi: secili ? Renkler.vurgu : Renkler.kenar,
      kesik: kesik,
      kose: 3,
      padding: const EdgeInsets.fromLTRB(5, 3, 5, 2),
      child: Text(Yazi.buyuk(metin), style: Yazi.etiket(boyut: 9.5, renk: renk)),
    );
  }
}
