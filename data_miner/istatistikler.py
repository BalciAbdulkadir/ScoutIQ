"""
Oyuncuların 6 ligdeki (Süper Lig + 5 büyük lig) toplam lig maçını Transfermarkt API'den çekip oyuncular.ust_lig_mac'a yazar.
Oyuncu havuzuna girme şartlarından biridir (kademeler.py). Oyuncu başına tek istek atılır: /stats.
Kupa ve Avrupa maçları sayılmaz; kulüp başına tüm resmi maçlar onem_verileri.py ile ayrıca tutulur.

Kullanım:
    python istatistikler.py          # sadece istatistiği henüz çekilmemiş oyuncular
    python istatistikler.py --hepsi  # tüm oyuncular baştan
    python istatistikler.py --is 8   # API'ye aynı anda atılan istek sayısı (varsayılan 4)

Önce supabase/migrations/017_oyuncu_havuzu.sql çalıştırılmış olmalıdır.
Yarıda kesilirse (Ctrl+C) tekrar çalıştırmak yeterli: çekilmiş oyuncular atlanır.
Hata alan oyuncular işaretlenmez, bir sonraki çalıştırmada tekrar denenir.
"""
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone

from main import LIGLER, api_istek_at, supabase

SAYFA_BOYUTU = 1000  # Supabase tek istekte en fazla 1000 satır döndürür
VARSAYILAN_IS_SAYISI = 4


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
            sorgu = sorgu.is_("istatistik_cekim_tarihi", "null")
        sayfa = sorgu.execute().data
        oyuncular.extend(sayfa)
        if len(sayfa) < SAYFA_BOYUTU:
            return oyuncular
        bas += SAYFA_BOYUTU


def istatistik_getir(oyuncu):
    """API isteği iş parçacıklarında atılır; veritabanına yazma ana akışta yapılır."""
    data = api_istek_at(f"/players/{oyuncu['transfermarkt_id']}/stats")
    time.sleep(0.3)  # Rate limit'e takılmamak için nefes aldırıyoruz
    return oyuncu, data


def ust_lig_maci(istatistikler):
    return sum(s.get("appearances") or 0 for s in istatistikler if s.get("competitionId") in LIGLER)


def kaydet(oyuncu_id, ust_lig_mac):
    supabase.table("oyuncular").update({
        "ust_lig_mac": ust_lig_mac,
        "istatistik_cekim_tarihi": datetime.now(timezone.utc).isoformat(),
    }).eq("id", oyuncu_id).execute()


def is_sayisini_oku():
    if "--is" not in sys.argv:
        return VARSAYILAN_IS_SAYISI
    try:
        return max(1, int(sys.argv[sys.argv.index("--is") + 1]))
    except (IndexError, ValueError):
        print("Kullanım: python istatistikler.py [--hepsi] [--is SAYI]   örn: python istatistikler.py --is 8")
        exit(1)


if __name__ == "__main__":
    hepsi = "--hepsi" in sys.argv
    is_sayisi = is_sayisini_oku()
    oyuncular = oyunculari_oku(hepsi)
    toplam = len(oyuncular)
    print(f"İstatistik çekimi başlatılıyor. İşlenecek oyuncu: {toplam}, aynı anda istek: {is_sayisi}")

    hata_sayisi = 0
    baslangic = time.time()
    havuz = ThreadPoolExecutor(max_workers=is_sayisi)

    try:
        isler = [havuz.submit(istatistik_getir, o) for o in oyuncular]
        for sira, is_ in enumerate(as_completed(isler), start=1):
            oyuncu, data = is_.result()
            if data is None or "stats" not in data:
                print(f"!! [{sira}/{toplam}] {oyuncu['isim']}: istatistik alınamadı.")
                hata_sayisi += 1
                continue

            try:
                mac = ust_lig_maci(data["stats"])
                kaydet(oyuncu["id"], mac)
            except Exception as e:
                print(f"!! [{sira}/{toplam}] {oyuncu['isim']} kaydedilemedi: {e}")
                hata_sayisi += 1
                continue

            # Kalan süre tahmini: şu ana kadarki ortalama hıza göre
            gecen = time.time() - baslangic
            kalan_dk = gecen / sira * (toplam - sira) / 60
            print(f">> [{sira}/{toplam}] {oyuncu['isim']}: {mac} üst lig maçı (kalan ~{kalan_dk:.0f} dk)")
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
