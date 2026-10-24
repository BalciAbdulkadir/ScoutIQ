"""
Oyuncuların transfer geçmişini (bonservis bedelleri) Transfermarkt API'den çekip Supabase'e yazar.
Bonservis oyunu için kullanılır.

Kullanım:
    python transferler.py          # sadece transferleri henüz çekilmemiş oyuncular
    python transferler.py --hepsi  # tüm oyuncular baştan

Önce supabase/migrations/004_transferler.sql çalıştırılmış olmalıdır.
Yarıda kesilirse (Ctrl+C) tekrar çalıştırmak yeterli: çekilmiş oyuncular atlanır, kayıtlar çoğalmaz.
Hata alan oyuncular işaretlenmez, bir sonraki çalıştırmada tekrar denenir.
"""
import sys
import time
from datetime import datetime, timezone

from main import api_istek_at, supabase

SAYFA_BOYUTU = 1000  # Supabase tek istekte en fazla 1000 satır döndürür


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
            sorgu = sorgu.is_("transfer_cekim_tarihi", "null")
        sayfa = sorgu.execute().data
        oyuncular.extend(sayfa)
        if len(sayfa) < SAYFA_BOYUTU:
            return oyuncular
        bas += SAYFA_BOYUTU


def kulup_bilgisi(kulup):
    if not kulup:
        return None, None
    return kulup.get("id"), kulup.get("name")


def transferleri_kaydet(oyuncu_id, transferler):
    """Oyuncunun transferlerini ekler ya da günceller. (transfer sayısı, bedelli transfer sayısı) döndürür."""
    satirlar = {}
    for transfer in transferler:
        # Henüz gerçekleşmemiş (ilan edilmiş) transferler alınmaz
        if not transfer.get("id") or transfer.get("upcoming"):
            continue
        eski_id, eski_isim = kulup_bilgisi(transfer.get("clubFrom"))
        yeni_id, yeni_isim = kulup_bilgisi(transfer.get("clubTo"))
        satirlar[transfer["id"]] = {
            "transfermarkt_id": transfer["id"],
            "oyuncu_id": oyuncu_id,
            "eski_kulup_tm_id": eski_id,
            "eski_kulup_isim": eski_isim,
            "yeni_kulup_tm_id": yeni_id,
            "yeni_kulup_isim": yeni_isim,
            "tarih": transfer.get("date"),
            "sezon": transfer.get("season"),
            "tip": transfer.get("transferType") or "bilinmiyor",
            "bedel": transfer.get("fee"),
            "piyasa_degeri": transfer.get("marketValue"),
        }

    if satirlar:
        supabase.table("transferler").upsert(
            list(satirlar.values()), on_conflict="transfermarkt_id"
        ).execute()

    bedelli = sum(1 for s in satirlar.values() if s["bedel"])
    return len(satirlar), bedelli


def cekildi_olarak_isaretle(oyuncu_id):
    supabase.table("oyuncular").update(
        {"transfer_cekim_tarihi": datetime.now(timezone.utc).isoformat()}
    ).eq("id", oyuncu_id).execute()


if __name__ == "__main__":
    hepsi = "--hepsi" in sys.argv
    oyuncular = oyunculari_oku(hepsi)
    toplam = len(oyuncular)
    print(f"Transfer çekimi başlatılıyor. İşlenecek oyuncu: {toplam}")

    hata_sayisi = 0
    baslangic = time.time()

    for sira, oyuncu in enumerate(oyuncular, start=1):
        data = api_istek_at(f"/players/{oyuncu['transfermarkt_id']}/transfers")
        if data is None or "transfers" not in data:
            print(f"!! [{sira}/{toplam}] {oyuncu['isim']}: transferler alınamadı.")
            hata_sayisi += 1
            continue

        try:
            adet, bedelli = transferleri_kaydet(oyuncu["id"], data["transfers"])
            cekildi_olarak_isaretle(oyuncu["id"])
        except Exception as e:
            print(f"!! [{sira}/{toplam}] {oyuncu['isim']} kaydedilemedi: {e}")
            hata_sayisi += 1
            continue

        # Kalan süre tahmini: şu ana kadarki ortalama hıza göre
        gecen = time.time() - baslangic
        kalan_dk = gecen / sira * (toplam - sira) / 60
        print(f">> [{sira}/{toplam}] {oyuncu['isim']}: {adet} transfer, {bedelli} bedelli (kalan ~{kalan_dk:.0f} dk)")

        time.sleep(0.3)  # Rate limit'e takılmamak için nefes aldırıyoruz

    if hata_sayisi:
        print(f"\nİşlem tamamlandı ama {hata_sayisi} oyuncuda hata oluştu. "
              "Tekrar çalıştırınca sadece eksikler çekilir.")
    else:
        print("\nİşlem hatasız tamamlandı.")
