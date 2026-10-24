import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/hub_provider.dart';
import '../theme/renkler.dart';

// Hub'ın üstündeki "Günün Bulmacaları" kartı: yenilenmeye kalan süre ve günlük ilerleme
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E6B3A), Color(0xFF0F3D22)],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'GÜNÜN BULMACALARI',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  hepsiBitti ? 'Bugünlük bu kadar!' : 'Yeni bulmacalara kalan süre',
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  _sureMetni(_kalan),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Her oyun günde yalnızca bir kez oynanır.',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 76,
            height: 76,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: oran,
                  strokeWidth: 7,
                  strokeCap: StrokeCap.round,
                  backgroundColor: Colors.white12,
                  color: Renkler.vurgu,
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${widget.tamamlanan}/${widget.toplam}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Text('oyun', style: TextStyle(color: Colors.white60, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
