import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/hub_provider.dart';
import '../theme/renkler.dart';

// Hub'daki günlük özet: bugün kaç oyunun tamamlandığı ve yeni oyunlara kalan süre
class GunlukKart extends ConsumerStatefulWidget {
  final int tamamlanan;
  final int toplam;

  const GunlukKart({super.key, required this.tamamlanan, required this.toplam});

  @override
  ConsumerState<GunlukKart> createState() => _GunlukKartState();
}

class _GunlukKartState extends ConsumerState<GunlukKart> {
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
    final oran = widget.toplam == 0 ? 0.0 : widget.tamamlanan / widget.toplam;
    final hepsiBitti = widget.toplam > 0 && widget.tamamlanan >= widget.toplam;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Renkler.yuzey,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Renkler.kenar),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Bugün', style: TextStyle(color: Renkler.metinIkincil, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(
                      hepsiBitti ? 'Tüm oyunlar tamamlandı' : '${widget.tamamlanan}/${widget.toplam} oyun tamamlandı',
                      style: const TextStyle(color: Renkler.metin, fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Yeni oyunlar', style: TextStyle(color: Renkler.metinIkincil, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(
                    _sureMetni(_kalan),
                    style: const TextStyle(
                      color: Renkler.metin,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: oran,
              minHeight: 4,
              backgroundColor: Renkler.kenar,
              color: Renkler.basari,
            ),
          ),
        ],
      ),
    );
  }
}
