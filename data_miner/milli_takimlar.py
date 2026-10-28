"""
Oyuncuların A milli takım kariyerini (maç ve gol sayıları) Transfermarkt API'den çekip Supabase'e yazar.

Kullanım:
    python milli_takimlar.py          # sadece milli takım kariyeri henüz çekilmemiş oyuncular
    python milli_takimlar.py --hepsi  # tüm oyuncular baştan (maç ve gol sayıları güncellenir)
    python milli_takimlar.py --is 8   # API'ye aynı anda atılan istek sayısı (varsayılan 4)

Önce supabase/migrations/009_milli_takim_kariyeri.sql çalıştırılmış olmalıdır.
Sadece veritabanında zaten olan oyuncular işlenir, yeni oyuncu eklenmez.
Alt yaş (U17, U21 ...) ve olimpiyat takımları ile hiç forma giyilmemiş milli takımlar (sadece kadroya çağrılma) alınmaz.
Yarıda kesilirse (Ctrl+C) tekrar çalıştırmak yeterli: çekilmiş oyuncular atlanır, kayıtlar çoğalmaz.
Hata alan oyuncular işaretlenmez, bir sonraki çalıştırmada tekrar denenir.
"""
import re
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone

from main import api_istek_at, supabase

SAYFA_BOYUTU = 1000  # Supabase tek istekte en fazla 1000 satır döndürür
VARSAYILAN_IS_SAYISI = 4

# Transfermarkt'ta alt takımların adı A takımın adına ek alır: "France U19", "Brazil Olympic Team", "Italy B"
ALT_TAKIM = re.compile(r"\bU\d{2}\b|Olympic|\bB$|Amateur|Futsal|Beach", re.IGNORECASE)


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
            sorgu = sorgu.is_("milli_takim_cekim_tarihi", "null")
        sayfa = sorgu.execute().data
        oyuncular.extend(sayfa)
        if len(sayfa) < SAYFA_BOYUTU:
            return oyuncular
        bas += SAYFA_BOYUTU


def milli_kariyeri_getir(oyuncu):
    """API isteği iş parçacıklarında atılır; veritabanına yazma ana akışta yapılır."""
    data = api_istek_at(f"/players/{oyuncu['transfermarkt_id']}/national_career")
    time.sleep(0.3)  # Rate limit'e takılmamak için nefes aldırıyoruz
    return oyuncu, data


def a_takimlari(milli_takimlar):
    """Oyuncunun forma giydiği A milli takımlar"""
    return [
        t for t in milli_takimlar
        if t.get("id") and t.get("name") and t.get("appearances") and not ALT_TAKIM.search(t["name"])
    ]


def milli_kariyeri_kaydet(oyuncu_id, takimlar):
    satirlar = [
        {
            "oyuncu_id": oyuncu_id,
            "milli_takim_tm_id": t["id"],
            "milli_takim_isim": t["name"],
            "mac_sayisi": t["appearances"],
            "gol": t.get("goals") or 0,
        }
        for t in takimlar
    ]
    if satirlar:
        supabase.table("milli_takim_kariyeri").upsert(
            satirlar, on_conflict="oyuncu_id,milli_takim_tm_id"
        ).execute()


def cekildi_olarak_isaretle(oyuncu_id):
    supabase.table("oyuncular").update(
        {"milli_takim_cekim_tarihi": datetime.now(timezone.utc).isoformat()}
    ).eq("id", oyuncu_id).execute()


def is_sayisini_oku():
    if "--is" not in sys.argv:
        return VARSAYILAN_IS_SAYISI
    try:
        return max(1, int(sys.argv[sys.argv.index("--is") + 1]))
    except (IndexError, ValueError):
        print("Kullanım: python milli_takimlar.py [--hepsi] [--is SAYI]   örn: python milli_takimlar.py --is 8")
        exit(1)


if __name__ == "__main__":
    hepsi = "--hepsi" in sys.argv
    is_sayisi = is_sayisini_oku()
    oyuncular = oyunculari_oku(hepsi)
    toplam = len(oyuncular)
    print(f"Milli takım çekimi başlatılıyor. İşlenecek oyuncu: {toplam}, aynı anda istek: {is_sayisi}")

    hata_sayisi = 0
    milli_oyuncu_sayisi = 0
    baslangic = time.time()
    havuz = ThreadPoolExecutor(max_workers=is_sayisi)

    try:
        isler = [havuz.submit(milli_kariyeri_getir, o) for o in oyuncular]
        for sira, is_ in enumerate(as_completed(isler), start=1):
            oyuncu, data = is_.result()
            if data is None or "nationalTeams" not in data:
                print(f"!! [{sira}/{toplam}] {oyuncu['isim']}: milli takım kariyeri alınamadı.")
                hata_sayisi += 1
                continue

            takimlar = a_takimlari(data["nationalTeams"])
            try:
                milli_kariyeri_kaydet(oyuncu["id"], takimlar)
                cekildi_olarak_isaretle(oyuncu["id"])
            except Exception as e:
                print(f"!! [{sira}/{toplam}] {oyuncu['isim']} kaydedilemedi: {e}")
                hata_sayisi += 1
                continue

            if takimlar:
                milli_oyuncu_sayisi += 1
            ozet = ", ".join(f"{t['name']} ({t['appearances']} maç, {t.get('goals') or 0} gol)" for t in takimlar)

            # Kalan süre tahmini: şu ana kadarki ortalama hıza göre
            gecen = time.time() - baslangic
            kalan_dk = gecen / sira * (toplam - sira) / 60
            print(f">> [{sira}/{toplam}] {oyuncu['isim']}: {ozet or 'A milli maçı yok'} (kalan ~{kalan_dk:.0f} dk)")
    except KeyboardInterrupt:
        # Sıradaki istekler iptal edilir; o an süren birkaç istek bitince program kapanır
        havuz.shutdown(wait=False, cancel_futures=True)
        print("\nDurduruldu. Tekrar çalıştırınca kalan oyuncular çekilir.")
        exit(1)

    havuz.shutdown()
    print(f"\n{milli_oyuncu_sayisi} oyuncunun A milli takım kariyeri yazıldı.")
    if hata_sayisi:
        print(f"İşlem tamamlandı ama {hata_sayisi} oyuncuda hata oluştu. "
              "Tekrar çalıştırınca sadece eksikler çekilir.")
    else:
        print("İşlem hatasız tamamlandı.")
