import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/puan.dart';
import '../providers/liderlik_provider.dart';
import '../services/analitik.dart';
import '../theme/renkler.dart';
import '../theme/yazi.dart';
import '../widgets/takma_ad_sayfasi.dart';
import '../widgets/tebesir.dart';

// Liderlik tablosu (038_puan_ve_liderlik.sql, CLAUDE.md madde 15).
// Dönem sekmeleri (Bugün · Bu Hafta · Tüm Zamanlar), oyun filtresi, ilk üç için kürsü, 4. sıradan itibaren liste.
// Takma adla gösterilir; Google adı ve fotoğrafı gösterilmez. Kullanıcı ilk 50'de değilse kendi satırı altta durur.
class LiderlikScreen extends ConsumerStatefulWidget {
  final LiderlikDonemi donem;

  const LiderlikScreen({super.key, this.donem = LiderlikDonemi.gun});

  @override
  ConsumerState<LiderlikScreen> createState() => _LiderlikScreenState();
}

class _LiderlikScreenState extends ConsumerState<LiderlikScreen> {
  late LiderlikDonemi _donem = widget.donem;
  String? _oyun;

  @override
  void initState() {
    super.initState();
    ref.read(analitikProvider).liderlikAcildi(donem: widget.donem.kod);
  }

  LiderlikSecimi get _secim => (_donem, _oyun);

  // Başkasının satırına uzun basınca: onay penceresi, sonra bildirim (041, Play kullanıcı içeriği politikası)
  Future<void> _bildirmeyiSor(LiderlikSatiri satir) async {
    final kimlik = satir.kullaniciId;
    if (!satir.bildirilebilir || kimlik == null) return;
    final onay = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Renkler.yuzey,
        title: const Text('Bu adı bildir'),
        content: Text("'${satir.ad}' uygunsuz bir takma ad mı? Bildirimini inceleyeceğiz."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(foregroundColor: Renkler.metinIkincil),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Renkler.can),
            child: const Text('Bildir'),
          ),
        ],
      ),
    );
    if (onay != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await takmaAdiBildir(ref, kimlik);
      messenger.showSnackBar(const SnackBar(content: Text('Teşekkürler, inceleyeceğiz.')));
    } on TakmaAdHatasi catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.mesaj)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(bildirimHataMesaji(null))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final sonuc = ref.watch(liderlikProvider(_secim));
    final profil = ref.watch(profilProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('SIRALAMA'),
        actions: [
          IconButton(
            tooltip: 'Puanlama',
            onPressed: () => puanKurallariniGoster(context),
            icon: const Icon(Icons.help_outline_rounded, color: Renkler.metinIkincil),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: TahtaZemini(
        child: SafeArea(
          child: Column(
            children: [
              _DonemSekmeleri(secili: _donem, onSec: (d) => setState(() => _donem = d)),
              const SizedBox(height: 10),
              _OyunFiltresi(secili: _oyun, onSec: (o) => setState(() => _oyun = o)),
              const SizedBox(height: 8),
              if (profil != null && profil.varsayilan)
                _TakmaAdSeridi(ad: profil.takmaAd, onTap: () => takmaAdSayfasiniAc(context)),
              Expanded(
                child: RefreshIndicator(
                  color: Renkler.vurgu,
                  backgroundColor: Renkler.yuzey,
                  onRefresh: () => ref.refresh(liderlikProvider(_secim).future),
                  child: sonuc.hasValue
                      ? _Tablo(sonuc: sonuc.requireValue, donem: _donem, onBildir: _bildirmeyiSor)
                      : sonuc.hasError
                          ? _Hata(onTekrar: () => ref.invalidate(liderlikProvider(_secim)))
                          : const _Iskelet(),
                ),
              ),
              if (sonuc.hasValue && !sonuc.requireValue.benListede)
                _BenimSatirim(ben: sonuc.requireValue.ben, donem: _donem),
            ],
          ),
        ),
      ),
    );
  }
}

class _DonemSekmeleri extends StatelessWidget {
  final LiderlikDonemi secili;
  final ValueChanged<LiderlikDonemi> onSec;

  const _DonemSekmeleri({required this.secili, required this.onSec});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          for (final d in LiderlikDonemi.values)
            Expanded(
              child: InkWell(
                onTap: () => onSec(d),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          Yazi.buyuk(d.ad),
                          style: Yazi.baslik(17, renk: d == secili ? Renkler.vurgu : Renkler.metinIkincil),
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Seçili sekmenin altında tebeşir çizgi
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        height: 2.5,
                        width: d == secili ? 56 : 0,
                        decoration: BoxDecoration(color: Renkler.vurgu, borderRadius: BorderRadius.circular(2)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// Oyun filtresi çipleri. Seçili çipin sarı çerçevesi çiplerden ayrı tek bir katmandır; seçim değişince yeni çipe
// "uzayarak" kayar: gidilen yöndeki kenar önce varır, arkadaki kenar sonra toparlanır.
class _OyunFiltresi extends StatefulWidget {
  final String? secili;
  final ValueChanged<String?> onSec;

  const _OyunFiltresi({required this.secili, required this.onSec});

  @override
  State<_OyunFiltresi> createState() => _OyunFiltresiState();
}

class _OyunFiltresiState extends State<_OyunFiltresi> with SingleTickerProviderStateMixin {
  final _satirAnahtari = GlobalKey();
  final _cipAnahtarlari = [for (final _ in liderlikOyunlari) GlobalKey()];
  late final AnimationController _kayma;

  // Çiplerin satır içindeki yerleri; ilk çizimden sonra ölçülür
  List<Rect>? _yerler;
  // Geçiş başlarken çerçevenin bulunduğu yer (yarım kalan geçişte o anki ara yer)
  Rect? _baslangic;
  late int _hedef = _sira(widget.secili);

  static const _sure = Duration(milliseconds: 420);

  @override
  void initState() {
    super.initState();
    _kayma = AnimationController(vsync: this, duration: _sure, value: 1);
  }

  @override
  void dispose() {
    _kayma.dispose();
    super.dispose();
  }

  int _sira(String? kod) {
    final i = liderlikOyunlari.indexWhere((o) => o.kod == kod);
    return i < 0 ? 0 : i;
  }

  @override
  void didUpdateWidget(covariant _OyunFiltresi eski) {
    super.didUpdateWidget(eski);
    final yeni = _sira(widget.secili);
    if (yeni == _hedef) return;
    // O anki yerden (yarım kalan geçişin ortasındaysa oradan) yeni çipe
    _baslangic = _cerceve();
    _hedef = yeni;
    _kayma.forward(from: 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _cipAnahtarlari[yeni].currentContext;
      if (!mounted || ctx == null) return;
      Scrollable.ensureVisible(ctx, alignment: 0.5, duration: _sure, curve: Curves.easeOutCubic);
    });
  }

  // Çerçevenin şu anki yeri: geçiş sürerken başlangıçla hedef arası
  Rect? _cerceve() {
    final yerler = _yerler;
    if (yerler == null) return null;
    final hedef = yerler[_hedef];
    final bas = _baslangic;
    final t = _kayma.value;
    if (bas == null || t >= 1) return hedef;
    final on = Curves.easeOutCubic.transform((t / 0.6).clamp(0.0, 1.0));
    final arka = Curves.easeInOutCubic.transform(((t - 0.3) / 0.7).clamp(0.0, 1.0));
    final saga = hedef.center.dx >= bas.center.dx;
    final sol = lerpDouble(bas.left, hedef.left, saga ? arka : on);
    final sag = lerpDouble(bas.right, hedef.right, saga ? on : arka);
    return Rect.fromLTRB(sol, lerpDouble(bas.top, hedef.top, t), sag, lerpDouble(bas.bottom, hedef.bottom, t));
  }

  static double lerpDouble(double a, double b, double t) => a + (b - a) * t;

  void _olc() {
    if (!mounted) return;
    final satir = _satirAnahtari.currentContext?.findRenderObject() as RenderBox?;
    if (satir == null || !satir.hasSize) return;
    final yerler = <Rect>[];
    for (final anahtar in _cipAnahtarlari) {
      final kutu = anahtar.currentContext?.findRenderObject() as RenderBox?;
      if (kutu == null || !kutu.hasSize) return;
      yerler.add(kutu.localToGlobal(Offset.zero, ancestor: satir) & kutu.size);
    }
    final eski = _yerler;
    if (eski != null && eski.length == yerler.length && List.generate(yerler.length, (i) => eski[i] == yerler[i]).every((e) => e)) {
      return;
    }
    setState(() => _yerler = yerler);
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _olc());
    // Altı çip var: hepsi kurulur, sığmayanlar yana kaydırılır
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Stack(
        children: [
          Row(
            key: _satirAnahtari,
            children: [
              for (final (i, oyun) in liderlikOyunlari.indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                _cip(i, oyun),
              ],
            ],
          ),
          if (_yerler != null)
            AnimatedBuilder(
              animation: _kayma,
              builder: (context, _) => Positioned.fromRect(
                rect: _cerceve()!,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      color: Renkler.vurgu.withValues(alpha: 0.08),
                      border: Border.all(color: Renkler.vurgu, width: 1.5),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _cip(int i, ({String? kod, String ad}) oyun) {
    final secilmis = oyun.kod == widget.secili;
    // Ölçüm gelene kadar (ilk kare) seçili çip kendi sarı çerçevesini taşır, boş kare görünmesin
    final kendiCercevesi = secilmis && _yerler == null;
    return InkWell(
      key: _cipAnahtarlari[i],
      onTap: () => widget.onSec(oyun.kod),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: kendiCercevesi ? Renkler.vurgu.withValues(alpha: 0.08) : null,
          border: Border.all(color: kendiCercevesi ? Renkler.vurgu : Renkler.kenar, width: 1.5),
        ),
        child: AnimatedDefaultTextStyle(
          duration: _sure,
          curve: Curves.easeOut,
          style: TextStyle(
            color: secilmis ? Renkler.vurgu : Renkler.metinIkincil,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          child: Text(oyun.ad),
        ),
      ),
    );
  }
}

class _TakmaAdSeridi extends StatelessWidget {
  final String ad;
  final VoidCallback onTap;

  const _TakmaAdSeridi({required this.ad, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: TebesirKutusu(
          kesik: true,
          kenarRengi: Renkler.vurgu,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          // Dar ekranda bağlantı alt satıra iner
          child: Wrap(
            spacing: 8,
            runSpacing: 2,
            children: [
              Text(
                "Tabloda '$ad' görünüyorsun.",
                style: const TextStyle(color: Renkler.metinIkincil, fontSize: 13.5),
              ),
              const Text(
                'Takma ad seç →',
                style: TextStyle(color: Renkler.vurgu, fontSize: 13.5, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _bosMetni(LiderlikDonemi donem) => switch (donem) {
      LiderlikDonemi.gun => 'Bugün tahta boş. İlk puanı sen yaz.',
      LiderlikDonemi.hafta => 'Bu hafta tahta boş. İlk puanı sen yaz.',
      LiderlikDonemi.tum => 'Tahta boş. İlk puanı sen yaz.',
    };

String _girilmediMetni(LiderlikDonemi donem) => switch (donem) {
      LiderlikDonemi.gun => 'Bugün puanlı oyun oynamadın.',
      LiderlikDonemi.hafta => 'Bu hafta puanlı oyun oynamadın.',
      LiderlikDonemi.tum => 'Henüz puanlı oyun oynamadın.',
    };

class _Tablo extends StatelessWidget {
  final LiderlikSonucu sonuc;
  final LiderlikDonemi donem;
  final ValueChanged<LiderlikSatiri> onBildir;

  const _Tablo({required this.sonuc, required this.donem, required this.onBildir});

  @override
  Widget build(BuildContext context) {
    final liste = sonuc.liste;
    if (liste.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          const Icon(Icons.emoji_events_outlined, size: 64, color: Renkler.metinSoluk),
          const SizedBox(height: 14),
          Text(
            _bosMetni(donem),
            textAlign: TextAlign.center,
            style: Yazi.tebesir(20, renk: Renkler.metinIkincil, kalinlik: FontWeight.w400),
          ),
        ],
      );
    }

    // İlk üç kürsüde; üçten az kişi varsa sadece liste
    final kursulu = liste.length >= 3;
    final satirlar = kursulu ? liste.skip(3).toList() : liste;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        if (kursulu) ...[
          _Kursu(key: const ValueKey('kursu'), ilkUc: liste.take(3).toList(), onBildir: onBildir),
          const SizedBox(height: 14),
        ],
        for (var i = 0; i < satirlar.length; i++) ...[
          if (i > 0) const KesikCizgi(),
          _Satir(satir: satirlar[i], onBildir: onBildir),
        ],
      ],
    );
  }
}

class _Kursu extends StatelessWidget {
  final List<LiderlikSatiri> ilkUc;
  final ValueChanged<LiderlikSatiri> onBildir;

  const _Kursu({super.key, required this.ilkUc, required this.onBildir});

  @override
  Widget build(BuildContext context) {
    // Ortada 1. (daha yüksek), solda 2., sağda 3.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: _basamak(ilkUc[1], 54)),
        const SizedBox(width: 8),
        Expanded(child: _basamak(ilkUc[0], 78, birinci: true)),
        const SizedBox(width: 8),
        Expanded(child: _basamak(ilkUc[2], 40)),
      ],
    );
  }

  Widget _basamak(LiderlikSatiri satir, double yukseklik, {bool birinci = false}) => _UzunBasinca(
        satir: satir,
        onBildir: onBildir,
        child: _KursuBasamagi(satir: satir, yukseklik: yukseklik, birinci: birinci),
      );
}

class _KursuBasamagi extends StatelessWidget {
  final LiderlikSatiri satir;
  final double yukseklik;
  final bool birinci;

  const _KursuBasamagi({required this.satir, required this.yukseklik, this.birinci = false});

  @override
  Widget build(BuildContext context) {
    final renk = birinci ? Renkler.vurgu : Renkler.metin;
    final harf = satir.ad.isEmpty ? '?' : Yazi.buyuk(satir.ad.characters.first);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: birinci ? 56 : 46,
          height: birinci ? 56 : 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: satir.ben ? Renkler.vurgu : renk, width: 1.5),
          ),
          child: Text(harf, style: Yazi.tebesir(birinci ? 26 : 22, renk: renk)),
        ),
        const SizedBox(height: 6),
        Text(
          satir.ben ? '${satir.ad} (sen)' : satir.ad,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: Yazi.tebesir(17, renk: renk),
        ),
        Text(binlik(satir.puan), style: Yazi.baslik(16, renk: renk).copyWith(fontFeatures: Yazi.sabitRakam)),
        const SizedBox(height: 6),
        Container(
          height: yukseklik,
          alignment: Alignment.topCenter,
          padding: const EdgeInsets.only(top: 6),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: renk, width: 1.5),
              left: BorderSide(color: renk, width: 1.5),
              right: BorderSide(color: renk, width: 1.5),
            ),
          ),
          child: Text('${satir.sira}', style: Yazi.baslik(birinci ? 26 : 20, renk: renk)),
        ),
      ],
    );
  }
}

// Başkasının (takma ad seçmiş) satırına uzun basınca bildirme penceresi açılır. Kendi satırı ve "Oyuncu 3FA9" gibi
// sistemin ürettiği adlar bildirilemez.
class _UzunBasinca extends StatelessWidget {
  final LiderlikSatiri satir;
  final ValueChanged<LiderlikSatiri> onBildir;
  final Widget child;

  const _UzunBasinca({required this.satir, required this.onBildir, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!satir.bildirilebilir) return child;
    return InkWell(
      onLongPress: () => onBildir(satir),
      borderRadius: BorderRadius.circular(6),
      child: child,
    );
  }
}

class _Satir extends StatelessWidget {
  final LiderlikSatiri satir;
  final ValueChanged<LiderlikSatiri> onBildir;

  const _Satir({required this.satir, required this.onBildir});

  @override
  Widget build(BuildContext context) {
    final icerik = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              '${satir.sira}',
              style: Yazi.baslik(20, renk: Renkler.metinIkincil).copyWith(fontFeatures: Yazi.sabitRakam),
            ),
          ),
          Expanded(
            child: Text(
              satir.ben ? '${satir.ad} (sen)' : satir.ad,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Yazi.tebesir(19, renk: satir.ben ? Renkler.vurgu : Renkler.metin),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                binlik(satir.puan),
                style: Yazi.baslik(19, renk: satir.ben ? Renkler.vurgu : Renkler.metin)
                    .copyWith(fontFeatures: Yazi.sabitRakam),
              ),
              const SizedBox(height: 2),
              Text('${satir.oyun} oyun', style: const TextStyle(color: Renkler.metinSoluk, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
    if (!satir.ben) return _UzunBasinca(satir: satir, onBildir: onBildir, child: icerik);
    return TebesirKutusu(kenarRengi: Renkler.vurgu, padding: EdgeInsets.zero, child: icerik);
  }
}

// Kullanıcı ilk 50'de değilse ekranın altında sabit duran kendi satırı
class _BenimSatirim extends StatelessWidget {
  final LiderlikSatiri? ben;
  final LiderlikDonemi donem;

  const _BenimSatirim({required this.ben, required this.donem});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: const BoxDecoration(
        color: Renkler.yuzey,
        border: Border(top: BorderSide(color: Renkler.vurgu, width: 1.5)),
      ),
      child: ben == null
          ? Text(
              '${_girilmediMetni(donem)} Süreli bir oyun oyna, tabloya gir.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Renkler.metinIkincil, fontSize: 14),
            )
          : Text(
              'Sen · ${ben!.sira}. · ${binlik(ben!.puan)} puan',
              textAlign: TextAlign.center,
              style: Yazi.tebesir(20, renk: Renkler.vurgu),
            ),
    );
  }
}

class _Iskelet extends StatelessWidget {
  const _Iskelet();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      children: [
        for (var i = 0; i < 8; i++)
          Container(
            height: 22,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: Renkler.yuzey, borderRadius: BorderRadius.circular(4)),
          ),
      ],
    );
  }
}

class _Hata extends StatelessWidget {
  final VoidCallback onTekrar;

  const _Hata({required this.onTekrar});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 80),
        const Icon(Icons.wifi_off_rounded, size: 40, color: Renkler.metinSoluk),
        const SizedBox(height: 12),
        const Text(
          'Sıralama yüklenemedi.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Renkler.metinIkincil, fontSize: 15),
        ),
        const SizedBox(height: 12),
        Center(child: FilledButton(onPressed: onTekrar, child: const Text('Tekrar dene'))),
      ],
    );
  }
}

// Puanlama kurallarının kısa hâli (sıralama ekranındaki "?")
Future<void> puanKurallariniGoster(BuildContext context) {
  const satirlar = [
    'Her doğru cevap ve her dolu kutu puan getirir.',
    'Zor mod ve kısa süre puanı artırır.',
    'Oyunu kusursuz ve hızlı bitirene bonus var.',
    'Süresiz oyunlar tabloya girmez. Top 10 her zaman puanlıdır.',
  ];
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(Yazi.buyuk('Puanlama'), style: Yazi.baslik(26, kalinlik: FontWeight.w900)),
            const SizedBox(height: 14),
            for (final satir in satirlar)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(satir, style: const TextStyle(color: Renkler.metinIkincil, fontSize: 14, height: 1.4)),
              ),
            const SizedBox(height: 6),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: Text(Yazi.buyuk('Tamam')),
            ),
          ],
        ),
      ),
    ),
  );
}
