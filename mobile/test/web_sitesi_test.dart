import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/screens/profil_screen.dart';

// Repo kökündeki web_sitesi/ (footylore.web.app): Google izin ekranı ve Google Play için ana sayfa, gizlilik politikası ve
// hesap silme sayfası. Sitede JavaScript, çerez ve takip kodu olmaz; dışarıya istek atılmaz.
void main() {
  final site = Directory('../web_sitesi');
  const sayfalar = ['index.html', 'gizlilik.html', 'hesap-silme.html', '404.html'];
  String oku(String ad) => File('${site.path}/$ad').readAsStringSync();

  test('üç sayfa ve 404 var', () {
    for (final ad in sayfalar) {
      expect(File('${site.path}/$ad').existsSync(), isTrue, reason: ad);
    }
  });

  test('hiçbir sayfada JavaScript, dış kaynak ya da çerez yok', () {
    for (final ad in [...sayfalar, 'stil.css']) {
      final icerik = oku(ad);
      expect(icerik, isNot(contains('<script')), reason: ad);
      expect(RegExp(r'\son[a-z]+\s*=', caseSensitive: false).hasMatch(icerik), isFalse, reason: '$ad: olay özniteliği');
      expect(icerik, isNot(contains('javascript:')), reason: ad);
      expect(icerik.toLowerCase(), isNot(contains('cookie')), reason: ad);
      // Kaynaklar (stil, görsel, font) sitenin içinden yüklenir; dışarıya sadece tıklanan bağlantılar gider
      for (final m in RegExp(r'''(?:src|href)=["']([^"']+)["']''').allMatches(icerik)) {
        final adres = m.group(1)!;
        final etiket = icerik.substring(icerik.lastIndexOf('<', m.start), m.start);
        if (etiket.startsWith('<a')) continue;
        expect(adres, startsWith('/'), reason: '$ad: $adres');
      }
      expect(RegExp(r'url\(\s*["'"'"']?https?:').hasMatch(icerik), isFalse, reason: '$ad: dış font ya da görsel');
    }
  });

  test('ana sayfa çerez ve takip kodu olmadığını yazar, gizlilik bağlantısı görünür', () {
    final ana = oku('index.html');
    expect(ana, contains('çerez, analitik ve takip kodu yoktur'));
    expect(ana, contains('href="/gizlilik"'));
    expect(ana, contains("Yakında Google Play'de"));
  });

  test('her sayfanın altında gizlilik, hesap silme, iletişim ve son güncelleme var', () {
    for (final ad in sayfalar) {
      final alt = oku(ad).split('<footer').last;
      expect(alt, contains('href="/gizlilik"'), reason: ad);
      expect(alt, contains('href="/hesap-silme"'), reason: ad);
      expect(alt, contains('mailto:'), reason: ad);
      expect(alt, contains('Son güncelleme'), reason: ad);
    }
  });

  test('hesap silme sayfası uygulamadaki adımlarla aynı', () {
    final silme = oku('hesap-silme.html');
    final profil = File('lib/screens/profil_screen.dart').readAsStringSync();
    // Düğme ve iki onayın metinleri uygulamadakiyle aynı
    for (final metin in ['Hesabımı sil', 'Devam']) {
      expect(silme, contains('<strong>$metin</strong>'));
      expect(profil, contains("'$metin'"));
    }
    expect(profil, contains("title: const Text('HESAP')"));
  });

  test("uygulamadaki gizlilik bağlantısı sitedeki sayfayı gösterir", () {
    expect(gizlilikPolitikasiAdresi, 'https://footylore.web.app/gizlilik');
  });

  test('Firebase ayarı sadece hosting içerir ve sadece footylore sitesine yayın yapar', () {
    final ayar = jsonDecode(File('../firebase.json').readAsStringSync()) as Map<String, dynamic>;
    expect(ayar.keys, ['hosting']);
    final hosting = (ayar['hosting'] as List).cast<Map<String, dynamic>>();
    expect(hosting, hasLength(1));
    expect(hosting.single['target'], 'footylore');
    expect(hosting.single['public'], 'web_sitesi');
    expect(hosting.single['cleanUrls'], isTrue);
    expect(hosting.single.containsKey('site'), isFalse); // Site hedef üzerinden seçilir, varsayılan siteye gitmez

    final hedefler = jsonDecode(File('../.firebaserc').readAsStringSync()) as Map<String, dynamic>;
    expect(hedefler['projects'], {'default': 'scoutiq-511311'});
    expect(hedefler['targets'], {
      'scoutiq-511311': {
        'hosting': {
          'footylore': ['footylore'],
        },
      },
    });
  });
}
