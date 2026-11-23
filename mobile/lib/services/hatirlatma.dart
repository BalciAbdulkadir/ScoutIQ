import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_veri;
import 'package:timezone/timezone.dart' as tz;
import '../theme/renkler.dart';

// Akşam hatırlatması: kullanıcı o gün hiç oyun bitirmediyse 20.00'de (Türkiye saati) yerel bildirim.
// Sunucu yoktur, bildirimler telefonda kurulur. Önümüzdeki 7 günün her biri için ayrı bildirim kurulur:
// uygulama birkaç gün açılmasa da her akşam bir hatırlatma gelir. O gün bir oyun bitince o günün bildirimi silinir.
// Uygulama her açılışta (ana menü) planı yeniden kurar.

const hatirlatmaSaati = 20;
const hatirlatmaGunSayisi = 7;
const _hatirlatmaKanali = 'gunluk_hatirlatma';

// Bildirim çubuğundaki görünüm: beyaz top simgesi (res/drawable/ic_bildirim.xml; Android sadece şeklini kullanır)
// ve tahta yeşili vurgu. Simge adı koddan okunduğu için res/raw/keep.xml release küçültmesinde silinmesini engeller.
const bildirimSimgesi = 'ic_bildirim';
const bildirimRengi = Renkler.arkaPlanAcik;

// Kurulacak tek bir bildirim. id günün tarihidir (yyyyMMdd): o günün bildirimi tarihten bulunup silinir.
typedef PlanliHatirlatma = ({int id, tz.TZDateTime zaman, String metin});

int hatirlatmaKimligi(DateTime gun) => gun.year * 10000 + gun.month * 100 + gun.day;

String hatirlatmaMetni(int? seri) => seri != null && seri > 0
    ? 'Bugünün bulmacaları seni bekliyor 🔥 $seri günlük serini kaçırma'
    : 'Bugünün bulmacaları seni bekliyor 🔥';

// Önümüzdeki günlerin bildirimleri. simdi Türkiye saatindedir.
// - Bugün bir oyun bitirildiyse ya da saat 20.00'yi geçtiyse bugünün bildirimi kurulmaz.
// - Seri sadece seriyi o akşam kurtarabilecek günün bildiriminde yazar: bugün oynanmadıysa bugün,
//   bugün oynandıysa yarın. Daha sonraki günlerde seri zaten bozulmuş olur, genel metin yazar.
List<PlanliHatirlatma> hatirlatmaPlani({required tz.TZDateTime simdi, required int seri, required bool bugunBitirdi}) {
  final plan = <PlanliHatirlatma>[];
  for (var gun = 0; gun < hatirlatmaGunSayisi; gun++) {
    final zaman = tz.TZDateTime(simdi.location, simdi.year, simdi.month, simdi.day + gun, hatirlatmaSaati);
    if (gun == 0 && (bugunBitirdi || !zaman.isAfter(simdi))) continue;
    final seriYazar = (gun == 0 && !bugunBitirdi) || (gun == 1 && bugunBitirdi);
    plan.add((id: hatirlatmaKimligi(zaman), zaman: zaman, metin: hatirlatmaMetni(seriYazar ? seri : null)));
  }
  return plan;
}

abstract class Hatirlatma {
  // Kullanıcının hatırlatma tercihi (profil sayfasındaki anahtar). Varsayılan: açık.
  Future<bool> acikMi();

  // Kapatılınca kurulu bildirimler silinir; açılınca bildirim izni istenir (plan ana menüde yeniden kurulur)
  Future<void> ayarla(bool acik);

  // Önümüzdeki günlerin bildirimlerini yeniden kurar. Hatırlatma kapalıysa hepsini siler.
  Future<void> planla({required int seri, required bool bugunBitirdi});

  // Bugün bir oyun bitti: bugünün bildirimi silinir
  Future<void> bugunuIptalEt();

  // Android 13+ bildirim izni (sistemin penceresi). İzin daha önce reddedildiyse sistem pencereyi tekrar göstermeyebilir.
  Future<void> izinIste();

  // İzin, ilk oyun bittikten sonra ana menüde uygulamanın kendi sayfasıyla bir kez sorulur: sorulduysa true
  Future<bool> izinSoruldu();

  // Sayfa gösterilmeden işaretlenir: izin zaten var ya da kullanıcı "Şimdi değil" dedi
  Future<void> izinSorulduIsaretle();

  // Telefon bu uygulamanın bildirimlerine izin veriyor mu (Android 12 ve öncesinde her zaman true)
  Future<bool> izinVar();
}

// Telefonun bildirimleriyle çalışır (flutter_local_notifications). Tercihler cihazda saklanır.
class YerelHatirlatma implements Hatirlatma {
  static const _acikAnahtari = 'hatirlatma_acik';
  static const _izinAnahtari = 'hatirlatma_izin_soruldu';

  final FlutterLocalNotificationsPlugin _eklenti;
  late final tz.Location _istanbul;

  YerelHatirlatma(this._eklenti);

  // Eklentiyi ve saat dilimlerini hazırlar. Bildirime dokunulunca (uygulama kapalıyken de) acildi çağrılır.
  Future<void> baslat({required VoidCallback acildi}) async {
    tz_veri.initializeTimeZones();
    _istanbul = tz.getLocation('Europe/Istanbul');
    await _eklenti.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings(bildirimSimgesi)),
      onDidReceiveNotificationResponse: (_) => acildi(),
    );
    final acilis = await _eklenti.getNotificationAppLaunchDetails();
    if (acilis?.didNotificationLaunchApp ?? false) acildi();
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _eklenti.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<bool> acikMi() async => (await SharedPreferences.getInstance()).getBool(_acikAnahtari) ?? true;

  @override
  Future<void> ayarla(bool acik) async {
    await (await SharedPreferences.getInstance()).setBool(_acikAnahtari, acik);
    if (acik) {
      await izinIste();
    } else {
      await _eklenti.cancelAll();
    }
  }

  @override
  Future<void> planla({required int seri, required bool bugunBitirdi}) async {
    await _eklenti.cancelAll();
    if (!await acikMi()) return;

    const ayrinti = NotificationDetails(
      android: AndroidNotificationDetails(
        _hatirlatmaKanali,
        'Günlük hatırlatma',
        channelDescription: 'O gün oyun oynamadıysan akşam 20.00\'de hatırlatır',
        icon: bildirimSimgesi,
        color: bildirimRengi,
      ),
    );
    final plan = hatirlatmaPlani(simdi: tz.TZDateTime.now(_istanbul), seri: seri, bugunBitirdi: bugunBitirdi);
    for (final h in plan) {
      await _eklenti.zonedSchedule(
        id: h.id,
        scheduledDate: h.zaman,
        notificationDetails: ayrinti,
        // Tam saatinde çalması gerekmiyor: tam zamanlı alarm izni istenmez, Android birkaç dakika kaydırabilir
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: 'FootyLore',
        body: h.metin,
      );
    }
  }

  @override
  Future<void> bugunuIptalEt() => _eklenti.cancel(id: hatirlatmaKimligi(tz.TZDateTime.now(_istanbul)));

  @override
  Future<void> izinIste() async {
    await (await SharedPreferences.getInstance()).setBool(_izinAnahtari, true);
    await _android?.requestNotificationsPermission();
  }

  @override
  Future<bool> izinSoruldu() async => (await SharedPreferences.getInstance()).getBool(_izinAnahtari) ?? false;

  @override
  Future<void> izinSorulduIsaretle() async => (await SharedPreferences.getInstance()).setBool(_izinAnahtari, true);

  @override
  Future<bool> izinVar() async => await _android?.areNotificationsEnabled() ?? true;
}

// Bildirim kurulamayan ortamlarda (testler) ya da eklenti açılamazsa: tercihi bellekte tutar, bildirim kurmaz
class BosHatirlatma implements Hatirlatma {
  bool _acik = true;
  bool _izinSoruldu = false;

  @override
  Future<bool> acikMi() async => _acik;

  @override
  Future<void> ayarla(bool acik) async => _acik = acik;

  @override
  Future<void> planla({required int seri, required bool bugunBitirdi}) async {}

  @override
  Future<void> bugunuIptalEt() async {}

  @override
  Future<void> izinIste() async => _izinSoruldu = true;

  @override
  Future<bool> izinSoruldu() async => _izinSoruldu;

  @override
  Future<void> izinSorulduIsaretle() async => _izinSoruldu = true;

  // Bildirim kurulamayan ortamda sorulacak bir şey yok: sayfa açılmaz
  @override
  Future<bool> izinVar() async => true;
}

// main.dart eklenti açılabildiyse YerelHatirlatma ile ezer
final hatirlatmaProvider = Provider<Hatirlatma>((ref) => BosHatirlatma());
