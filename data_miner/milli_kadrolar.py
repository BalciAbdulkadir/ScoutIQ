"""
Bilinen milli takımların sezon sezon kadrolarını Transfermarkt API'den çeker, veritabanında olmayan oyuncuları ekler.
Amaç: 6 ana lig dışında (ör. Suudi Arabistan, Hollanda, Portekiz liginde) oynayan ama tanınmış bir milli takımda
forma giyen oyuncuların da veritabanında olması. Bu oyuncuların kulüp kariyeri (kariyer_gecmisi) eklenmez,
çünkü kulüpleri ana liglerin dışındadır; milli takım kariyerleri milli_takimlar.py ile çekilir.

Kullanım:
    python milli_kadrolar.py            # 2000/01'den bugüne tüm sezonlar
    python milli_kadrolar.py 2024 2025  # sadece verilen sezonlar

Sadece yeni oyuncu eklenir: veritabanında zaten olan oyuncuların kaydına dokunulmaz.
Tekrar çalıştırmak güvenlidir. Kadrosu alınamayan sezonlar (API 500) atlanır.
"""
import sys
import time
from datetime import date

from main import api_istek_at, foto_adresi, supabase

SAYFA_BOYUTU = 1000  # Supabase tek istekte en fazla 1000 satır döndürür
ILK_SEZON = 2000

# Kadroları çekilecek milli takımlar: Izgara'nın orta seviyesindeki 20 milli takım + Türkiye.
# Transfermarkt'taki milli takım ID'si -> isim
MILLI_TAKIMLAR = {
    "3381": "Türkiye",
    "3375": "İspanya", "3437": "Arjantin", "3377": "Fransa", "3299": "İngiltere", "3439": "Brezilya",
    "3575": "Fas", "3300": "Portekiz", "3382": "Belçika", "3379": "Hollanda", "6303": "Meksika",
    "3816": "Kolombiya", "3262": "Almanya", "3556": "Hırvatistan", "3384": "İsviçre", "3376": "İtalya",
    "3505": "ABD", "3435": "Japonya", "3499": "Senegal", "3440": "Norveç", "3449": "Uruguay",
}


def mevcut_oyuncular():
    """Veritabanındaki oyuncuların Transfermarkt ID'leri"""
    idler = set()
    bas = 0
    while True:
        sayfa = (
            supabase.table("oyuncular").select("transfermarkt_id")
            .order("transfermarkt_id").range(bas, bas + SAYFA_BOYUTU - 1).execute().data
        )
        idler.update(o["transfermarkt_id"] for o in sayfa)
        if len(sayfa) < SAYFA_BOYUTU:
            return idler
        bas += SAYFA_BOYUTU


def yeni_oyunculari_ekle(kadro, mevcutlar):
    """Kadrodaki, veritabanında olmayan oyuncuları ekler, eklenenlerin isimlerini döndürür."""
    satirlar = {}
    for oyuncu in kadro:
        tm_id = oyuncu.get("id")
        if not tm_id or not oyuncu.get("name") or tm_id in mevcutlar or tm_id in satirlar:
            continue
        uyruklar = oyuncu.get("nationality") or []
        satirlar[tm_id] = {
            "transfermarkt_id": tm_id,
            "isim": oyuncu["name"],
            "uyruk": uyruklar[0] if uyruklar else None,
            "foto_url": foto_adresi(oyuncu),
        }

    if satirlar:
        supabase.table("oyuncular").insert(list(satirlar.values())).execute()
        mevcutlar.update(satirlar)
    return [s["isim"] for s in satirlar.values()]


def sezonlari_oku():
    if len(sys.argv) == 1:
        # Bugün sonbahardaysak yeni sezon başlamıştır (2026 Kasım -> 2026/27)
        bugun = date.today()
        return list(range(ILK_SEZON, bugun.year + (1 if bugun.month >= 7 else 0)))
    try:
        return sorted({int(arg) for arg in sys.argv[1:]})
    except ValueError:
        print("Kullanım: python milli_kadrolar.py [sezon ...]   örn: python milli_kadrolar.py 2024 2025")
        exit(1)


if __name__ == "__main__":
    sezonlar = sezonlari_oku()
    mevcutlar = mevcut_oyuncular()
    print(f"Milli kadro çekimi başlatılıyor. Milli takım: {len(MILLI_TAKIMLAR)}, sezonlar: {sezonlar[0]}-{sezonlar[-1]}, "
          f"veritabanındaki oyuncu: {len(mevcutlar)}")

    toplam_eklenen = 0
    hata_sayisi = 0
    for tm_id, isim in MILLI_TAKIMLAR.items():
        print(f"\n=== {isim} ===")
        for sezon in sezonlar:
            kadro = api_istek_at(f"/clubs/{tm_id}/players?season_id={sezon}")
            if not kadro or "players" not in kadro:
                print(f"!! {isim} {sezon} kadrosu alınamadı.")
                hata_sayisi += 1
                continue

            try:
                eklenenler = yeni_oyunculari_ekle(kadro["players"], mevcutlar)
            except Exception as e:
                print(f"!! {isim} {sezon} kaydedilemedi: {e}")
                hata_sayisi += 1
                continue

            toplam_eklenen += len(eklenenler)
            ozet = f": {', '.join(eklenenler)}" if eklenenler else ""
            print(f">> {isim} {sezon}: {len(kadro['players'])} kişilik kadro, {len(eklenenler)} yeni oyuncu{ozet}")
            time.sleep(0.3)  # Rate limit'e takılmamak için nefes aldırıyoruz

    print(f"\nToplam {toplam_eklenen} yeni oyuncu eklendi.")
    if hata_sayisi:
        print(f"{hata_sayisi} kadro alınamadı. '!!' ile başlayan satırlara bakın; tekrar çalıştırmak güvenlidir.")
