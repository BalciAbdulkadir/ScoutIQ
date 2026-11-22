import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/puan.dart';
import '../providers/liderlik_provider.dart';
import '../theme/renkler.dart';
import '../theme/yazi.dart';

// Takma ad seçimi (alt sayfa). Sıralamada bu ad görünür; Google adı ve fotoğrafı gösterilmez.
// Kurallar sunucudadır (takma_ad_kaydet, 038 ve 041): 3-16 karakter, harf/rakam/_/., benzersiz, küfürsüz, 7 günde bir.
// Kaydedilirse true döner.
Future<bool> takmaAdSayfasiniAc(BuildContext context, {String? mevcut}) async {
  final kaydedildi = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => TakmaAdSayfasi(mevcut: mevcut),
  );
  return kaydedildi ?? false;
}

// Takma ad bildirildiği için sıfırlandı (041): kullanıcı tabloda varsayılan adla duruyor, yeni ad seçmesi istenir
Future<void> takmaAdSifirlandiPenceresi(BuildContext context) async {
  final sec = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Renkler.yuzey,
      title: const Text('Takma adın sıfırlandı'),
      content: const Text(
        'Takma adın bildirildiği için sıfırlandı, yeni bir ad seç. Puanın ve sıralamadaki yerin duruyor.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          style: TextButton.styleFrom(foregroundColor: Renkler.metinIkincil),
          child: const Text('Sonra'),
        ),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yeni ad seç')),
      ],
    ),
  );
  if (sec == true && context.mounted) await takmaAdSayfasiniAc(context);
}

class TakmaAdSayfasi extends ConsumerStatefulWidget {
  final String? mevcut; // Varsayılan ad değilse alana yazılır

  const TakmaAdSayfasi({super.key, this.mevcut});

  @override
  ConsumerState<TakmaAdSayfasi> createState() => _TakmaAdSayfasiState();
}

class _TakmaAdSayfasiState extends ConsumerState<TakmaAdSayfasi> {
  late final _alan = TextEditingController(text: widget.mevcut ?? '');
  String? _hata;
  bool _kaydediliyor = false;

  @override
  void dispose() {
    _alan.dispose();
    super.dispose();
  }

  Future<void> _kaydet() async {
    final ad = _alan.text.trim();
    if (ad.length < 3) {
      setState(() => _hata = takmaAdHataMesaji('takma_ad_gecersiz'));
      return;
    }

    final onay = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Takma adın kaydedilsin mi?'),
        content: const Text('Takma adını 7 gün boyunca değiştiremezsin. Devam?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Kaydet')),
        ],
      ),
    );
    if (onay != true || !mounted) return;

    setState(() {
      _kaydediliyor = true;
      _hata = null;
    });
    try {
      await takmaAdiKaydet(ref, ad);
      if (mounted) Navigator.pop(context, true);
    } on TakmaAdHatasi catch (e) {
      if (mounted) setState(() => _hata = e.mesaj);
    } catch (_) {
      if (mounted) setState(() => _hata = takmaAdHataMesaji(null));
    } finally {
      if (mounted) setState(() => _kaydediliyor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        // Klavye açılınca sayfa yukarı kalkar
        padding: EdgeInsets.fromLTRB(20, 0, 20, 18 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(Yazi.buyuk('Takma adın'), style: Yazi.baslik(26, kalinlik: FontWeight.w900)),
            const SizedBox(height: 6),
            const Text(
              'Sıralamada bu ad görünür. Google adın ve fotoğrafın gösterilmez.',
              style: TextStyle(color: Renkler.metinIkincil, fontSize: 14, height: 1.35),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _alan,
              autofocus: true,
              maxLength: 16,
              enabled: !_kaydediliyor,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _kaydet(),
              style: Yazi.tebesir(22),
              decoration: InputDecoration(
                hintText: 'ör. tribun_kartali',
                errorText: _hata,
                errorStyle: const TextStyle(color: Renkler.hata, fontSize: 13),
                errorMaxLines: 2,
              ),
            ),
            const Text(
              '3-16 karakter; harf, rakam, _ ve .',
              style: TextStyle(color: Renkler.metinSoluk, fontSize: 12.5),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _kaydediliyor ? null : _kaydet,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: _kaydediliyor
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(Yazi.buyuk('Kaydet')),
            ),
          ],
        ),
      ),
    );
  }
}

// Kullanıcının ilk puanlı oyunu bitince takma ad bir kez sorulur (cihazda takma_ad_soruldu bayrağı).
// Testlerde sahtesi verilir.
abstract class TakmaAdSorusu {
  Future<bool> soruldu();
  Future<void> isaretle();
}

class YerelTakmaAdSorusu implements TakmaAdSorusu {
  static const _anahtar = 'takma_ad_soruldu';

  const YerelTakmaAdSorusu();

  @override
  Future<bool> soruldu() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(_anahtar) ?? false;
    } catch (_) {
      return true; // Okunamazsa sorulmaz; kullanıcı sıralama ekranından ve Hesap sayfasından seçebilir
    }
  }

  @override
  Future<void> isaretle() async {
    try {
      await (await SharedPreferences.getInstance()).setBool(_anahtar, true);
    } catch (_) {}
  }
}

final takmaAdSorusuProvider = Provider<TakmaAdSorusu>((ref) => const YerelTakmaAdSorusu());
