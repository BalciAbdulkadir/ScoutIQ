import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/puan.dart';
import '../services/oyun_deposu.dart';
import 'hub_provider.dart';

// Liderlik tablosu: dönem (bugün, bu hafta, tüm zamanlar) ve oyun (null: hepsi). Gün değişince yeniden okunur.
typedef LiderlikSecimi = (LiderlikDonemi, String?);

// Hata olursa kendiliğinden tekrar denenmez: ekranda "Tekrar dene" ve aşağı çekip yenileme var.
final liderlikProvider = FutureProvider.autoDispose.family<LiderlikSonucu, LiderlikSecimi>(
  (ref, secim) {
    ref.watch(bugunProvider);
    final (donem, oyun) = secim;
    return ref.read(oyunDeposuProvider).liderlikTablosu(donem, oyun: oyun);
  },
  retry: (_, _) => null,
);

// Kullanıcının takma adı. Takma ad kaydedilince takmaAdiKaydet bunu ve liderlik tablosunu yeniler.
final profilProvider = FutureProvider.autoDispose<Profil>((ref) => ref.read(oyunDeposuProvider).profilGetir());

// Başkasının takma adını bildirir. Tablo yenilenmez: ad sunucuda üç bildirimden sonra sıfırlanır.
Future<void> takmaAdiBildir(WidgetRef ref, String kullaniciId) =>
    ref.read(oyunDeposuProvider).takmaAdBildir(kullaniciId);

// Takma adı kaydeder; sunucu reddederse TakmaAdHatasi fırlatır
Future<String> takmaAdiKaydet(WidgetRef ref, String ad) async {
  final kaydedilen = await ref.read(oyunDeposuProvider).takmaAdKaydet(ad);
  ref.invalidate(profilProvider);
  ref.invalidate(liderlikProvider);
  return kaydedilen;
}
