import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show ClientException;
import 'package:mobile/models/izgara.dart';
import 'package:mobile/models/oyuncu_oneri.dart';
import 'package:mobile/providers/bingo_provider.dart';
import 'package:mobile/providers/bonservis_provider.dart';
import 'package:mobile/providers/game_provider.dart';
import 'package:mobile/providers/izgara_provider.dart';
import 'package:mobile/providers/top10_provider.dart';
import 'package:mobile/services/gunluk_oyun.dart';
import 'package:mobile/services/hata_kaydi.dart';
import 'package:mobile/services/oyun_deposu.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'bingo_test.dart' show bingoDeposu;
import 'bonservis_test.dart' show bonservisDeposu;
import 'izgara_test.dart' show izgaraDeposu;
import 'top10_test.dart' show top10Deposu;
import 'yardimcilar/sahte_oyun_deposu.dart';

// Testler için: gelen hataları kaydeder, hiçbir yere göndermez
class SahteHataKaydi implements HataKaydi {
  final List<({Object hata, OyunIslemi islem, String oyunTipi, int? sure})> hatalar = [];

  @override
  Future<void> oyunHatasi(Object hata, StackTrace iz,
          {required OyunIslemi islem, required String oyunTipi, int? sure}) async =>
      hatalar.add((hata: hata, islem: islem, oyunTipi: oyunTipi, sure: sure));
}

// 043'ten sonra 40 saniyelik açılışta loglarda görülen hata (044_sure_kisiti_duzeltme.sql)
final kisitHatasi = PostgrestException(
  message: 'new row for relation "kullanici_oyun_gecmisi" violates check constraint '
      '"kullanici_oyun_gecmisi_sure_saniye_check"',
  code: '23514',
  details: 'Failing row contains (kullanici-1, ...)',
);

Future<(ProviderContainer, SahteHataKaydi)> ac<T>(SahteOyunDeposu depo, ProviderListenable<T> provider,
    bool Function(T) yukleniyor) async {
  final kayit = SahteHataKaydi();
  final c = ProviderContainer(overrides: [
    oyunDeposuProvider.overrideWithValue(depo),
    hataKaydiProvider.overrideWithValue(kayit),
  ]);
  addTearDown(c.dispose);
  final dinleyici = c.listen(provider, (_, _) {});
  addTearDown(dinleyici.close);
  for (var i = 0; i < 100 && yukleniyor(c.read(provider)); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  return (c, kayit);
}

void main() {
  group('açılışta sunucu hatası kaydedilir, kullanıcıya gösterilen mesaj değişmez', () {
    test('Kesişim 40 saniye', () async {
      final p = gameProvider((oyunTipi: 'kesisim_orta', sure: 40));
      final (c, k) = await ac(SahteOyunDeposu()..oyunAcHatasi = kisitHatasi, p, (GameState s) => s.status == 'loading');

      expect(c.read(p).status, 'error');
      expect(c.read(p).hataMesaji, yuklemeHataMesaji);
      expect(k.hatalar.single.hata, kisitHatasi);
      expect(k.hatalar.single.islem, OyunIslemi.acilis);
      expect(k.hatalar.single.oyunTipi, 'kesisim_orta');
      expect(k.hatalar.single.sure, 40);
    });

    test('Bonservis 40 saniye', () async {
      final p = bonservisProvider((oyunTipi: 'bonservis_zor', sure: 40));
      final (c, k) =
          await ac(bonservisDeposu()..oyunAcHatasi = kisitHatasi, p, (BonservisState s) => s.durum == BonservisDurumu.yukleniyor);

      expect(c.read(p).hataMesaji, yuklemeHataMesaji);
      expect((k.hatalar.single.oyunTipi, k.hatalar.single.sure), ('bonservis_zor', 40));
    });

    test('Izgara 40 saniye', () async {
      final p = izgaraProvider((zorluk: IzgaraZorlugu.kolay, sure: 40));
      final (c, k) = await ac(izgaraDeposu((d) => d.oyunAcHatasi = kisitHatasi), p,
          (IzgaraState s) => s.durum == IzgaraDurumu.yukleniyor);

      expect(c.read(p).hataMesaji, yuklemeHataMesaji);
      expect((k.hatalar.single.oyunTipi, k.hatalar.single.sure), (IzgaraZorlugu.kolay.oyunTipi, 40));
    });

    test('Bingo 60 saniye', () async {
      final p = bingoProvider((oyunTipi: 'bingo', sure: 60));
      final (c, k) =
          await ac(bingoDeposu()..oyunAcHatasi = kisitHatasi, p, (BingoState s) => s.durum == BingoDurumu.yukleniyor);

      expect(c.read(p).hataMesaji, yuklemeHataMesaji);
      expect((k.hatalar.single.oyunTipi, k.hatalar.single.sure), ('bingo', 60));
    });

    test('Top 10 (süresiz)', () async {
      final p = top10Provider('top10');
      final (c, k) =
          await ac(top10Deposu()..oyunAcHatasi = kisitHatasi, p, (Top10State s) => s.durum == Top10Durumu.yukleniyor);

      expect(c.read(p).hataMesaji, yuklemeHataMesaji);
      expect((k.hatalar.single.oyunTipi, k.hatalar.single.sure), ('top10', null));
    });
  });

  test('hamlede gelen hata kaydedilir, mesaj aynı kalır', () async {
    final p = gameProvider((oyunTipi: 'kesisim_kolay', sure: null));
    final depo = SahteOyunDeposu();
    final (c, k) = await ac(depo, p, (GameState s) => s.status == 'loading');
    depo.cevapKontrolHataVerir = true;

    final mesaj = await c.read(p.notifier).makeGuess(const OyuncuOneri(id: 'o-1', isim: 'Arda Güler'));

    expect(mesaj, gonderimHataMesaji);
    expect(k.hatalar.single.islem, OyunIslemi.hamle);
    expect(k.hatalar.single.sure, null);
  });

  test('başarılı açılışta hiçbir şey kaydedilmez', () async {
    final p = gameProvider((oyunTipi: 'kesisim_orta', sure: 40));
    final (c, k) = await ac(SahteOyunDeposu(), p, (GameState s) => s.status == 'loading');

    expect(c.read(p).status, 'playing');
    expect(k.hatalar, isEmpty);
  });

  test('bağlantı hataları ve beklenen durumlar gönderilmez, sunucu hataları gönderilir', () {
    expect(gonderilecekHata(kisitHatasi), isTrue);
    expect(gonderilecekHata(TypeError()), isTrue);
    expect(gonderilecekHata(const SocketException('bağlantı yok')), isFalse);
    expect(gonderilecekHata(TimeoutException('zaman aşımı')), isFalse);
    expect(gonderilecekHata(ClientException('bağlantı yok')), isFalse);
    expect(gonderilecekHata(OyunAcikDegil()), isFalse);
    expect(gonderilecekHata(BaskaModOynandi()), isFalse);
  });

  test('Crashlytics\'e kod, mesaj, oyun tipi ve süre gider; satırın içeriği (details) gitmez', () {
    final bilgiler = hataBilgileri(kisitHatasi, islem: OyunIslemi.acilis, oyunTipi: 'kesisim_orta', sure: 40);

    expect(bilgiler['islem'], 'acilis');
    expect(bilgiler['oyun_tipi'], 'kesisim_orta');
    expect(bilgiler['sure'], '40');
    expect(bilgiler['kod'], '23514');
    expect(bilgiler['mesaj'], contains('kullanici_oyun_gecmisi_sure_saniye_check'));
    expect(bilgiler.toString(), isNot(contains('kullanici-1')));
    expect(SunucuHatasi.from(kisitHatasi).toString(), isNot(contains('kullanici-1')));
    expect(SunucuHatasi.from(kisitHatasi).toString(), startsWith('[23514]'));
  });
}
