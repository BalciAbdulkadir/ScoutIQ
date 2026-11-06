import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/hub_provider.dart';
import '../theme/renkler.dart';
import '../theme/yazi.dart';
import 'tebesir.dart';

// Ana menünün üstündeki günlük şerit: tarih, biten oyunlar için tebeşir çentikleri ve yeni oyunlara kalan süre
class GunlukSerit extends ConsumerStatefulWidget {
  final int tamamlanan;
  final int toplam;

  const GunlukSerit({super.key, required this.tamamlanan, required this.toplam});

  @override
  ConsumerState<GunlukSerit> createState() => _GunlukSeritState();
}

class _GunlukSeritState extends ConsumerState<GunlukSerit> {
  late Duration _kalan = yenilenmeyeKalanSure();
  Timer? _zamanlayici;

  @override
  void initState() {
    super.initState();
    _zamanlayici = Timer.periodic(const Duration(seconds: 1), (_) {
      final kalan = yenilenmeyeKalanSure();
      // Süre aniden arttıysa gece yarısı geçmiştir: yeni günün durumunu çekiyoruz
      if (kalan > _kalan) {
        ref.invalidate(bugunOynananlarProvider);
      }
      setState(() => _kalan = kalan);
    });
  }

  @override
  void dispose() {
    _zamanlayici?.cancel();
    super.dispose();
  }

  String _sureMetni(Duration sure) {
    String iki(int n) => n.toString().padLeft(2, '0');
    return '${iki(sure.inHours)}:${iki(sure.inMinutes % 60)}:${iki(sure.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    final hepsiBitti = widget.toplam > 0 && widget.tamamlanan >= widget.toplam;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(Yazi.buyuk(tarihMetni(turkiyeSaati())), style: Yazi.etiket()),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Flexible(child: TebesirCentikleri(toplam: widget.toplam, biten: widget.tamamlanan)),
                      const SizedBox(width: 4),
                      Text(
                        hepsiBitti ? 'Hepsi bitti' : '${widget.tamamlanan} / ${widget.toplam}',
                        style: Yazi.tebesir(16, renk: Renkler.vurgu),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('YENİ OYUNLARA', style: Yazi.etiket()),
                const SizedBox(height: 6),
                Text(
                  _sureMetni(_kalan),
                  style: Yazi.baslik(32, kalinlik: FontWeight.w800).copyWith(fontFeatures: Yazi.sabitRakam),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        const KesikCizgi(),
      ],
    );
  }
}
