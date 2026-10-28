import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/oyuncu_oneri.dart';
import 'package:mobile/providers/game_provider.dart';
import 'package:mobile/providers/hub_provider.dart';
import 'package:mobile/services/oyun_deposu.dart';

import 'yardimcilar/sahte_oyun_deposu.dart';

const dogruOyuncu = OyuncuOneri(id: 'o-1', isim: 'Arda Güler');
const yanlisOyuncu = OyuncuOneri(id: 'o-2', isim: 'Mesut Özil');

// Sahte depoyla bir ProviderContainer kurar ve oyunun yüklenmesini bekler
Future<(ProviderContainer, SahteOyunDeposu)> oyunuBaslat([void Function(SahteOyunDeposu)? ayarla]) async {
  final depo = SahteOyunDeposu();
  ayarla?.call(depo);

  final container = ProviderContainer(overrides: [oyunDeposuProvider.overrideWithValue(depo)]);
  addTearDown(container.dispose);

  // autoDispose provider test boyunca canlı kalsın
  container.listen(gameProvider, (_, _) {});
  await yuklenmesiniBekle(container);
  return (container, depo);
}

Future<void> yuklenmesiniBekle(ProviderContainer container) async {
  for (var i = 0; i < 100 && container.read(gameProvider).status == 'loading'; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

GameNotifier notifier(ProviderContainer c) => c.read(gameProvider.notifier);
GameState durum(ProviderContainer c) => c.read(gameProvider);

void main() {
  group('Oyunun açılması', () {
    test('günün oyunu varsa oyun başlar ve kayıt "basladi" olarak açılır', () async {
      final (c, depo) = await oyunuBaslat();

      expect(durum(c).status, 'playing');
      expect(durum(c).questions, hasLength(5));
      expect(depo.kayitAcSayisi, 1);
      expect(depo.kayit, {'skor': 0, 'durum': 'basladi'});
    });

    test('günün oyunu yoksa "no_game" gösterilir ve kayıt açılmaz (hak yanmaz)', () async {
      final (c, depo) = await oyunuBaslat((d) => d.oyun = null);

      expect(durum(c).status, 'no_game');
      expect(depo.kayitAcSayisi, 0);
    });

    test('tarih sunucudan alınır', () async {
      final (c, _) = await oyunuBaslat((d) => d.tarih = '2030-01-15');

      expect(durum(c).tarih, '2030-01-15');
    });

    test('sunucudan tarih alınamazsa Türkiye saatine göre yerel tarih kullanılır', () async {
      final (c, _) = await oyunuBaslat((d) => d.tarihHataVerir = true);

      expect(durum(c).status, 'playing');
      expect(durum(c).tarih, bugununTarihi());
    });

    test('oturum yoksa hata mesajı gösterilir', () async {
      final (c, depo) = await oyunuBaslat((d) => d.kullaniciId = null);

      expect(durum(c).status, 'error');
      expect(durum(c).hataMesaji, contains('Oturum'));
      expect(depo.kayitAcSayisi, 0);
    });

    test('oyun yüklenemezse "oyun bulunamadı" değil, bağlantı hatası gösterilir', () async {
      final (c, _) = await oyunuBaslat((d) => d.oyunYuklemeHataVerir = true);

      expect(durum(c).status, 'error');
      expect(durum(c).hataMesaji, contains('İnternet'));
    });
  });

  group('Kulüp logoları', () {
    test('logosu olmayan eski sorularda logolar kulüp kimliğinden tamamlanır', () async {
      final (c, depo) = await oyunuBaslat((d) {
        d.oyun = {
          'id': 'oyun-1',
          'soru_verisi': [
            {'kulup_a': 'Galatasaray', 'kulup_b': 'Juventus', 'kulup_a_id': 'k-gs', 'kulup_b_id': 'k-juve'},
            {'kulup_a': 'Fenerbahçe', 'kulup_b': 'Ajax', 'kulup_a_id': 'k-fb', 'kulup_b_id': 'k-ajax', 'kulup_a_logo': 'fb.png'},
          ],
        };
        d.logolar = {'k-gs': 'gs.png', 'k-juve': 'juve.png', 'k-ajax': 'ajax.png', 'k-fb': 'baska.png'};
      });
      // Logolar oyun açıldıktan sonra gelir
      await Future<void>.delayed(Duration.zero);

      final sorular = durum(c).questions.cast<Map<String, dynamic>>();
      expect(sorular[0]['kulup_a_logo'], 'gs.png');
      expect(sorular[0]['kulup_b_logo'], 'juve.png');
      expect(sorular[1]['kulup_a_logo'], 'fb.png'); // Soruda olan logo değişmez
      expect(sorular[1]['kulup_b_logo'], 'ajax.png');
      expect(depo.logoIstekSayisi, 1);
    });

    test('sorularda logo varsa kulüpler tekrar sorgulanmaz', () async {
      final (_, depo) = await oyunuBaslat((d) {
        d.oyun = {
          'id': 'oyun-1',
          'soru_verisi': [
            {'kulup_a': 'A', 'kulup_b': 'B', 'kulup_a_id': 'a', 'kulup_b_id': 'b', 'kulup_a_logo': 'a.png', 'kulup_b_logo': 'b.png'},
          ],
        };
      });
      await Future<void>.delayed(Duration.zero);

      expect(depo.logoIstekSayisi, 0);
    });
  });

  group('Günde tek atış', () {
    test('bugün bitirilmiş oyun tekrar açılmaz, skor gösterilir', () async {
      final (c, depo) = await oyunuBaslat((d) => d.kayit = {'skor': 6, 'durum': 'tamamlandi'});

      expect(durum(c).status, 'already_played');
      expect(durum(c).score, 6);
      expect(depo.kayitAcSayisi, 0);
    });

    test('yarıda bırakılan oyun tekrar açılmaz ve kaydı kapatılır', () async {
      final (c, depo) = await oyunuBaslat((d) => d.kayit = {'skor': 4, 'durum': 'basladi'});

      expect(durum(c).status, 'abandoned');
      expect(durum(c).score, 4);
      expect(depo.yarimKayitKapatildi, isTrue);
      expect(depo.kayit!['durum'], 'tamamlandi');
      expect(depo.kayitAcSayisi, 0);
    });

    test('oyun aynı anda başka cihazda başlatıldıysa oyun kilitlenir', () async {
      final (c, _) = await oyunuBaslat((d) => d.kayitAcCakisir = true);

      expect(durum(c).status, 'abandoned');
      expect(durum(c).score, 4);
    });
  });

  group('Cevap kontrolü', () {
    test('doğru cevap +2 puan verir ve skor kayda yazılır', () async {
      final (c, depo) = await oyunuBaslat();

      final hata = await notifier(c).makeGuess(dogruOyuncu);

      expect(hata, isNull);
      expect(durum(c).score, 2);
      expect(durum(c).currentIndex, 1);
      expect(durum(c).lastGuessStatus, 'correct');
      expect(depo.yazilanSkorlar.single, (skor: 2, bitti: false));
    });

    test('yanlış cevap puan vermez ama sonraki soruya geçer', () async {
      final (c, depo) = await oyunuBaslat();

      await notifier(c).makeGuess(yanlisOyuncu);

      expect(durum(c).score, 0);
      expect(durum(c).currentIndex, 1);
      expect(durum(c).lastGuessStatus, 'wrong');
      expect(depo.yazilanSkorlar.single, (skor: 0, bitti: false));
    });

    test('son soruda oyun tamamlanır ve kayıt kilitlenir', () async {
      final (c, depo) = await oyunuBaslat();

      for (var i = 0; i < 5; i++) {
        await notifier(c).makeGuess(i.isEven ? dogruOyuncu : yanlisOyuncu);
      }

      expect(durum(c).status, 'completed');
      expect(durum(c).score, 6);
      expect(durum(c).sonuclar, [true, false, true, false, true]);
      expect(durum(c).cevaplar, ['Arda Güler', 'Mesut Özil', 'Arda Güler', 'Mesut Özil', 'Arda Güler']);
      expect(depo.kayit, {'skor': 6, 'durum': 'tamamlandi'});
      expect(depo.yazilanSkorlar.last, (skor: 6, bitti: true));
    });

    test('cevap gönderilemezse hata döner, soru ilerlemez ve tekrar denenebilir', () async {
      final (c, depo) = await oyunuBaslat((d) => d.cevapKontrolHataVerir = true);

      final hata = await notifier(c).makeGuess(dogruOyuncu);

      expect(hata, contains('gönderilemedi'));
      expect(durum(c).currentIndex, 0);
      expect(durum(c).gonderiliyor, isFalse);

      depo.cevapKontrolHataVerir = false;
      await notifier(c).makeGuess(dogruOyuncu);
      expect(durum(c).currentIndex, 1);
    });

    test('kayıt başka yerden kapatıldıysa oyun kilitlenir', () async {
      final (c, depo) = await oyunuBaslat();
      depo.kayit = {'skor': 0, 'durum': 'tamamlandi'};

      await notifier(c).makeGuess(dogruOyuncu);

      expect(durum(c).status, 'already_played');
    });
  });

  group('Oyun sonu doğru cevaplar', () {
    test('oyun bitince yanlış cevap varsa örnek doğru cevaplar getirilir', () async {
      final (c, depo) = await oyunuBaslat();

      for (var i = 0; i < 5; i++) {
        await notifier(c).makeGuess(i == 1 ? yanlisOyuncu : dogruOyuncu);
      }

      expect(depo.ornekCevaplarSayisi, 1);
      expect(durum(c).ornekCevaplar[1], 'Doğru Oyuncu 1');
    });

    test('oyun sürerken doğru cevaplar istenmez', () async {
      final (c, depo) = await oyunuBaslat();

      await notifier(c).makeGuess(yanlisOyuncu);
      await notifier(c).makeGuess(yanlisOyuncu);

      expect(depo.ornekCevaplarSayisi, 0);
      expect(durum(c).ornekCevaplar, isEmpty);
    });

    test('hepsi doğruysa doğru cevaplar istenmez', () async {
      final (c, depo) = await oyunuBaslat();

      for (var i = 0; i < 5; i++) {
        await notifier(c).makeGuess(dogruOyuncu);
      }

      expect(depo.ornekCevaplarSayisi, 0);
    });

    test('doğru cevaplar getirilemezse oyun yine düzgün biter', () async {
      final (c, _) = await oyunuBaslat((d) => d.ornekCevaplarHataVerir = true);

      String? sonHata;
      for (var i = 0; i < 5; i++) {
        sonHata = await notifier(c).makeGuess(yanlisOyuncu);
      }

      expect(sonHata, isNull);
      expect(durum(c).status, 'completed');
      expect(durum(c).ornekCevaplar, isEmpty);
    });
  });

  group('Çift gönderim', () {
    test('cevap kontrol edilirken ikinci gönderim yok sayılır', () async {
      final (c, depo) = await oyunuBaslat((d) => d.cevapKontrolBekletici = Completer<void>());

      final ilk = notifier(c).makeGuess(dogruOyuncu);
      expect(durum(c).gonderiliyor, isTrue);
      final ikinci = notifier(c).makeGuess(dogruOyuncu);

      depo.cevapKontrolBekletici!.complete();
      await Future.wait([ilk, ikinci]);

      expect(depo.cevapKontrolSayisi, 1);
      expect(durum(c).score, 2);
      expect(durum(c).currentIndex, 1);
    });

    test('son soruda çift gönderim skoru iki kez yazmaz', () async {
      final (c, depo) = await oyunuBaslat();
      for (var i = 0; i < 4; i++) {
        await notifier(c).makeGuess(dogruOyuncu);
      }

      depo.cevapKontrolBekletici = Completer<void>();
      final ilk = notifier(c).makeGuess(dogruOyuncu);
      final ikinci = notifier(c).makeGuess(dogruOyuncu);
      depo.cevapKontrolBekletici!.complete();
      await Future.wait([ilk, ikinci]);

      expect(depo.cevapKontrolSayisi, 5);
      expect(depo.yazilanSkorlar.where((s) => s.bitti), hasLength(1));
      expect(durum(c).score, 10);
    });

    test('oyun bittikten sonra gelen gönderim yok sayılır', () async {
      final (c, depo) = await oyunuBaslat();
      for (var i = 0; i < 5; i++) {
        await notifier(c).makeGuess(dogruOyuncu);
      }

      await notifier(c).makeGuess(dogruOyuncu);

      expect(depo.cevapKontrolSayisi, 5);
      expect(durum(c).gonderiliyor, isTrue);
    });
  });
}
