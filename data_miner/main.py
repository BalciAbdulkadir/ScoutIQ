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

# Hedef: 5 Büyük Lig + Süper Lig (25/26 Sezonu)
YIL = 2025
LIGLER = ["TR1", "GB1", "ES1", "IT1", "L1", "FR1"] 

def bonservis_parse(deger_str):
    """Bonservis string'ini Supabase DECIMAL(15,2) formatı için float'a çevirir."""
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

def veri_tabanina_upsert(tablo_adi, veri):
    try:
        supabase.table(tablo_adi).upsert(veri).execute()
    except Exception as e:
        print(f"[{tablo_adi}] Yazma hatası: {e}")

def verileri_cek_ve_isle():
    for lig in LIGLER:
        print(f"\n=== {lig} Ligi {YIL} Sezonu Başlıyor ===")
        
        kulup_data = api_istek_at(f"/competitions/{lig}/clubs?season_id={YIL}")
        if not kulup_data or "clubs" not in kulup_data:
            continue
            
        for kulup in kulup_data["clubs"]:
            kulup_id = kulup.get("id")
            kulup_isim = kulup.get("name")
            
            # 1. KULÜBÜ KAYDET
            veri_tabanina_upsert("kulupler", {
                "isim": kulup_isim,
                "lig": lig,
                "logo_url": kulup.get("image", "")
            })
            print(f">> Kulüp işleniyor: {kulup_isim}")
            
            oyuncu_data = api_istek_at(f"/clubs/{kulup_id}/players?season_id={YIL}")
            if not oyuncu_data or "players" not in oyuncu_data:
                continue
                
            for oyuncu in oyuncu_data["players"]:
                oyuncu_id = oyuncu.get("id")
                oyuncu_isim = oyuncu.get("name")
                
                # 2. OYUNCUYU KAYDET
                veri_tabanina_upsert("oyuncular", {
                    "isim": oyuncu_isim,
                    "uyruk": oyuncu.get("nationality", ""),
                    "aktif_durum": True
                })
                
                # 3. OYUNCUNUN TRANSFER GEÇMİŞİNİ KAYDET
                transfer_data = api_istek_at(f"/players/{oyuncu_id}/transfers")
                if transfer_data and "transfers" in transfer_data:
                    for transfer in transfer_data["transfers"]:
                        islenmis_bonservis = bonservis_parse(transfer.get("fee"))
                        
                        # Not: MVP için kulüp ve oyuncu UUID eşleştirmelerini atlıyoruz. 
                        # Veritabanında foreign key'ler isim yerine Supabase'in atadığı UUID'leri bekler.
                        # Gerçek ilişkisel veriyi kurarken Supabase'den ID'leri çekip buraya basman gerekecek.
                        
                        # kariyer_payload = {
                        #     "oyuncu_id": "BULUNACAK_OYUNCU_UUID",
                        #     "kulup_id": "BULUNACAK_KULUP_UUID",
                        #     "baslangic_yili": transfer.get("season"),
                        #     "bonservis_bedeli": islenmis_bonservis
                        # }
                        # veri_tabanina_upsert("kariyer_gecmisi", kariyer_payload)
                
                time.sleep(0.3) # Rate limit'e takılmamak için nefes aldırıyoruz

if __name__ == "__main__":
    print("Veri madenciliği başlatılıyor. Bu işlem biraz zaman alabilir...")
    verileri_cek_ve_isle()
    print("\nİşlem tamamlandı.")