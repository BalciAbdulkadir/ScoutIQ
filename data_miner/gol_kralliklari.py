"""
Oyuncuların gol krallıklarını Transfermarkt API'den çekip Supabase'deki gol_kralliklari tablosuna yazar.
Oyuncu başına tek istek atılır: /achievements. Oradaki "Top goal scorer" başlığının her ayrıntısı bir gol krallığıdır
(sezon, müsabaka, kulüp ya da milli takım). Gol sayısı kaynakta yoktur.

Kullanım:
    python gol_kralliklari.py                  # soru havuzundaki (ünlü, bilinen, diğer) çekilmemiş oyuncular
    python gol_kralliklari.py --tum-oyuncular  # havuz dışındakiler dahil bütün oyuncular
    python gol_kralliklari.py --bastan         # daha önce çekilmiş oyuncular da yeniden çekilir
    python gol_kralliklari.py --is 8           # API'ye aynı anda atılan oyuncu sayısı (varsayılan 4)
    python gol_kralliklari.py --dene 418560 8198   # verilen Transfermarkt ID'lerini çeker ve yazdırır, veritabanına yazmaz

Önce supabase/migrations/025_gol_kralliklari.sql çalıştırılmış ve Transfermarkt API (Docker) açık olmalıdır.
Sadece veritabanında zaten olan oyuncular işlenir, yeni oyuncu eklenmez.
Yarıda kesilirse (Ctrl+C) tekrar çalıştırmak yeterli: çekilmiş oyuncular atlanır, kayıtlar çoğalmaz.
İstek hata alırsa oyuncu işaretlenmez, bir sonraki çalıştırmada tekrar denenir.
"""
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone

from main import api_istek_at, supabase

SAYFA_BOYUTU = 1000  # Supabase tek istekte en fazla 1000 satır döndürür
VARSAYILAN_IS_SAYISI = 4
BASLIK = "Top goal scorer"
HAVUZ_KADEMELERI = "(unlu,bilinen,diger)"


def oyunculari_oku(tum_oyuncular, bastan):
    oyuncular = []
    bas = 0
    while True:
        sorgu = (
            supabase.table("oyuncular")
            .select("id, transfermarkt_id, isim")
            .order("id")
            .range(bas, bas + SAYFA_BOYUTU - 1)
        )
        if not tum_oyuncular:
            sorgu = sorgu.or_(f"kademe.in.{HAVUZ_KADEMELERI},kademe_override.in.{HAVUZ_KADEMELERI}")
        if not bastan:
            sorgu = sorgu.is_("gol_kralligi_cekim_tarihi", "null")
        sayfa = sorgu.execute().data
        oyuncular.extend(sayfa)
        if len(sayfa) < SAYFA_BOYUTU:
            return oyuncular
        bas += SAYFA_BOYUTU


def basarilari_getir(oyuncu):
    """API isteği iş parçacığında atılır; veritabanına yazma ana akışta yapılır."""
    return oyuncu, api_istek_at(f"/players/{oyuncu['transfermarkt_id']}/achievements")


def krallik_satirlari(oyuncu_id, basarilar):
    """Gol krallığı başlığının ayrıntılarından satırlar. Sezonu ya da müsabakası olmayan ayrıntı atlanır."""
    satirlar = {}
    for b in basarilar:
        if b.get("title") != BASLIK:
            continue
        for d in b.get("details") or []:
            sezon = (d.get("season") or {}).get("id")
            musabaka = d.get("competition") or {}
            kulup = d.get("club") or {}
            if not sezon or not str(sezon).isdigit() or not musabaka.get("id"):
                continue
            anahtar = (int(sezon), musabaka["id"], kulup.get("id") or "")
            satirlar[anahtar] = {
                "oyuncu_id": oyuncu_id,
                "sezon": int(sezon),
                "musabaka_tm_id": musabaka["id"],
                "musabaka_isim": musabaka.get("name"),
                "kulup_tm_id": kulup.get("id") or "",
                "kulup_isim": kulup.get("name"),
            }
    return list(satirlar.values())


def kaydet(oyuncu, basari):
    """Oyuncunun gol krallıklarını baştan yazar ve oyuncuyu işaretler. Satır sayısını döndürür."""
    satirlar = krallik_satirlari(oyuncu["id"], basari.get("achievements") or [])
    supabase.table("gol_kralliklari").delete().eq("oyuncu_id", oyuncu["id"]).execute()
    if satirlar:
        supabase.table("gol_kralliklari").insert(satirlar).execute()
    supabase.table("oyuncular").update({
        "gol_kralligi_cekim_tarihi": datetime.now(timezone.utc).isoformat(),
    }).eq("id", oyuncu["id"]).execute()
    return len(satirlar)


def kullanim():
    print("Kullanım: python gol_kralliklari.py [--tum-oyuncular] [--bastan] [--is SAYI] | --dene TM_ID [TM_ID ...]")
    exit(1)


def is_sayisini_oku():
    if "--is" not in sys.argv:
        return VARSAYILAN_IS_SAYISI
    try:
        return max(1, int(sys.argv[sys.argv.index("--is") + 1]))
    except (IndexError, ValueError):
        kullanim()


def dene(tm_idler):
    """Veritabanına dokunmadan verilen oyuncuların gol krallıklarını yazdırır."""
    if not tm_idler:
        kullanim()
    for tm_id in tm_idler:
        basari = api_istek_at(f"/players/{tm_id}/achievements")
        if basari is None:
            print(f"!! {tm_id}: başarılar alınamadı.")
            continue
        satirlar = krallik_satirlari(None, basari.get("achievements") or [])
        print(f"\n{tm_id}: {len(satirlar)} gol krallığı")
        for s in sorted(satirlar, key=lambda s: (-s["sezon"], s["musabaka_tm_id"])):
            print(f"   {s['sezon']}  {s['musabaka_tm_id']:<6} {s['musabaka_isim'] or '-':<32} {s['kulup_isim'] or '-'}")


if __name__ == "__main__":
    if "--dene" in sys.argv:
        dene(sys.argv[sys.argv.index("--dene") + 1:])
        exit(0)

    is_sayisi = is_sayisini_oku()
    oyuncular = oyunculari_oku("--tum-oyuncular" in sys.argv, "--bastan" in sys.argv)
    toplam = len(oyuncular)
    print(f"Gol krallığı çekimi başlatılıyor. İşlenecek oyuncu: {toplam}, aynı anda oyuncu: {is_sayisi}")

    hata_sayisi = 0
    krallik_toplami = 0
    baslangic = time.time()
    havuz = ThreadPoolExecutor(max_workers=is_sayisi)

    try:
        isler = [havuz.submit(basarilari_getir, o) for o in oyuncular]
        for sira, is_ in enumerate(as_completed(isler), start=1):
            oyuncu, basari = is_.result()
            if basari is None:
                print(f"!! [{sira}/{toplam}] {oyuncu['isim']}: başarılar alınamadı.")
                hata_sayisi += 1
                continue

            try:
                adet = kaydet(oyuncu, basari)
            except Exception as e:
                print(f"!! [{sira}/{toplam}] {oyuncu['isim']} kaydedilemedi: {e}")
                hata_sayisi += 1
                continue

            krallik_toplami += adet
            # Kalan süre tahmini: şu ana kadarki ortalama hıza göre
            gecen = time.time() - baslangic
            kalan_dk = gecen / sira * (toplam - sira) / 60
            print(f">> [{sira}/{toplam}] {oyuncu['isim']}: {adet} gol krallığı (kalan ~{kalan_dk:.0f} dk)")
    except KeyboardInterrupt:
        # Sıradaki istekler iptal edilir; o an süren birkaç istek bitince program kapanır
        havuz.shutdown(wait=False, cancel_futures=True)
        print("\nDurduruldu. Tekrar çalıştırınca kalan oyuncular çekilir.")
        exit(1)

    havuz.shutdown()
    print(f"\nToplam {krallik_toplami} gol krallığı yazıldı.")
    if hata_sayisi:
        print(f"İşlem tamamlandı ama {hata_sayisi} oyuncuda hata oluştu. Tekrar çalıştırınca sadece eksikler çekilir.")
    else:
        print("İşlem hatasız tamamlandı.")
