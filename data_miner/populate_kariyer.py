import os
import time
import re
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

YIL = 2023
LIGLER = ["TR1", "GB1", "ES1", "IT1", "L1", "FR1"]

def bonservis_parse(deger_str):
    if not deger_str or deger_str in ["?", "-", "Draft", "unknown"]:
        return 0.0
    deger = str(deger_str).lower().strip()
    if "free" in deger or "bedelsiz" in deger or "loan" in deger:
        return 0.0
    match = re.search(r'([0-9.]+)([km]?)', deger)
    if not match:
        return 0.0
    sayi = float(match.group(1))
    carpan = match.group(2)
    if carpan == 'm':
        return sayi * 1000000.0
    elif carpan == 'k':
        return sayi * 1000.0
    return sayi

def api_istek_at(endpoint):
    url = f"{API_BASE_URL}{endpoint}"
    while True:
        try:
            response = requests.get(url, timeout=15)
            if response.status_code == 200:
                return response.json()
            elif response.status_code == 429:
                print("Hız sınırına takıldık. 10 sn bekleniyor...")
                time.sleep(10)
            else:
                return None
        except Exception as e:
            print(f"Bağlantı hatası ({e}). 5 sn sonra tekrar deneniyor...")
            time.sleep(5)

def kariyer_verilerini_cek():
    print("1. Adım: Supabase'deki kulüp ve oyuncu haritası belleğe yükleniyor...")
    
    # Tüm kulüpleri al ve isim -> uuid eşle
    kulupler_raw = []
    offset = 0
    while True:
        res = supabase.table("kulupler").select("id, isim").range(offset, offset + 999).execute()
        if not res.data:
            break
        kulupler_raw.extend(res.data)
        offset += 1000
    kulup_map = {k["isim"]: k["id"] for k in kulupler_raw}
    print(f">> {len(kulup_map)} kulüp eşleşmesi yüklendi.")

    # Tüm oyuncuları al ve isim -> uuid eşle
    oyuncular_raw = []
    offset = 0
    while True:
        res = supabase.table("oyuncular").select("id, isim").range(offset, offset + 999).execute()
        if not res.data:
            break
        oyuncular_raw.extend(res.data)
        offset += 1000
    oyuncu_map = {o["isim"]: o["id"] for o in oyuncular_raw}
    print(f">> {len(oyuncu_map)} oyuncu eşleşmesi yüklendi.")

    eklenen_kariyer_sayisi = 0

    print("\n2. Adım: Ligler ve kulüpler üzerinden kariyer bağlantıları taranıyor...")
    for lig in LIGLER:
        print(f"\n=== {lig} Ligi Kariyer Taraması Başlıyor ===")
        kulup_data = api_istek_at(f"/competitions/{lig}/clubs?season_id={YIL}")
        if not kulup_data or "clubs" not in kulup_data:
            continue

        for kulup in kulup_data["clubs"]:
            kulup_id_tm = kulup.get("id")
            kulup_isim = kulup.get("name")
            
            # Kulüp Supabase'de var mı?
            supabase_kulup_id = kulup_map.get(kulup_isim)
            if not supabase_kulup_id:
                continue

            print(f">> {kulup_isim} oyuncuları taranıyor...")
            oyuncu_data = api_istek_at(f"/clubs/{kulup_id_tm}/players?season_id={YIL}")
            if not oyuncu_data or "players" not in oyuncu_data:
                continue

            for oyuncu in oyuncu_data["players"]:
                oyuncu_id_tm = oyuncu.get("id")
                oyuncu_isim = oyuncu.get("name")
                supabase_oyuncu_id = oyuncu_map.get(oyuncu_isim)
                
                if not supabase_oyuncu_id:
                    continue

                # 1. Mevcut sezon kariyer bağı
                try:
                    supabase.table("kariyer_gecmisi").insert({
                        "oyuncu_id": supabase_oyuncu_id,
                        "kulup_id": supabase_kulup_id,
                        "baslangic_yili": str(YIL),
                        "bonservis_bedeli": 0.0
                    }).execute()
                    eklenen_kariyer_sayisi += 1
                except Exception:
                    pass

                # 2. Geçmiş transferler
                transfer_data = api_istek_at(f"/players/{oyuncu_id_tm}/transfers")
                if transfer_data and "transfers" in transfer_data:
                    for transfer in transfer_data["transfers"]:
                        eski_kulup_isim = transfer.get("left", {}).get("name")
                        if not eski_kulup_isim:
                            continue

                        eski_kulup_uuid = kulup_map.get(eski_kulup_isim)
                        if eski_kulup_uuid:
                            islenmis_bonservis = bonservis_parse(transfer.get("fee"))
                            sezon = transfer.get("season", "").split("/")[0] if transfer.get("season") else "0000"

                            try:
                                supabase.table("kariyer_gecmisi").insert({
                                    "oyuncu_id": supabase_oyuncu_id,
                                    "kulup_id": eski_kulup_uuid,
                                    "baslangic_yili": str(sezon),
                                    "bonservis_bedeli": islenmis_bonservis
                                }).execute()
                                eklenen_kariyer_sayisi += 1
                            except Exception:
                                pass

                time.sleep(0.15)
            
            print(f"   [Ara Toplam] Eklenen Kariyer Kaydı: {eklenen_kariyer_sayisi}")

    print(f"\nİşlem tamamlandı! Toplam {eklenen_kariyer_sayisi} kariyer kaydı başarıyla eklendi.")

if __name__ == "__main__":
    kariyer_verilerini_cek()
