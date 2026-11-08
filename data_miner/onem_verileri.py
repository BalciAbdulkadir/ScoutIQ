"""
Önem kriterleri (genel tanınmışlık ve kulüp önemi) için oyuncuların istatistik, piyasa değeri ve başarılarını
Transfermarkt API'den çekip Supabase'e yazar. Oyuncu başına üç istek atılır: /stats, /market_value, /achievements.

Kullanım:
    python onem_verileri.py          # sadece verisi henüz çekilmemiş oyuncular
    python onem_verileri.py --hepsi  # tüm oyuncular baştan (değerler güncellenir)
    python onem_verileri.py --is 8   # API'ye aynı anda atılan oyuncu sayısı (varsayılan 4)

Önce supabase/migrations/015_onem_verileri.sql çalıştırılmış olmalıdır.
Sadece veritabanında zaten olan oyuncular işlenir, yeni oyuncu eklenmez.
Yazılanlar:
  - oyuncular.zirve_piyasa_degeri / guncel_piyasa_degeri
  - oyuncu_kulup_istatistikleri: kulüp başına toplam maç, gol, asist, dakika, sezon ve o kulüpteki zirve piyasa değeri
  - oyuncu_basarilari: kazanılan başlıklar (sadece KALAN_BASLIKLAR), kulüp başına adet
Yarıda kesilirse (Ctrl+C) tekrar çalıştırmak yeterli: çekilmiş oyuncular atlanır, kayıtlar çoğalmaz.
Üç istekten biri bile hata alırsa oyuncu işaretlenmez, bir sonraki çalıştırmada tekrar denenir.
"""
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone

from main import api_istek_at, supabase

SAYFA_BOYUTU = 1000  # Supabase tek istekte en fazla 1000 satır döndürür
VARSAYILAN_IS_SAYISI = 4

# oyuncu_basarilari'na sadece bu başlıklar yazılır: Avrupa kupaları, 6 ligin şampiyonluk/kupa/süper kupaları,
# büyük milli turnuvalar ve bireysel ödüller. Aynı liste supabase/migrations/016_basari_temizligi.sql'dedir.
KALAN_BASLIKLAR = {
    "UEFA Champions League winner", "European Champion Clubs' Cup winner",
    "Europa League winner", "Uefa Cup winner",
    "Uefa Supercup winner",
    "Turkish champion", "English Champion", "Spanish champion", "Italian champion", "German Champion", "French champion",
    "Turkish cup winner", "English FA Cup winner", "Spanish cup winner", "Italian cup winner", "German cup winner",
    "French cup winner",
    "Turkish Super Cup winner", "English Super Cup winner", "Spanish Super Cup winner", "Italian Super Cup winner",
    "German Super Cup winner", "French Super Cup winner",
    "World Cup winner", "European champion", "Copa América winner", "Winner UEFA Nations League",
    "Winner Ballon d'Or", "The Best FIFA Men's Player", "UEFA Best Player in Europe", "Golden Boot winner (Europe)",
}


def oyunculari_oku(hepsi):
    oyuncular = []
    bas = 0
    while True:
        sorgu = (
            supabase.table("oyuncular")
            .select("id, transfermarkt_id, isim")
            .order("id")
            .range(bas, bas + SAYFA_BOYUTU - 1)
        )
        if not hepsi:
            sorgu = sorgu.is_("onem_verisi_cekim_tarihi", "null")
        sayfa = sorgu.execute().data
        oyuncular.extend(sayfa)
        if len(sayfa) < SAYFA_BOYUTU:
            return oyuncular
        bas += SAYFA_BOYUTU


def onem_verisini_getir(oyuncu):
    """API istekleri iş parçacıklarında atılır; veritabanına yazma ana akışta yapılır."""
    tm_id = oyuncu["transfermarkt_id"]
    istatistik = api_istek_at(f"/players/{tm_id}/stats")
    piyasa = api_istek_at(f"/players/{tm_id}/market_value")
    basari = api_istek_at(f"/players/{tm_id}/achievements")
    time.sleep(0.3)  # Rate limit'e takılmamak için nefes aldırıyoruz
    return oyuncu, istatistik, piyasa, basari


def kulup_ozetleri(oyuncu_id, istatistikler, piyasa_gecmisi):
    """Sezon ve turnuva satırlarını kulüp başına toplar; o kulüpteyken ulaşılan zirve piyasa değerini ekler."""
    kulupler = {}

    def kulup(kulup_tm_id):
        return kulupler.setdefault(kulup_tm_id, {
            "oyuncu_id": oyuncu_id, "kulup_tm_id": kulup_tm_id, "mac": 0, "gol": 0, "asist": 0, "dakika": 0,
            "sezonlar": set(), "zirve_piyasa_degeri": None,
        })

    for s in istatistikler:
        if not s.get("clubId"):
            continue
        k = kulup(s["clubId"])
        k["mac"] += s.get("appearances") or 0
        k["gol"] += s.get("goals") or 0
        k["asist"] += s.get("assists") or 0
        k["dakika"] += s.get("minutesPlayed") or 0
        if (s.get("appearances") or 0) > 0 and str(s.get("seasonId", "")).isdigit():
            k["sezonlar"].add(int(s["seasonId"]))

    for p in piyasa_gecmisi:
        if not p.get("clubId") or not p.get("marketValue"):
            continue
        k = kulup(p["clubId"])
        k["zirve_piyasa_degeri"] = max(k["zirve_piyasa_degeri"] or 0, p["marketValue"])

    satirlar = []
    for k in kulupler.values():
        sezonlar = k.pop("sezonlar")
        satirlar.append(k | {
            "sezon_sayisi": len(sezonlar),
            "ilk_sezon": min(sezonlar) if sezonlar else None,
            "son_sezon": max(sezonlar) if sezonlar else None,
        })
    return satirlar


def basari_satirlari(oyuncu_id, basarilar):
    """Başlık ve kulüp başına adet. Ayrıntısı olmayan başlıklar kulüpsüz tek satırdır."""
    adetler = {}
    for b in basarilar:
        if b.get("title") not in KALAN_BASLIKLAR:
            continue
        detaylar = b.get("details") or []
        if not detaylar:
            adetler[(b["title"], "")] = adetler.get((b["title"], ""), 0) + (b.get("count") or 1)
            continue
        for d in detaylar:
            anahtar = (b["title"], (d.get("club") or {}).get("id") or "")
            adetler[anahtar] = adetler.get(anahtar, 0) + 1
    return [
        {"oyuncu_id": oyuncu_id, "baslik": baslik, "kulup_tm_id": kulup_tm_id, "adet": adet}
        for (baslik, kulup_tm_id), adet in adetler.items()
    ]


def kaydet(oyuncu, istatistik, piyasa, basari):
    """Oyuncunun özetlerini yazar ve işaretler. (kulüp sayısı, başlık sayısı, zirve piyasa değeri) döndürür."""
    gecmis = piyasa.get("marketValueHistory") or []
    zirve = max((p["marketValue"] for p in gecmis if p.get("marketValue")), default=None)

    kulup_satirlari = kulup_ozetleri(oyuncu["id"], istatistik.get("stats") or [], gecmis)
    if kulup_satirlari:
        supabase.table("oyuncu_kulup_istatistikleri").upsert(
            kulup_satirlari, on_conflict="oyuncu_id,kulup_tm_id"
        ).execute()

    basari_satir = basari_satirlari(oyuncu["id"], basari.get("achievements") or [])
    if basari_satir:
        supabase.table("oyuncu_basarilari").upsert(
            basari_satir, on_conflict="oyuncu_id,baslik,kulup_tm_id"
        ).execute()

    supabase.table("oyuncular").update({
        "zirve_piyasa_degeri": zirve,
        "guncel_piyasa_degeri": piyasa.get("marketValue"),
        "onem_verisi_cekim_tarihi": datetime.now(timezone.utc).isoformat(),
    }).eq("id", oyuncu["id"]).execute()

    return len(kulup_satirlari), len(basari_satir), zirve


def is_sayisini_oku():
    if "--is" not in sys.argv:
        return VARSAYILAN_IS_SAYISI
    try:
        return max(1, int(sys.argv[sys.argv.index("--is") + 1]))
    except (IndexError, ValueError):
        print("Kullanım: python onem_verileri.py [--hepsi] [--is SAYI]   örn: python onem_verileri.py --is 8")
        exit(1)


if __name__ == "__main__":
    hepsi = "--hepsi" in sys.argv
    is_sayisi = is_sayisini_oku()
    oyuncular = oyunculari_oku(hepsi)
    toplam = len(oyuncular)
    print(f"Önem verisi çekimi başlatılıyor. İşlenecek oyuncu: {toplam}, aynı anda oyuncu: {is_sayisi}")

    hata_sayisi = 0
    baslangic = time.time()
    havuz = ThreadPoolExecutor(max_workers=is_sayisi)

    try:
        isler = [havuz.submit(onem_verisini_getir, o) for o in oyuncular]
        for sira, is_ in enumerate(as_completed(isler), start=1):
            oyuncu, istatistik, piyasa, basari = is_.result()
            if istatistik is None or piyasa is None or basari is None:
                eksik = [ad for ad, veri in (("istatistik", istatistik), ("piyasa değeri", piyasa), ("başarılar", basari)) if veri is None]
                print(f"!! [{sira}/{toplam}] {oyuncu['isim']}: {', '.join(eksik)} alınamadı.")
                hata_sayisi += 1
                continue

            try:
                kulup_sayisi, baslik_sayisi, zirve = kaydet(oyuncu, istatistik, piyasa, basari)
            except Exception as e:
                print(f"!! [{sira}/{toplam}] {oyuncu['isim']} kaydedilemedi: {e}")
                hata_sayisi += 1
                continue

            # Kalan süre tahmini: şu ana kadarki ortalama hıza göre
            gecen = time.time() - baslangic
            kalan_dk = gecen / sira * (toplam - sira) / 60
            zirve_metni = f"{zirve / 1_000_000:.1f} M€" if zirve else "-"
            print(f">> [{sira}/{toplam}] {oyuncu['isim']}: {kulup_sayisi} kulüp, {baslik_sayisi} başlık, zirve {zirve_metni} (kalan ~{kalan_dk:.0f} dk)")
    except KeyboardInterrupt:
        # Sıradaki istekler iptal edilir; o an süren birkaç istek bitince program kapanır
        havuz.shutdown(wait=False, cancel_futures=True)
        print("\nDurduruldu. Tekrar çalıştırınca kalan oyuncular çekilir.")
        exit(1)

    havuz.shutdown()
    if hata_sayisi:
        print(f"\nİşlem tamamlandı ama {hata_sayisi} oyuncuda hata oluştu. Tekrar çalıştırınca sadece eksikler çekilir.")
    else:
        print("\nİşlem hatasız tamamlandı.")
