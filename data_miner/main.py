"""
Transfermarkt API'den kulüp, oyuncu ve kariyer verisini sezon sezon çekip Supabase'e yazar.

Kullanım:
    python main.py            # varsayılan sezonlar: 2023/2024 - 2026/2027
    python main.py 2025 2026  # sadece verilen sezonlar, eskiden yeniye işlenir

Önce supabase/migrations/001_temel_veri_duzeltmeleri.sql ve 007_oyuncu_fotograflari.sql çalıştırılmış olmalıdır.
Tekrar çalıştırmak güvenlidir: kayıtlar transfermarkt_id üzerinden güncellenir, çoğalmaz.
Yeni eklenen oyuncuların fotoğrafları da yazılır. Mevcut oyuncuların fotoğrafları için: python fotograflar.py
Lig kulüp listesinde logo gelmez. Yeni eklenen kulüplerin logoları için: python logolar.py
"""
import os
import sys
import time
import requests
from dotenv import load_dotenv
from supabase import create_client, Client

load_dotenv()

URL = os.getenv("SUPABASE_URL")
KEY = os.getenv("SUPABASE_KEY")

if not URL or not KEY:
    print("Hata: .env dosyasında SUPABASE_URL veya SUPABASE_KEY eksik!")
    exit(1)

supabase: Client = create_client(URL, KEY)
API_BASE_URL = "http://localhost:8000"

# Hedef: 5 Büyük Lig + Süper Lig
LIGLER = ["TR1", "GB1", "ES1", "IT1", "L1", "FR1"]

# Transfermarkt'ta season_id=2025, 2025/2026 sezonudur.
VARSAYILAN_SEZONLAR = [2023, 2024, 2025, 2026]
MAX_DENEME = 5

def api_istek_at(endpoint):
    url = f"{API_BASE_URL}{endpoint}"
    for deneme in range(1, MAX_DENEME + 1):
        try:
            response = requests.get(url, timeout=30)
            if response.status_code == 200:
                return response.json()
            if response.status_code == 429:
                print("Hız sınırına takıldık. 10 sn bekleniyor...")
                time.sleep(10)
                continue
            print(f"!! API hatası {response.status_code}: {endpoint}")
            return None
        except requests.RequestException as e:
            print(f"Bağlantı hatası ({e}). 5 sn sonra tekrar deneniyor... ({deneme}/{MAX_DENEME})")
            time.sleep(5)
    print(f"!! Vazgeçildi: {endpoint}")
    return None

def kulup_kaydet(kulup, lig):
    """Kulübü ekler ya da günceller, Supabase UUID'sini döndürür."""
    res = supabase.table("kulupler").upsert(
        {"transfermarkt_id": kulup["id"], "isim": kulup["name"], "lig": lig},
        on_conflict="transfermarkt_id",
    ).execute()
    return res.data[0]["id"]

def foto_adresi(oyuncu):
    """Oyuncunun Transfermarkt fotoğrafının adresi. Fotoğrafı olmayan oyuncular için None:
    Transfermarkt'ın boş siluet resmi (default.jpg) uygulamada baş harflerle gösterilir."""
    adres = oyuncu.get("imageUrl")
    if not adres or "/default." in adres:
        return None
    return adres

def oyunculari_kaydet(oyuncular):
    """Kadrodaki oyuncuları toplu ekler ya da günceller, Supabase UUID'lerini döndürür."""
    # Aynı oyuncu listede iki kez geçerse upsert hata verir, transfermarkt_id ile tekilleştiriyoruz
    satirlar = {}
    for oyuncu in oyuncular:
        if not oyuncu.get("id") or not oyuncu.get("name") or oyuncu["id"] in satirlar:
            continue
        uyruklar = oyuncu.get("nationality") or []
        satirlar[oyuncu["id"]] = {
            "transfermarkt_id": oyuncu["id"],
            "isim": oyuncu["name"],
            "uyruk": uyruklar[0] if uyruklar else None,
            "foto_url": foto_adresi(oyuncu),
        }

    if not satirlar:
        return []

    res = supabase.table("oyuncular").upsert(
        list(satirlar.values()), on_conflict="transfermarkt_id"
    ).execute()
    return [o["id"] for o in res.data]

def sezonu_isle(sezon):
    """Bir sezonun tüm lig ve kulüplerini işler, karşılaşılan hata sayısını döndürür."""
    print(f"\n########## {sezon}/{sezon + 1} Sezonu ##########")
    hata_sayisi = 0

    for lig in LIGLER:
        kulup_data = api_istek_at(f"/competitions/{lig}/clubs?season_id={sezon}")
        if not kulup_data or "clubs" not in kulup_data:
            print(f"!! {lig} kulüpleri alınamadı, lig atlanıyor.")
            hata_sayisi += 1
            continue

        print(f"\n=== {lig} Ligi ({len(kulup_data['clubs'])} kulüp) ===")

        for kulup in kulup_data["clubs"]:
            if not kulup.get("id") or not kulup.get("name"):
                continue

            oyuncu_data = api_istek_at(f"/clubs/{kulup['id']}/players?season_id={sezon}")
            if not oyuncu_data or "players" not in oyuncu_data:
                print(f"!! {kulup['name']} kadrosu alınamadı.")
                hata_sayisi += 1
                continue

            try:
                kulup_id = kulup_kaydet(kulup, lig)
                oyuncu_idleri = oyunculari_kaydet(oyuncu_data["players"])
                if oyuncu_idleri:
                    supabase.rpc("kariyer_sezon_ekle", {
                        "p_kulup_id": kulup_id,
                        "p_sezon": sezon,
                        "p_oyuncu_ids": oyuncu_idleri,
                    }).execute()
                print(f">> {kulup['name']}: {len(oyuncu_idleri)} oyuncu")
            except Exception as e:
                print(f"!! {kulup['name']} kaydedilemedi: {e}")
                hata_sayisi += 1

            time.sleep(0.3)  # Rate limit'e takılmamak için nefes aldırıyoruz

    return hata_sayisi

def sezonlari_oku():
    if len(sys.argv) == 1:
        return VARSAYILAN_SEZONLAR
    try:
        # Eskiden yeniye: kulübün "lig" bilgisi en son sezondaki ligi olarak kalır
        return sorted({int(arg) for arg in sys.argv[1:]})
    except ValueError:
        print("Kullanım: python main.py [sezon ...]   örn: python main.py 2025 2026")
        exit(1)

if __name__ == "__main__":
    sezonlar = sezonlari_oku()
    print(f"Veri madenciliği başlatılıyor. Sezonlar: {sezonlar}")

    toplam_hata = 0
    for sezon in sezonlar:
        toplam_hata += sezonu_isle(sezon)

    if toplam_hata:
        print(f"\nİşlem tamamlandı ama {toplam_hata} hata oluştu. '!!' ile başlayan satırlara bakın.")
    else:
        print("\nİşlem hatasız tamamlandı.")
