import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/bonservis_sorusu.dart';
import '../providers/bonservis_provider.dart';
import '../theme/renkler.dart';
import '../widgets/bonservis_oyuncu_karti.dart';
import '../widgets/oyun_mesaj_karti.dart';

class BonservisScreen extends ConsumerStatefulWidget {
  const BonservisScreen({super.key});

  // Sonuç gösterildikten sonra sıradaki soruya kendiliğinden geçmeden önceki bekleme
  static const sonucBeklemesi = Duration(milliseconds: 1800);

  @override
  ConsumerState<BonservisScreen> createState() => _BonservisScreenState();
}

class _BonservisScreenState extends ConsumerState<BonservisScreen> {
  Timer? _devamZamanlayici;

  @override
  void dispose() {
    _devamZamanlayici?.cancel();
    super.dispose();
  }

  Future<void> _tahminEt(bool dahaFazla) async {
    final hata = await ref.read(bonservisProvider.notifier).tahminEt(dahaFazla: dahaFazla);
    if (!mounted) return;

    if (hata != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(hata)));
      return;
    }

    // Bedel açıldı: kullanıcı sonucu görsün, sonra sıradaki soruya geç
    if (ref.read(bonservisProvider).sonCevapDogru != null) {
      _devamZamanlayici?.cancel();
      _devamZamanlayici = Timer(BonservisScreen.sonucBeklemesi, _devamEt);
    }
  }

  void _devamEt() {
    _devamZamanlayici?.cancel();
    if (!mounted) return;
    ref.read(bonservisProvider.notifier).devamEt();
  }

  @override
  Widget build(BuildContext context) {
    final durum = ref.watch(bonservisProvider);

    return Scaffold(
      backgroundColor: Renkler.arkaPlan,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Bonservis', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(child: _govde(durum)),
    );
  }

  Widget _govde(BonservisState durum) {
    switch (durum.durum) {
      case BonservisDurumu.yukleniyor:
        return const Center(child: CircularProgressIndicator(color: Colors.lightBlueAccent));
      case BonservisDurumu.hata:
        return OyunMesajKarti(baslik: 'Bir sorun oluştu', aciklama: durum.hataMesaji ?? 'Lütfen daha sonra tekrar dene.');
      case BonservisDurumu.oyunYok:
        return const OyunMesajKarti(baslik: 'Bugün için oyun bulunamadı.', aciklama: 'Yarın tekrar gel.');
      case BonservisDurumu.zatenOynandi:
        return OyunMesajKarti(
          baslik: 'Bugünkü Hakkını Doldurdun!',
          aciklama: 'Skorun: ${durum.skor} / 5\nYarın yeni oyuncularla görüşmek üzere.',
        );
      case BonservisDurumu.yaridaBirakildi:
        return OyunMesajKarti(
          baslik: 'Bugünkü Hakkını Kullandın',
          aciklama: 'Oyunu yarıda bıraktığın için tamamlanmış sayıldı.\nSkorun: ${durum.skor} / 5',
        );
      case BonservisDurumu.bitti:
        return _BitisEkrani(durum: durum);
      case BonservisDurumu.oynaniyor:
        return _oyun(durum);
    }
  }

  Widget _oyun(BonservisState durum) {
    final soru = durum.soru!;
    final cevaplandi = durum.sonCevapDogru != null;

    // Büyük ekranda butonlar en altta durur; küçük ekranda içerik sığmazsa sayfa kaydırılır
    return LayoutBuilder(
      builder: (context, kisitlar) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: kisitlar.maxHeight - 28),
          child: IntrinsicHeight(child: _oyunIcerigi(durum, soru, cevaplandi)),
        ),
      ),
    );
  }

  Widget _oyunIcerigi(BonservisState durum, BonservisSorusu soru, bool cevaplandi) {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _IlerlemeCubugu(durum: durum),
          const SizedBox(height: 28),
          const Text(
            'Kariyeri boyunca ödenen toplam bonservis daha mı fazla, daha mı az?',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 15, height: 1.3),
          ),
          const SizedBox(height: 20),
          _gecisli(
            BonservisOyuncuKarti(key: ValueKey('ref-${soru.referans.id}'), oyuncu: soru.referans, bedelGorunur: true),
          ),
          const _VsRozeti(),
          _gecisli(
            BonservisOyuncuKarti(
              key: ValueKey('rakip-${soru.rakip.id}'),
              oyuncu: soru.rakip,
              bedelGorunur: cevaplandi,
              bedelAnimasyonlu: cevaplandi,
              dogru: durum.sonCevapDogru,
            ),
          ),
          const Spacer(),
          const SizedBox(height: 20),
          if (cevaplandi) _SonucBandi(soru: soru, dogru: durum.sonCevapDogru!, sonSoru: durum.sonSoru, onDevam: _devamEt),
          if (!cevaplandi) _tahminButonlari(durum, soru),
        ],
    );
  }

  // Yeni oyuncu geldiğinde kart yandan kayarak girer
  Widget _gecisli(Widget kart) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      transitionBuilder: (child, animasyon) => SlideTransition(
        position: Tween(begin: const Offset(0.15, 0), end: Offset.zero).animate(animasyon),
        child: FadeTransition(opacity: animasyon, child: child),
      ),
      child: kart,
    );
  }

  Widget _tahminButonlari(BonservisState durum, BonservisSorusu soru) {
    final aktif = durum.tahminEdilebilir;

    Widget buton({required String metin, required IconData ikon, required Color renk, required bool dahaFazla}) {
      return Expanded(
        child: SizedBox(
          height: 64,
          child: FilledButton.icon(
            onPressed: aktif ? () => _tahminEt(dahaFazla) : null,
            style: FilledButton.styleFrom(
              backgroundColor: renk,
              foregroundColor: Colors.black,
              disabledBackgroundColor: renk.withValues(alpha: 0.3),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            icon: Icon(ikon, size: 26),
            label: Text(metin, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ),
        ),
      );
    }

    return Column(
      children: [
        Text(
          '${soru.rakip.isim} için tahminin?',
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Renkler.soluk, fontSize: 13),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            buton(metin: 'Daha Az', ikon: Icons.arrow_downward, renk: const Color(0xFFFF8A65), dahaFazla: false),
            const SizedBox(width: 12),
            buton(metin: 'Daha Fazla', ikon: Icons.arrow_upward, renk: Colors.greenAccent, dahaFazla: true),
          ],
        ),
      ],
    );
  }
}

class _IlerlemeCubugu extends StatelessWidget {
  final BonservisState durum;

  const _IlerlemeCubugu({required this.durum});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < durum.sorular.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  height: 8,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: switch (i < durum.sonuclar.length ? durum.sonuclar[i] : null) {
                      true => Colors.greenAccent,
                      false => Colors.redAccent,
                      null => i == durum.soruIndex ? Colors.lightBlueAccent.withValues(alpha: 0.6) : Colors.white12,
                    },
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Soru ${durum.soruIndex + 1} / ${durum.sorular.length}', style: const TextStyle(color: Colors.white70)),
            Text(
              'Skor: ${durum.skor}',
              style: const TextStyle(color: Colors.lightBlueAccent, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
      ],
    );
  }
}

class _VsRozeti extends StatelessWidget {
  const _VsRozeti();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Renkler.arkaPlan,
            border: Border.all(color: Colors.lightBlueAccent.withValues(alpha: 0.6), width: 2),
          ),
          child: const Text('VS', style: TextStyle(color: Colors.lightBlueAccent, fontWeight: FontWeight.w900)),
        ),
      ),
    );
  }
}

class _SonucBandi extends StatelessWidget {
  final BonservisSorusu soru;
  final bool dogru;
  final bool sonSoru;
  final VoidCallback onDevam;

  const _SonucBandi({required this.soru, required this.dogru, required this.sonSoru, required this.onDevam});

  @override
  Widget build(BuildContext context) {
    final renk = dogru ? Colors.greenAccent : Colors.redAccent;
    final fark = (soru.rakip.toplamBonservis - soru.referans.toplamBonservis).abs();
    final aciklama = '${soru.pahaliOlan.isim} ${bonservisMetni(fark)} daha pahalı.';
    final butonMetni = (!dogru || sonSoru) ? 'Sonucu Gör' : 'Sıradaki';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: renk.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: renk.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(dogru ? Icons.check_circle : Icons.cancel, color: renk, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dogru ? 'Doğru!' : 'Yanlış!',
                  style: TextStyle(color: renk, fontSize: 20, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(aciklama, style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),
          TextButton(
            onPressed: onDevam,
            child: Text(butonMetni, style: TextStyle(color: renk, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class _BitisEkrani extends StatelessWidget {
  final BonservisState durum;

  const _BitisEkrani({required this.durum});

  String get _baslik => switch (durum.skor) {
        5 => 'Kusursuz! 🏆',
        4 => 'Harika!',
        2 || 3 => 'Fena değil!',
        _ => 'Bir dahaki sefere!',
      };

  @override
  Widget build(BuildContext context) {
    final oynananSorular = durum.sorular.take(durum.sonuclar.length).toList();

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Center(
          child: Container(
            width: 140,
            height: 140,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.lightBlueAccent, width: 4),
              color: Colors.lightBlueAccent.withValues(alpha: 0.08),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${durum.skor}/${durum.sorular.length}',
                  style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w900),
                ),
                const Text('doğru', style: TextStyle(color: Colors.white60)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          _baslik,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        const Text(
          'Yarın yeni oyuncularla görüşmek üzere.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white60),
        ),
        const SizedBox(height: 28),
        const Text('Bugünün eşleşmeleri', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        for (var i = 0; i < oynananSorular.length; i++) _eslesmeSatiri(oynananSorular[i], durum.sonuclar[i]),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.lightBlueAccent,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: const Text('Ana Menüye Dön', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _eslesmeSatiri(BonservisSorusu soru, bool dogru) {
    Widget oyuncu(BonservisOyuncusu o) {
      final pahali = identical(o, soru.pahaliOlan);
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              o.isim,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: pahali ? Colors.white : Colors.white60, fontWeight: pahali ? FontWeight.bold : FontWeight.normal),
            ),
            Text(
              bonservisMetni(o.toplamBonservis),
              style: TextStyle(color: pahali ? Colors.lightBlueAccent : Colors.white38, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: Renkler.kart, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(dogru ? Icons.check_circle : Icons.cancel, color: dogru ? Colors.greenAccent : Colors.redAccent, size: 20),
          const SizedBox(width: 12),
          oyuncu(soru.referans),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text('vs', style: TextStyle(color: Colors.white38)),
          ),
          oyuncu(soru.rakip),
        ],
      ),
    );
  }
}
