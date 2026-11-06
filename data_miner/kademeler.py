"""
Oyuncuların bilinirlik skorunu hesaplar ve kademelerini (unlu / bilinen / diger / cevap) oyuncular tablosuna yazar.
API'ye gitmez, sadece veritabanını okur: istatistikler.py, wikipedia.py ve milli_takimlar.py'den sonra çalıştırılır.
İstenildiği kadar tekrar çalıştırılabilir.

Kullanım:
    python kademeler.py                  # hesaplar, yazar ve kontrol CSV'sini çıkarır
    python kademeler.py --dene           # sadece özet ve kontrol CSV'si, veritabanına yazmaz
    python kademeler.py --csv yol.csv    # kontrol CSV'sinin yeri (varsayılan: kademe_kontrol.csv)

Önce supabase/migrations/017_oyuncu_havuzu.sql çalıştırılmış olmalıdır.

Soru havuzu: 6 ligde en az MIN_UST_LIG_MAC lig maçı, ya da en az MIN_MILLI_MAC A milli maçı, ya da efsane listesinde olmak.
Havuzdakiler bilinirlik skoruna göre sıralanır: ilk UNLU_SAYISI 'unlu', sonraki BILINEN_SAYISI 'bilinen', kalanı 'diger'.
Havuza girmeyip veritabanındaki bir kulüpte ya da A milli takımda en az 1 maçı olanlar 'cevap'tır: soru üretmez,
sadece cevap olarak kabul edilir. Bunların hiçbirinde maçı olmayan oyuncuların kademesi boştur.

Skor: her bileşen havuzdaki yüzdelik sırasına çevrilir ("havuzdakilerin yüzde kaçından yüksek") ve ağırlıklı
ortalaması alınır. Verisi olmayan bileşen (ör. efsanenin piyasa değeri) o oyuncu için atlanır.
"""
import csv
import random
import sys
import time
from collections import defaultdict

from efsaneler import EFSANELER
from main import supabase

SAYFA_BOYUTU = 1000  # Supabase tek istekte en fazla 1000 satır döndürür

MIN_UST_LIG_MAC = 100
MIN_MILLI_MAC = 20
UNLU_SAYISI = 500
BILINEN_SAYISI = 1500

# Türkçe görüntülenme, Türk kullanıcının tanıdığı Süper Lig yıldızlarını yukarı taşımak için en yüksek ağırlıktır
AGIRLIKLAR = {
    "trwiki_goruntulenme": 0.35,
    "wiki_dil_sayisi": 0.25,
    "zirve_piyasa_degeri": 0.15,
    "ust_lig_mac": 0.125,
    "milli_mac": 0.125,
}


def hepsini_oku(tablo, kolonlar, sira, filtre=None):
    """Tablonun tüm satırlarını sayfa sayfa okur. Bağlantı anlık koparsa sayfa tekrar denenir."""
    satirlar = []
    bas = 0
    while True:
        for deneme in range(1, 6):
            try:
                sorgu = supabase.table(tablo).select(kolonlar).order(sira).range(bas, bas + SAYFA_BOYUTU - 1)
                if filtre:
                    sorgu = filtre(sorgu)
                sayfa = sorgu.execute().data
                break
            except Exception as e:
                if deneme == 5:
                    raise
                print(f"Bağlantı hatası ({e}). Tekrar deneniyor... ({deneme}/5)")
                time.sleep(3)
        satirlar.extend(sayfa)
        if len(sayfa) < SAYFA_BOYUTU:
            return satirlar
        bas += SAYFA_BOYUTU


def yuzdelik_sira(degerler):
    """id -> değer sözlüğünü id -> (0, 1] yüzdelik sıraya çevirir. Eşit değerler sıralarının ortalamasını alır.
    Değeri None olanlar sonuçta yer almaz."""
    dolu = sorted((d, i) for i, d in degerler.items() if d is not None)
    n = len(dolu)
    sonuc = {}
    bas = 0
    while bas < n:
        son = bas
        while son + 1 < n and dolu[son + 1][0] == dolu[bas][0]:
            son += 1
        ortalama_sira = (bas + son) / 2 + 1  # 1'den başlayan sıra
        for _, i in dolu[bas:son + 1]:
            sonuc[i] = ortalama_sira / n
        bas = son + 1
    return sonuc


def verileri_oku():
    print("kariyer_gecmisi maç sayıları güncelleniyor...")
    supabase.rpc("kariyer_mac_sayisi_hesapla").execute()

    print("Veriler okunuyor...")
    oyuncular = hepsini_oku(
        "oyuncular",
        "id, transfermarkt_id, isim, ust_lig_mac, zirve_piyasa_degeri, wiki_dil_sayisi, trwiki_goruntulenme, "
        "kademe_override",
        "id",
    )
    milli_mac = defaultdict(int)
    for r in hepsini_oku("milli_takim_kariyeri", "oyuncu_id, mac_sayisi", "id"):
        milli_mac[r["oyuncu_id"]] += r["mac_sayisi"]
    mac_yapanlar = {
        r["oyuncu_id"]
        for r in hepsini_oku("kariyer_gecmisi", "oyuncu_id", "oyuncu_id,kulup_id", lambda s: s.gt("mac_sayisi", 0))
    }
    return oyuncular, milli_mac, mac_yapanlar


def kademeleri_hesapla(oyuncular, milli_mac, mac_yapanlar):
    """Her oyuncuya 'milli_mac', 'havuzda', 'bilinirlik' ve 'kademe' ekler."""
    for o in oyuncular:
        o["milli_mac"] = milli_mac.get(o["id"], 0)
        o["havuzda"] = (
            (o["ust_lig_mac"] or 0) >= MIN_UST_LIG_MAC
            or o["milli_mac"] >= MIN_MILLI_MAC
            or o["transfermarkt_id"] in EFSANELER
        )

    havuz = [o for o in oyuncular if o["havuzda"]]
    siralar = {kolon: yuzdelik_sira({o["id"]: o[kolon] for o in havuz}) for kolon in AGIRLIKLAR}
    for o in havuz:
        toplam = agirlik_toplami = 0.0
        for kolon, agirlik in AGIRLIKLAR.items():
            if o["id"] in siralar[kolon]:
                toplam += agirlik * siralar[kolon][o["id"]]
                agirlik_toplami += agirlik
        o["bilinirlik"] = toplam / agirlik_toplami if agirlik_toplami else 0.0

    havuz.sort(key=lambda o: (-o["bilinirlik"], o["isim"]))
    for sira, o in enumerate(havuz):
        o["sira"] = sira + 1
        if sira < UNLU_SAYISI:
            o["kademe"] = "unlu"
        elif sira < UNLU_SAYISI + BILINEN_SAYISI:
            o["kademe"] = "bilinen"
        else:
            o["kademe"] = "diger"

    for o in oyuncular:
        if not o["havuzda"]:
            o["bilinirlik"] = None
            o["sira"] = None
            o["kademe"] = "cevap" if o["id"] in mac_yapanlar or o["milli_mac"] >= 1 else None
    return havuz


def ozet_yaz(oyuncular):
    sayilar = defaultdict(int)
    for o in oyuncular:
        sayilar[o["kademe"]] += 1
    for kademe in ("unlu", "bilinen", "diger", "cevap", None):
        print(f"  {kademe or 'kademesiz (kulüp ve milli maçı yok)'}: {sayilar[kademe]}")

    eksik = sum(1 for o in oyuncular if o["ust_lig_mac"] is None)
    if eksik:
        print(f"Uyarı: {eksik} oyuncunun istatistiği çekilmemiş (istatistikler.py), üst lig maçı 0 sayıldı.")
    eksik = sum(1 for o in oyuncular if o["wiki_dil_sayisi"] is None)
    if eksik:
        print(f"Uyarı: {eksik} oyuncunun Wikipedia verisi çekilmemiş (wikipedia.py), skorda atlandı.")
    elle = sum(1 for o in oyuncular if o["kademe_override"])
    if elle:
        print(f"{elle} oyuncunun kademesi elle düzeltilmiş (kademe_override); uygulama onları kullanır.")


def kontrol_csv_yaz(yol, oyuncular, havuz):
    """İlk 100 'unlu' ve her kademeden rastgele 50 oyuncu"""
    random.seed(1)
    satirlar = [("ilk 100", o) for o in havuz[:100]]
    for kademe in ("unlu", "bilinen", "diger", "cevap"):
        grup = [o for o in oyuncular if o["kademe"] == kademe]
        satirlar += [(f"rastgele {kademe}", o) for o in random.sample(grup, min(50, len(grup)))]

    # Excel'in Türkçe karakterleri ve sütunları doğru açması için: UTF-8 BOM ve noktalı virgül
    with open(yol, "w", newline="", encoding="utf-8-sig") as f:
        w = csv.writer(f, delimiter=";")
        w.writerow(["liste", "kademe", "elle kademe", "sıra", "oyuncu", "bilinirlik", "wiki dil sayısı",
                    "zirve piyasa değeri (M€)", "tr wiki görüntülenme", "üst lig maç", "milli maç"])
        for liste, o in satirlar:
            w.writerow([
                liste, o["kademe"], o["kademe_override"] or "", o["sira"] or "", o["isim"],
                f"{o['bilinirlik']:.3f}".replace(".", ",") if o["bilinirlik"] is not None else "",
                o["wiki_dil_sayisi"], f"{(o['zirve_piyasa_degeri'] or 0) / 1e6:.1f}".replace(".", ","),
                o["trwiki_goruntulenme"], o["ust_lig_mac"], o["milli_mac"],
            ])


def yaz(oyuncular):
    satirlar = [
        # Upsert, insert yolu için not null kolonları da ister; mevcut oyuncular olduğu için sadece güncellenir
        {"id": o["id"], "transfermarkt_id": o["transfermarkt_id"], "isim": o["isim"],
         "bilinirlik": o["bilinirlik"], "kademe": o["kademe"]}
        for o in oyuncular
    ]
    for bas in range(0, len(satirlar), SAYFA_BOYUTU):
        supabase.table("oyuncular").upsert(satirlar[bas:bas + SAYFA_BOYUTU], on_conflict="id").execute()
        print(f">> {min(bas + SAYFA_BOYUTU, len(satirlar))}/{len(satirlar)} oyuncu yazıldı")


def csv_yolu():
    if "--csv" not in sys.argv:
        return "kademe_kontrol.csv"
    try:
        return sys.argv[sys.argv.index("--csv") + 1]
    except IndexError:
        print("Kullanım: python kademeler.py [--dene] [--csv yol.csv]")
        exit(1)


if __name__ == "__main__":
    yol = csv_yolu()
    oyuncular, milli_mac, mac_yapanlar = verileri_oku()
    havuz = kademeleri_hesapla(oyuncular, milli_mac, mac_yapanlar)

    print(f"\nSoru havuzu: {len(havuz)} oyuncu")
    ozet_yaz(oyuncular)
    kontrol_csv_yaz(yol, oyuncular, havuz)
    print(f"\nKontrol listesi yazıldı: {yol}")

    if "--dene" in sys.argv:
        print("Deneme: veritabanına yazılmadı.")
    else:
        print()
        yaz(oyuncular)
        print("\nKademeler yazıldı.")
