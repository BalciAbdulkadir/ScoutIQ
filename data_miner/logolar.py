"""
Veritabanındaki kulüplerin logo adreslerini (logo_url) Transfermarkt API'den çekip Supabase'e yazar.
Lig kulüp listesinde logo gelmediği için her kulübün profili ayrı sorgulanır.

Kullanım:
    python logolar.py

Önce supabase/migrations/008_kulup_logolari.sql çalıştırılmış olmalıdır.
Sadece veritabanında zaten olan ve logosu boş olan kulüpler güncellenir: yeni kulüp eklenmez,
logo dışındaki alanlar değişmez. Yarıda kesilirse tekrar çalıştırmak yeterli, logosu yazılmış kulüpler atlanır.
"""
import time

from main import api_istek_at, supabase

SAYFA_BOYUTU = 1000  # Supabase tek istekte en fazla 1000 satır döndürür


def logosuz_kulupleri_oku():
    """Logosu henüz yazılmamış kulüpler: transfermarkt_id -> isim"""
    kulupler = {}
    bas = 0
    while True:
        sayfa = (
            supabase.table("kulupler")
            .select("transfermarkt_id, isim")
            .is_("logo_url", "null")
            .order("transfermarkt_id")
            .range(bas, bas + SAYFA_BOYUTU - 1)
            .execute()
            .data
        )
        kulupler.update({k["transfermarkt_id"]: k["isim"] for k in sayfa})
        if len(sayfa) < SAYFA_BOYUTU:
            return kulupler
        bas += SAYFA_BOYUTU


def logo_adresi(profil):
    """Kulübün Transfermarkt logosunun adresi. Logosu olmayan kulüpler için None:
    Transfermarkt'ın boş logo resmi (default.png) uygulamada kalkan ikonuyla gösterilir."""
    adres = profil.get("image")
    if not adres or "/default." in adres:
        return None
    return adres


if __name__ == "__main__":
    bekleyenler = logosuz_kulupleri_oku()
    toplam = len(bekleyenler)
    print(f"Logo çekimi başlatılıyor. Logosuz kulüp: {toplam}")

    yazilan = 0
    hata_sayisi = 0
    for sira, (tm_id, isim) in enumerate(bekleyenler.items(), start=1):
        profil = api_istek_at(f"/clubs/{tm_id}/profile")
        if profil is None:
            print(f"!! [{sira}/{toplam}] {isim}: profil alınamadı.")
            hata_sayisi += 1
            continue

        adres = logo_adresi(profil)
        if not adres:
            print(f">> [{sira}/{toplam}] {isim}: logosu yok")
            continue

        try:
            supabase.table("kulupler").update({"logo_url": adres}).eq("transfermarkt_id", tm_id).execute()
        except Exception as e:
            print(f"!! [{sira}/{toplam}] {isim} kaydedilemedi: {e}")
            hata_sayisi += 1
            continue

        yazilan += 1
        print(f">> [{sira}/{toplam}] {isim}: logo yazıldı")
        time.sleep(0.3)  # Rate limit'e takılmamak için nefes aldırıyoruz

    print(f"\nToplam {yazilan} logo yazıldı. Logosuz kalan kulüp: {toplam - yazilan}.")
    if hata_sayisi:
        print(f"{hata_sayisi} hata oluştu. '!!' ile başlayan satırlara bakın; tekrar çalıştırınca sadece eksikler yazılır.")
