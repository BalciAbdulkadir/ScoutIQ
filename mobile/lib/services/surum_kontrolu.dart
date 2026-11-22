import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// Zorunlu güncelleme (041_yayin_oncesi.sql). Uygulama açılışta, girişten önce sunucudaki en düşük sürüm kodunu okur.
// Telefondaki sürüm kodu (pubspec.yaml'da "+"dan sonraki sayı) bundan küçükse "Güncelleme gerekli" sayfası açılır.
// Okuma başarısız olursa (internet yok, tablo yok) uygulama engellenmez, normal açılır.

const varsayilanGuncellemeMesaji = "Bu sürüm artık desteklenmiyor. Oynamaya devam etmek için FootyLore'u güncelle.";

// Saf karşılaştırma. Sürüm kodu sayı değilse ya da sunucu sınır vermediyse güncelleme istenmez (uygulama engellenmez).
bool guncellemeGerekli({required String surumKodu, required int? enDusukSurumKodu}) {
  final kod = int.tryParse(surumKodu.trim());
  if (kod == null || enDusukSurumKodu == null) return false;
  return kod < enDusukSurumKodu;
}

// Gösterilecek mesaj: sunucudaki mesaj boşsa uygulamanın kendi mesajı
String guncellemeMesaji(String? sunucuMesaji) {
  final mesaj = sunucuMesaji?.trim() ?? '';
  return mesaj.isEmpty ? varsayilanGuncellemeMesaji : mesaj;
}

typedef SurumSarti = ({int enDusukSurumKodu, String? mesaj});

// Sunucudaki sürüm sınırı. Testlerde sahtesi verilir.
abstract class SurumDeposu {
  // Satır yoksa null
  Future<SurumSarti?> oku();
}

class SupabaseSurumDeposu implements SurumDeposu {
  final SupabaseClient _supabase;

  SupabaseSurumDeposu(this._supabase);

  @override
  Future<SurumSarti?> oku() async {
    final satir = await _supabase
        .from('uygulama_surumu')
        .select('en_dusuk_surum_kodu, guncelleme_mesaji')
        .eq('id', 1)
        .maybeSingle();
    if (satir == null) return null;
    return (
      enDusukSurumKodu: (satir['en_dusuk_surum_kodu'] as num).toInt(),
      mesaj: satir['guncelleme_mesaji'] as String?,
    );
  }
}

final surumDeposuProvider = Provider<SurumDeposu>((ref) => SupabaseSurumDeposu(Supabase.instance.client));

// Telefondaki sürüm kodu (Android versionCode). Testlerde sahtesi verilir.
final surumKoduProvider = Provider<Future<String> Function()>(
  (ref) => () async => (await PackageInfo.fromPlatform()).buildNumber,
);

// Yavaş bağlantıda açılış en fazla bu kadar bekler, sonra uygulama normal açılır
const surumKontroluSuresi = Duration(seconds: 5);

// null: güncelleme gerekmiyor ya da öğrenilemedi. Değilse "Güncelleme gerekli" sayfasının mesajı.
final zorunluGuncellemeProvider = FutureProvider<String?>((ref) async {
  try {
    final (sart, kod) =
        await (ref.read(surumDeposuProvider).oku(), ref.read(surumKoduProvider)()).wait.timeout(surumKontroluSuresi);
    if (sart == null || !guncellemeGerekli(surumKodu: kod, enDusukSurumKodu: sart.enDusukSurumKodu)) return null;
    return guncellemeMesaji(sart.mesaj);
  } catch (_) {
    return null;
  }
});

// Play sayfasını açar; açılamazsa false. Testlerde sahtesi verilir.
final baglantiAciciProvider = Provider<Future<bool> Function(Uri adres)>(
  (ref) => (adres) => launchUrl(adres, mode: LaunchMode.externalApplication).catchError((_) => false),
);
