"""
Veritabanındaki oyuncuların fotoğraf adreslerini (foto_url) Transfermarkt API'den çekip Supabase'e yazar.
Fotoğraflar kadro listesinde geldiği için oyuncu başına değil, kulüp-sezon başına bir istek atılır.

Kullanım:
    python fotograflar.py            # kariyer_gecmisi'ndeki tüm sezonlar
    python fotograflar.py 2024 2025  # sadece verilen sezonlar
    python fotograflar.py --profil   # kadrolardan sonra fotoğrafsız kalanlar, oyuncu profilinden tek tek

Önce supabase/migrations/007_oyuncu_fotograflari.sql çalıştırılmış olmalıdır.
Sadece veritabanında zaten olan ve fotoğrafı boş olan oyuncular güncellenir: yeni oyuncu eklenmez,
fotoğraf dışındaki alanlar değişmez. Yarıda kesilirse tekrar çalıştırmak yeterli, fotoğrafı yazılmış oyuncular atlanır.
"""
import sys
import time

from main import LIGLER, api_istek_at, foto_adresi, supabase

SAYFA_BOYUTU = 1000  # Supabase tek istekte en fazla 1000 satır döndürür


def fotografsiz_oyunculari_oku():
    """Fotoğrafı henüz yazılmamış oyuncular: transfermarkt_id -> isim"""
    oyuncular = {}
    bas = 0
    while True:
        sayfa = (
            supabase.table("oyuncular")
            .select("transfermarkt_id, isim")
            .is_("foto_url", "null")
            .order("transfermarkt_id")
            .range(bas, bas + SAYFA_BOYUTU - 1)
            .execute()
            .data
        )
        oyuncular.update({o["transfermarkt_id"]: o["isim"] for o in sayfa})
        if len(sayfa) < SAYFA_BOYUTU:
            return oyuncular
        bas += SAYFA_BOYUTU


def sezon_araligi():
    """kariyer_gecmisi'ndeki ilk ve son sezon"""
    ilk = (
        supabase.table("kariyer_gecmisi").select("baslangic_yili")
        .order("baslangic_yili").limit(1).execute().data
    )
    son = (
        supabase.table("kariyer_gecmisi").select("bitis_yili")
        .order("bitis_yili", desc=True).limit(1).execute().data
    )
    if not ilk or not son:
        print("Hata: kariyer_gecmisi boş.")
        exit(1)
    return list(range(ilk[0]["baslangic_yili"], son[0]["bitis_yili"] + 1))


def fotograflari_kaydet(kadro, bekleyenler):
    """Kadrodaki fotoğrafsız oyuncuların fotoğraflarını yazar, yazılan oyuncu sayısını döndürür."""
    satirlar = {}
    for oyuncu in kadro:
        tm_id = oyuncu.get("id")
        adres = foto_adresi(oyuncu)
        if tm_id in bekleyenler and adres:
            # isim zorunlu kolon olduğu için upsert'e veritabanındaki hâliyle eklenir, değişmez
            satirlar[tm_id] = {"transfermarkt_id": tm_id, "isim": bekleyenler[tm_id], "foto_url": adres}

    if satirlar:
        supabase.table("oyuncular").upsert(list(satirlar.values()), on_conflict="transfermarkt_id").execute()
        for tm_id in satirlar:
            del bekleyenler[tm_id]
    return len(satirlar)


def profilden_tamamla(bekleyenler):
    """Kadrosuna ulaşılamayan (ör. API'nin hata verdiği kadrolar) oyuncular için her oyuncunun profili ayrı sorgulanır."""
    toplam = len(bekleyenler)
    print(f"Profilden fotoğraf çekimi başlatılıyor. Fotoğrafsız oyuncu: {toplam}")

    yazilan = 0
    hata_sayisi = 0
    for sira, (tm_id, isim) in enumerate(list(bekleyenler.items()), start=1):
        profil = api_istek_at(f"/players/{tm_id}/profile")
        if profil is None:
            print(f"!! [{sira}/{toplam}] {isim}: profil alınamadı.")
            hata_sayisi += 1
            continue

        try:
            adet = fotograflari_kaydet([{"id": tm_id, "imageUrl": profil.get("imageUrl")}], bekleyenler)
        except Exception as e:
            print(f"!! [{sira}/{toplam}] {isim} kaydedilemedi: {e}")
            hata_sayisi += 1
            continue

        yazilan += adet
        print(f">> [{sira}/{toplam}] {isim}: {'fotoğraf yazıldı' if adet else 'fotoğrafı yok'}")
        time.sleep(0.3)  # Rate limit'e takılmamak için nefes aldırıyoruz

    print(f"\nToplam {yazilan} fotoğraf yazıldı. Fotoğrafsız kalan oyuncu: {len(bekleyenler)}.")
    if hata_sayisi:
        print(f"{hata_sayisi} hata oluştu. '!!' ile başlayan satırlara bakın.")


def sezonlari_oku():
    if len(sys.argv) == 1:
        return sezon_araligi()
    try:
        return sorted({int(arg) for arg in sys.argv[1:]})
    except ValueError:
        print("Kullanım: python fotograflar.py [sezon ...]   örn: python fotograflar.py 2024 2025")
        exit(1)


if __name__ == "__main__":
    bekleyenler = fotografsiz_oyunculari_oku()
    if "--profil" in sys.argv:
        profilden_tamamla(bekleyenler)
        exit(0)

    sezonlar = sezonlari_oku()
    print(f"Fotoğraf çekimi başlatılıyor. Fotoğrafsız oyuncu: {len(bekleyenler)}, sezonlar: {sezonlar[0]}-{sezonlar[-1]}")

    hata_sayisi = 0
    toplam_yazilan = 0

    for sezon in sezonlar:
        for lig in LIGLER:
            if not bekleyenler:
                break

            kulup_data = api_istek_at(f"/competitions/{lig}/clubs?season_id={sezon}")
            if not kulup_data or "clubs" not in kulup_data:
                print(f"!! {sezon} {lig} kulüpleri alınamadı, lig atlanıyor.")
                hata_sayisi += 1
                continue

            for kulup in kulup_data["clubs"]:
                if not kulup.get("id"):
                    continue

                oyuncu_data = api_istek_at(f"/clubs/{kulup['id']}/players?season_id={sezon}")
                if not oyuncu_data or "players" not in oyuncu_data:
                    print(f"!! {sezon} {kulup.get('name')} kadrosu alınamadı.")
                    hata_sayisi += 1
                    continue

                try:
                    yazilan = fotograflari_kaydet(oyuncu_data["players"], bekleyenler)
                except Exception as e:
                    print(f"!! {sezon} {kulup.get('name')} kaydedilemedi: {e}")
                    hata_sayisi += 1
                    continue

                toplam_yazilan += yazilan
                print(f">> {sezon} {kulup.get('name')}: {yazilan} fotoğraf (kalan fotoğrafsız: {len(bekleyenler)})")

                time.sleep(0.3)  # Rate limit'e takılmamak için nefes aldırıyoruz

    print(f"\nToplam {toplam_yazilan} fotoğraf yazıldı. Fotoğrafsız kalan oyuncu: {len(bekleyenler)} "
          "(Transfermarkt'ta fotoğrafı olmayanlar ya da kadrolarına ulaşılamayanlar).")
    if hata_sayisi:
        print(f"{hata_sayisi} hata oluştu. '!!' ile başlayan satırlara bakın; tekrar çalıştırınca sadece eksikler yazılır.")
