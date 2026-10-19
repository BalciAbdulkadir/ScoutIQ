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

# Hedef: 5 Büyük Lig + Süper Lig (2026/2027 Sezonu - Hoca'nın İsteği)
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

def verileri_cek_ve_isle():
    for lig in LIGLER:
        print(f"\n=== {lig} Ligi {YIL} Sezonu Başlıyor ===")
        
        kulup_data = api_istek_at(f"/competitions/{lig}/clubs?season_id={YIL}")
        if not kulup_data or "clubs" not in kulup_data:
            continue
            
        for kulup in kulup_data["clubs"]:
            kulup_id_tm = kulup.get("id")
            kulup_isim = kulup.get("name")
            
            # 1. KULÜBÜ KAYDET VE UUID AL
            kulup_res = supabase.table("kulupler").select("id").eq("isim", kulup_isim).execute()
            if not kulup_res.data:
                yeni_kulup = supabase.table("kulupler").insert({
                    "isim": kulup_isim,
                    "lig": lig,
                    "logo_url": kulup.get("image", "")
                }).execute()
                supabase_kulup_id = yeni_kulup.data[0]["id"]
            else:
                supabase_kulup_id = kulup_res.data[0]["id"]
                
            print(f">> Kulüp işleniyor: {kulup_isim}")
            
            oyuncu_data = api_istek_at(f"/clubs/{kulup_id_tm}/players?season_id={YIL}")
            if not oyuncu_data or "players" not in oyuncu_data:
                continue
                
            for oyuncu in oyuncu_data["players"]:
                oyuncu_id_tm = oyuncu.get("id")
                oyuncu_isim = oyuncu.get("name")
                
                # 2. OYUNCUYU KAYDET VE UUID AL
                oyuncu_res = supabase.table("oyuncular").select("id").eq("isim", oyuncu_isim).execute()
                if not oyuncu_res.data:
                    yeni_oyuncu = supabase.table("oyuncular").insert({
                        "isim": oyuncu_isim,
                        "uyruk": oyuncu.get("nationality", ""),
                        "aktif_durum": True
                    }).execute()
                    supabase_oyuncu_id = yeni_oyuncu.data[0]["id"]
                else:
                    supabase_oyuncu_id = oyuncu_res.data[0]["id"]
                
                # 3. KARIYER GEÇMİŞİNİ KAYDET (KÖPRÜ)
                # Önce 2026 yılı için bu kulüple bağını atıyoruz.
                try:
                    supabase.table("kariyer_gecmisi").insert({
                        "oyuncu_id": supabase_oyuncu_id,
                        "kulup_id": supabase_kulup_id,
                        "baslangic_yili": str(YIL),
                        "bonservis_bedeli": 0.0 # Mevcut sezon
                    }).execute()
                except Exception:
                    pass # Zaten ekliyse UNIQUE constraint patlar, yutuyoruz.

                # 4. ESKİ TRANSFER GEÇMİŞİNİ KAYDET (Bonservis Oyunu İçin)
                transfer_data = api_istek_at(f"/players/{oyuncu_id_tm}/transfers")
                if transfer_data and "transfers" in transfer_data:
                    for transfer in transfer_data["transfers"]:
                        eski_kulup_isim = transfer.get("left", {}).get("name")
                        if not eski_kulup_isim:
                            continue

                        # Eski kulübün Supabase UUID'sini bulmaya çalış
                        eski_kulup_res = supabase.table("kulupler").select("id").eq("isim", eski_kulup_isim).execute()
                        if eski_kulup_res.data:
                            eski_kulup_uuid = eski_kulup_res.data[0]["id"]
                            islenmis_bonservis = bonservis_parse(transfer.get("fee"))
                            sezon = transfer.get("season", "").split("/")[0] if transfer.get("season") else "0000"

                            try:
                                supabase.table("kariyer_gecmisi").insert({
                                    "oyuncu_id": supabase_oyuncu_id,
                                    "kulup_id": eski_kulup_uuid,
                                    "baslangic_yili": str(sezon),
                                    "bonservis_bedeli": islenmis_bonservis
                                }).execute()
                            except Exception:
                                pass # Tekrarlanan kariyerleri yutuyoruz

                time.sleep(0.3) 

if __name__ == "__main__":
    print("Veri madenciliği başlatılıyor. Bu işlem biraz zaman alabilir...")
    verileri_cek_ve_isle()
    print("\nİşlem tamamlandı.")