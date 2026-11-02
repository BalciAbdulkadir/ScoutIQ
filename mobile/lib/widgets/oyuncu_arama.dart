import 'dart:async';

import 'package:flutter/material.dart';
import '../models/oyuncu_oneri.dart';
import '../theme/renkler.dart';
import 'oyuncu_fotografi.dart';

// Cevap kutusu ve altındaki öneri listesi. Cevap sadece listeden seçilebilir, seçilen oyuncu gönder butonuyla gönderilir.
// Kesişim ve Izgara ortak kullanır.
class OyuncuArama extends StatefulWidget {
  final Color renk;
  final bool gonderiliyor;
  // Tüm oyuncular arasında arar, doğru cevabı ele vermez
  final Future<List<OyuncuOneri>> Function(String metin) ara;
  // Seçilen oyuncuyu gönderir. Hata olursa mesajını döndürür, başarılıysa null (kutu temizlenir).
  final Future<String?> Function(OyuncuOneri oyuncu) gonder;

  const OyuncuArama({
    super.key,
    required this.renk,
    required this.gonderiliyor,
    required this.ara,
    required this.gonder,
  });

  @override
  State<OyuncuArama> createState() => _OyuncuAramaState();
}

class _OyuncuAramaState extends State<OyuncuArama> {
  final TextEditingController _controller = TextEditingController();

  List<OyuncuOneri> _oneriler = [];
  OyuncuOneri? _secilenOyuncu;
  bool _araniyor = false;
  Timer? _aramaZamanlayici;
  int _aramaNo = 0; // Geç gelen eski arama sonuçlarının yenilerinin üstüne yazılmasını engeller

  @override
  void dispose() {
    _aramaZamanlayici?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _metinDegisti(String metin) {
    // Seçimden sonra metin değiştirilirse seçim geçersiz olur
    if (_secilenOyuncu != null && metin != _secilenOyuncu!.isim) {
      setState(() => _secilenOyuncu = null);
    }

    _aramaZamanlayici?.cancel();
    final arama = metin.trim();
    if (arama.length < 2 || _secilenOyuncu != null) {
      setState(() {
        _oneriler = [];
        _araniyor = false;
      });
      return;
    }

    setState(() => _araniyor = true);
    // Her tuşta sunucuya gitmemek için yazmanın bitmesini kısaca bekliyoruz
    _aramaZamanlayici = Timer(const Duration(milliseconds: 300), () => _ara(arama));
  }

  Future<void> _ara(String arama) async {
    final buArama = ++_aramaNo;
    try {
      final sonuc = await widget.ara(arama);
      if (!mounted || buArama != _aramaNo) return;
      setState(() {
        _oneriler = sonuc;
        _araniyor = false;
      });
    } catch (_) {
      if (!mounted || buArama != _aramaNo) return;
      setState(() {
        _oneriler = [];
        _araniyor = false;
      });
    }
  }

  void _oyuncuSec(OyuncuOneri oyuncu) {
    _aramaZamanlayici?.cancel();
    _aramaNo++;
    _controller.value = TextEditingValue(
      text: oyuncu.isim,
      selection: TextSelection.collapsed(offset: oyuncu.isim.length),
    );
    setState(() {
      _secilenOyuncu = oyuncu;
      _oneriler = [];
      _araniyor = false;
    });
  }

  Future<void> _gonder() async {
    final secilen = _secilenOyuncu;
    if (secilen == null) {
      _mesajGoster('Cevabını listeden seçmelisin.');
      return;
    }

    final hata = await widget.gonder(secilen);
    if (!mounted) return;

    if (hata != null) {
      _mesajGoster(hata);
      return;
    }

    _controller.clear();
    setState(() {
      _secilenOyuncu = null;
      _oneriler = [];
    });
  }

  void _mesajGoster(String mesaj) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mesaj)));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [_cevapAlani(), _oneriListesi()],
    );
  }

  Widget _cevapAlani() {
    final gonderilebilir = _secilenOyuncu != null && !widget.gonderiliyor;

    OutlineInputBorder kenarlik(Color renk) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: renk),
        );

    return TextField(
      controller: _controller,
      enabled: !widget.gonderiliyor,
      style: const TextStyle(color: Renkler.metin, fontSize: 16),
      cursorColor: widget.renk,
      textInputAction: TextInputAction.send,
      textCapitalization: TextCapitalization.words,
      onChanged: _metinDegisti,
      onSubmitted: (_) => _gonder(),
      decoration: InputDecoration(
        hintText: 'Oyuncu ara',
        hintStyle: const TextStyle(color: Renkler.metinSoluk),
        filled: true,
        fillColor: Renkler.yuzey,
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        enabledBorder: kenarlik(_secilenOyuncu != null ? widget.renk : Renkler.kenar),
        focusedBorder: kenarlik(widget.renk),
        disabledBorder: kenarlik(Renkler.kenar),
        prefixIcon: _secilenOyuncu != null
            ? Icon(Icons.check_circle, color: widget.renk, size: 22)
            : const Icon(Icons.search_rounded, color: Renkler.metinSoluk),
        suffixIcon: widget.gonderiliyor
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : IconButton(
                tooltip: 'Gönder',
                icon: Icon(Icons.send, color: gonderilebilir ? widget.renk : Renkler.metinSoluk),
                onPressed: gonderilebilir ? _gonder : null,
              ),
      ),
    );
  }

  Widget _oneriListesi() {
    if (_araniyor) {
      return const Padding(
        padding: EdgeInsets.only(top: 16),
        child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }

    if (_secilenOyuncu != null || _controller.text.trim().length < 2) {
      return const SizedBox.shrink();
    }

    if (_oneriler.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 14, left: 4),
        child: Text('Bu isimde oyuncu bulunamadı.', style: TextStyle(color: Renkler.metinSoluk)),
      );
    }

    // Renk Material'da: ListTile dokunma efektini en yakın Material'a çizer, renkli bir kutu onu gizlerdi
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: Renkler.yuzey,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var i = 0; i < _oneriler.length; i++) ...[
              if (i > 0) const Divider(indent: 16, endIndent: 16),
              ListTile(
                dense: true,
                leading: OyuncuFotografi(isim: _oneriler[i].isim, fotoUrl: _oneriler[i].fotoUrl, boyut: 32),
                title: Text(_oneriler[i].isim, style: const TextStyle(color: Renkler.metin, fontSize: 15)),
                trailing: const Icon(Icons.north_west_rounded, size: 16, color: Renkler.metinSoluk),
                onTap: () => _oyuncuSec(_oneriler[i]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
