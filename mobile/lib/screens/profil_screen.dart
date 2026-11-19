import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/auth_provider.dart';
import '../providers/hub_provider.dart';
import '../theme/renkler.dart';
import '../theme/yazi.dart';
import '../widgets/kullanici_avatari.dart';
import '../widgets/tebesir.dart';

// Gizlilik politikasının yayınlandığı sayfa
const gizlilikPolitikasiAdresi = 'https://footylore.app/gizlilik';

// Hesap sayfası: giriş yapılan hesap, çıkış, gizlilik politikası ve hesap silme (Google Play zorunluluğu).
// Çıkış ya da silme sonrası oturum kapanınca uygulama giriş ekranına döner (main.dart oturumu dinler);
// bu sayfa da kapanır ki giriş ekranının üstünde kalmasın.
class ProfilScreen extends ConsumerStatefulWidget {
  const ProfilScreen({super.key});

  @override
  ConsumerState<ProfilScreen> createState() => _ProfilScreenState();
}

class _ProfilScreenState extends ConsumerState<ProfilScreen> {
  bool _isleniyor = false;

  @override
  Widget build(BuildContext context) {
    final kullanici = ref.watch(kullaniciProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('HESAP')),
      body: TahtaZemini(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              Row(
                children: [
                  KullaniciAvatari(kullanici: kullanici, yaricap: 28),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(kullanici?.ad ?? '', style: Yazi.baslik(22)),
                        if (kullanici?.eposta != null) ...[
                          const SizedBox(height: 2),
                          Text(kullanici!.eposta!, style: const TextStyle(color: Renkler.metinIkincil, fontSize: 14)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Divider(color: Renkler.kenar, height: 1),
              _Satir(
                ikon: Icons.privacy_tip_outlined,
                metin: 'Gizlilik politikası',
                sonIkon: Icons.open_in_new_rounded,
                onTap: _isleniyor ? null : _gizlilikPolitikasiniAc,
              ),
              _Satir(
                ikon: Icons.logout_rounded,
                metin: 'Çıkış yap',
                onTap: _isleniyor ? null : _cikisYap,
              ),
              const Divider(color: Renkler.kenar, height: 1),
              const SizedBox(height: 32),
              OutlinedButton.icon(
                onPressed: _isleniyor ? null : _hesabiSil,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Renkler.can,
                  side: const BorderSide(color: Renkler.can, width: 1.4),
                  minimumSize: const Size.fromHeight(50),
                ),
                icon: _isleniyor
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Renkler.can),
                      )
                    : const Icon(Icons.delete_forever_rounded),
                label: const Text('Hesabımı sil'),
              ),
              const SizedBox(height: 10),
              const Text(
                'Hesabın ve bütün oyun geçmişin kalıcı olarak silinir.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Renkler.metinSoluk, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _gizlilikPolitikasiniAc() async {
    final acildi = await launchUrl(Uri.parse(gizlilikPolitikasiAdresi), mode: LaunchMode.externalApplication)
        .catchError((_) => false);
    if (!acildi && mounted) _mesajGoster('Bağlantı açılamadı: $gizlilikPolitikasiAdresi');
  }

  Future<void> _cikisYap() async {
    final onay = await _onayIste(
      baslik: 'Çıkış yapılsın mı?',
      icerik: 'Tekrar oynamak için Google hesabınla yeniden giriş yapman gerekecek.',
      onayMetni: 'Çıkış yap',
    );
    if (!onay || !mounted) return;

    setState(() => _isleniyor = true);
    try {
      await ref.read(authServiceProvider).signOut();
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isleniyor = false);
      _mesajGoster('Çıkış yapılamadı. Bağlantını kontrol edip tekrar dene.');
    }
  }

  // İki adımlı onay: önce ne olacağı, sonra son karar
  Future<void> _hesabiSil() async {
    final ilk = await _onayIste(
      baslik: 'Hesabın silinsin mi?',
      icerik: 'Tüm oyun geçmişin silinecek, geri alınamaz.',
      onayMetni: 'Devam',
    );
    if (!ilk || !mounted) return;

    final son = await _onayIste(
      baslik: 'Emin misin?',
      icerik: 'Hesabın ve bütün oyun geçmişin kalıcı olarak silinecek. Bu işlem geri alınamaz.',
      onayMetni: 'Hesabımı sil',
    );
    if (!son || !mounted) return;

    setState(() => _isleniyor = true);
    try {
      await ref.read(authServiceProvider).hesabimiSil();
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isleniyor = false);
      _mesajGoster('Hesap silinemedi. Bağlantını kontrol edip tekrar dene.');
    }
  }

  Future<bool> _onayIste({required String baslik, required String icerik, required String onayMetni}) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Renkler.yuzey,
        title: Text(baslik),
        content: Text(icerik),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(foregroundColor: Renkler.metinIkincil),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Renkler.can),
            child: Text(onayMetni),
          ),
        ],
      ),
    );
    return onay ?? false;
  }

  void _mesajGoster(String mesaj) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mesaj)));
  }
}

class _Satir extends StatelessWidget {
  final IconData ikon;
  final String metin;
  final IconData? sonIkon;
  final VoidCallback? onTap;

  const _Satir({required this.ikon, required this.metin, this.sonIkon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(ikon, color: Renkler.metinIkincil),
      title: Text(metin, style: const TextStyle(color: Renkler.metin, fontSize: 16, fontWeight: FontWeight.w600)),
      trailing: sonIkon == null ? null : Icon(sonIkon, color: Renkler.metinSoluk, size: 18),
      onTap: onTap,
    );
  }
}
