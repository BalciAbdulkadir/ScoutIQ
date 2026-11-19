"""
Oyuncuların doğum tarihlerini Transfermarkt API'den çekip Supabase'deki oyuncular.dogum_tarihi kolonuna yazar.
Oyuncu başına tek istek atılır: /players/{id}/profile ("dateOfBirth").

Kullanım:
    python dogum_tarihleri.py              # doğum tarihi henüz çekilmemiş bütün oyuncular
    python dogum_tarihleri.py --havuz      # sadece soru havuzundakiler (ünlü, bilinen, diğer)
    python dogum_tarihleri.py --bastan     # daha önce çekilmiş oyuncular da yeniden çekilir
    python dogum_tarihleri.py --is 8       # API'ye aynı anda atılan oyuncu sayısı (varsayılan 4)
    python dogum_tarihleri.py --dene 8198 418560   # verilen Transfermarkt ID'lerini çeker ve yazdırır, veritabanına yazmaz

Önce supabase/migrations/032_dogum_tarihleri.sql çalıştırılmış ve Transfermarkt API (Docker) açık olmalıdır.
Sadece veritabanında zaten olan oyuncular işlenir, yeni oyuncu eklenmez.
Yarıda kesilirse (Ctrl+C) tekrar çalıştırmak yeterli: çekilmiş oyuncular atlanır.
İstek hata alırsa oyuncu işaretlenmez, bir sonraki çalıştırmada tekrar denenir. Profilinde doğum tarihi olmayan oyuncu
işaretlenir (doğum tarihi boş kalır) ve tekrar denenmez.
"""
import re
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone

from main import api_istek_at, supabase

SAYFA_BOYUTU = 1000  # Supabase tek istekte en fazla 1000 satır döndürür
VARSAYILAN_IS_SAYISI = 4
HAVUZ_KADEMELERI = "(unlu,bilinen,diger)"


def oyunculari_oku(havuz, bastan):
    oyuncular = []
    bas = 0
    while True:
        sorgu = (
            supabase.table("oyuncular")
            .select("id, transfermarkt_id, isim")
            .order("id")
            .range(bas, bas + SAYFA_BOYUTU - 1)
        )
        if havuz:
            sorgu = sorgu.or_(f"kademe.in.{HAVUZ_KADEMELERI},kademe_override.in.{HAVUZ_KADEMELERI}")
        if not bastan:
            sorgu = sorgu.is_("dogum_tarihi_cekim_tarihi", "null")
        sayfa = sorgu.execute().data
        oyuncular.extend(sayfa)
        if len(sayfa) < SAYFA_BOYUTU:
            return oyuncular
        bas += SAYFA_BOYUTU


def profil_getir(oyuncu):
    """API isteği iş parçacığında atılır; veritabanına yazma ana akışta yapılır."""
    return oyuncu, api_istek_at(f"/players/{oyuncu['transfermarkt_id']}/profile")


def dogum_tarihi(profil):
    """'1985-02-05' biçimindeki tarih ya da yoksa / bozuksa None"""
    tarih = (profil or {}).get("dateOfBirth")
    return tarih if isinstance(tarih, str) and re.fullmatch(r"\d{4}-\d{2}-\d{2}", tarih) else None


def kaydet(oyuncu, profil):
    tarih = dogum_tarihi(profil)
    supabase.table("oyuncular").update({
        "dogum_tarihi": tarih,
        "dogum_tarihi_cekim_tarihi": datetime.now(timezone.utc).isoformat(),
    }).eq("id", oyuncu["id"]).execute()
    return tarih


def kullanim():
    print("Kullanım: python dogum_tarihleri.py [--havuz] [--bastan] [--is SAYI] | --dene TM_ID [TM_ID ...]")
    exit(1)


def is_sayisini_oku():
    if "--is" not in sys.argv:
        return VARSAYILAN_IS_SAYISI
    try:
        return max(1, int(sys.argv[sys.argv.index("--is") + 1]))
    except (IndexError, ValueError):
        kullanim()


def dene(tm_idler):
    """Veritabanına dokunmadan verilen oyuncuların doğum tarihlerini yazdırır."""
    if not tm_idler:
        kullanim()
    for tm_id in tm_idler:
        profil = api_istek_at(f"/players/{tm_id}/profile")
        if profil is None:
            print(f"!! {tm_id}: profil alınamadı.")
            continue
        print(f"{tm_id}: {profil.get('name')} - {dogum_tarihi(profil) or 'doğum tarihi yok'}")


if __name__ == "__main__":
    if "--dene" in sys.argv:
        dene(sys.argv[sys.argv.index("--dene") + 1:])
        exit(0)

    is_sayisi = is_sayisini_oku()
    oyuncular = oyunculari_oku("--havuz" in sys.argv, "--bastan" in sys.argv)
    toplam = len(oyuncular)
    print(f"Doğum tarihi çekimi başlatılıyor. İşlenecek oyuncu: {toplam}, aynı anda oyuncu: {is_sayisi}")

    hata_sayisi = 0
    tarihsiz = 0
    baslangic = time.time()
    havuz = ThreadPoolExecutor(max_workers=is_sayisi)

    try:
        isler = [havuz.submit(profil_getir, o) for o in oyuncular]
        for sira, is_ in enumerate(as_completed(isler), start=1):
            oyuncu, profil = is_.result()
            if profil is None:
                print(f"!! [{sira}/{toplam}] {oyuncu['isim']}: profil alınamadı.")
                hata_sayisi += 1
                continue

            try:
                tarih = kaydet(oyuncu, profil)
            except Exception as e:
                print(f"!! [{sira}/{toplam}] {oyuncu['isim']} kaydedilemedi: {e}")
                hata_sayisi += 1
                continue

            tarihsiz += tarih is None
            # Kalan süre tahmini: şu ana kadarki ortalama hıza göre
            gecen = time.time() - baslangic
            kalan_dk = gecen / sira * (toplam - sira) / 60
            print(f">> [{sira}/{toplam}] {oyuncu['isim']}: {tarih or 'doğum tarihi yok'} (kalan ~{kalan_dk:.0f} dk)")
    except KeyboardInterrupt:
        # Sıradaki istekler iptal edilir; o an süren birkaç istek bitince program kapanır
        havuz.shutdown(wait=False, cancel_futures=True)
        print("\nDurduruldu. Tekrar çalıştırınca kalan oyuncular çekilir.")
        exit(1)

    havuz.shutdown()
    print(f"\n{tarihsiz} oyuncunun profilinde doğum tarihi yoktu.")
    if hata_sayisi:
        print(f"İşlem tamamlandı ama {hata_sayisi} oyuncuda hata oluştu. Tekrar çalıştırınca sadece eksikler çekilir.")
    else:
        print("İşlem hatasız tamamlandı.")
