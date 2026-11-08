"""
Oyuncuların Wikipedia bilinirliğini çekip Supabase'e yazar. Transfermarkt dışı bir kaynaktır:
Wikidata'da her futbolcunun Transfermarkt oyuncu ID'si (P2446) kayıtlıdır, eşleştirme bununla yapılır.

Yazılanlar (oyuncular tablosu):
  - wikidata_id, wiki_dil_sayisi: kaç dilde Wikipedia sayfası olduğu. Wikidata'da kaydı olmayan oyuncu için 0.
  - trwiki_baslik, trwiki_goruntulenme: Türkçe sayfanın adı ve son 60 gündeki görüntülenmesi. Sayfa yoksa 0.
    Görüntülenmeler Türkçe Wikipedia'nın kendi API'sinden toplu alınır (prop=pageviews, tek istekte 50 sayfa).
    Bu API en fazla 60 gün geriye gider. Sayfa başına istek atan Pageviews REST API'si, binlerce istekte hız
    sınırına takıldığı için kullanılmaz.

Kullanım:
    python wikipedia.py          # sadece Wikipedia verisi henüz çekilmemiş oyuncular
    python wikipedia.py --hepsi  # tüm oyuncular baştan (Wikipedia değişkendir, her güncellemede önerilir)

Önce supabase/migrations/017_oyuncu_havuzu.sql çalıştırılmış olmalıdır.
Oyuncular 300'erli gruplar halinde işlenir ve her grup bitince yazılır: yarıda kesilirse tekrar çalıştırmak yeterli.
Görüntülenmesi alınamayan oyuncu işaretlenmez, bir sonraki çalıştırmada tekrar denenir.
"""
import sys
import time
from datetime import datetime, timezone

import requests

from main import supabase

SAYFA_BOYUTU = 1000  # Supabase tek istekte en fazla 1000 satır döndürür
GRUP_BOYUTU = 300    # Tek SPARQL sorgusundaki oyuncu sayısı
BASLIK_GRUBU = 50    # Wikipedia API'sinin tek istekte kabul ettiği en fazla sayfa
GUN_SAYISI = 60      # Wikipedia API'sinin verdiği en uzun görüntülenme dönemi
MAX_DENEME = 5

SPARQL = "https://query.wikidata.org/sparql"
TRWIKI_API = "https://tr.wikipedia.org/w/api.php"
# Wikimedia, User-Agent başlığı olmayan istekleri reddeder; başlıkta iletişim adresi olmasını ister
HEADERS = {"User-Agent": "ScoutIQ-data-miner/1.0 (https://github.com/BalciAbdulkadir/ScoutIQ)"}


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
            sorgu = sorgu.is_("wiki_cekim_tarihi", "null")
        sayfa = sorgu.execute().data
        oyuncular.extend(sayfa)
        if len(sayfa) < SAYFA_BOYUTU:
            return oyuncular
        bas += SAYFA_BOYUTU


def istek_at(yontem, url, **kwargs):
    """Wikimedia'ya istek atar. 429 ve bağlantı hatalarında bekleyip tekrar dener; olmazsa None döndürür."""
    for deneme in range(1, MAX_DENEME + 1):
        try:
            r = requests.request(yontem, url, headers=HEADERS, timeout=60, **kwargs)
            if r.status_code == 429:
                bekle = int(r.headers.get("Retry-After", 10))
                print(f"Hız sınırına takıldık. {bekle} sn bekleniyor...")
                time.sleep(bekle)
                continue
            return r
        except requests.RequestException as e:
            print(f"Bağlantı hatası ({e}). 5 sn sonra tekrar deneniyor... ({deneme}/{MAX_DENEME})")
            time.sleep(5)
    return None


def wikidata_grup(tm_idleri):
    """Transfermarkt ID -> {wikidata_id, wiki_dil_sayisi, trwiki_baslik}. Sorgu başarısızsa None."""
    degerler = " ".join(f'"{i}"' for i in tm_idleri)
    sorgu = f"""
    SELECT ?tm ?item ?sl ?trBaslik WHERE {{
      VALUES ?tm {{ {degerler} }}
      ?item wdt:P2446 ?tm ;
            wikibase:sitelinks ?sl .
      OPTIONAL {{
        ?tr schema:about ?item ;
            schema:isPartOf <https://tr.wikipedia.org/> ;
            schema:name ?trBaslik .
      }}
    }}"""
    r = istek_at("POST", SPARQL, data={"query": sorgu, "format": "json"})
    if r is None or r.status_code != 200:
        return None

    sonuc = {}
    for satir in r.json()["results"]["bindings"]:
        kayit = {
            "wikidata_id": satir["item"]["value"].rsplit("/", 1)[-1],
            "wiki_dil_sayisi": int(satir["sl"]["value"]),
            "trwiki_baslik": satir.get("trBaslik", {}).get("value"),
        }
        tm = satir["tm"]["value"]
        # Aynı Transfermarkt ID'si nadiren iki Wikidata kaydında geçer: sayfası çok olan alınır
        if tm not in sonuc or kayit["wiki_dil_sayisi"] > sonuc[tm]["wiki_dil_sayisi"]:
            sonuc[tm] = kayit
    return sonuc


def trwiki_goruntulenmeler(basliklar):
    """Türkçe sayfaların son GUN_SAYISI gündeki toplam görüntülenmesi: başlık -> sayı.
    Sayfa yoksa 0. İsteği başarısız olan başlıklar sonuçta yer almaz."""
    sonuc = {}
    for i in range(0, len(basliklar), BASLIK_GRUBU):
        parametreler = {
            "action": "query", "prop": "pageviews", "titles": "|".join(basliklar[i:i + BASLIK_GRUBU]),
            "pvipdays": GUN_SAYISI, "format": "json", "formatversion": 2,
        }
        # API her istekte sayfaların bir kısmının görüntülenmesini verir, kalanı için devam (continue) bilgisi döner
        while True:
            r = istek_at("GET", TRWIKI_API, params=parametreler)
            if r is None or r.status_code != 200:
                break
            j = r.json()
            for sayfa in j["query"]["pages"]:
                if sayfa.get("missing"):
                    sonuc[sayfa["title"]] = 0
                elif "pageviews" in sayfa:
                    sonuc[sayfa["title"]] = sum(v or 0 for v in sayfa["pageviews"].values())
            if "continue" not in j:
                break
            parametreler.update(j["continue"])
    return sonuc


def grubu_isle(oyuncular):
    """Grubu işler ve yazar. (yazılan, Wikipedia'da bulunan, görüntülenmesi alınamayan) döndürür."""
    wiki = wikidata_grup([o["transfermarkt_id"] for o in oyuncular])
    if wiki is None:
        return 0, 0, len(oyuncular)

    goruntulenme = trwiki_goruntulenmeler(sorted({k["trwiki_baslik"] for k in wiki.values() if k["trwiki_baslik"]}))

    simdi = datetime.now(timezone.utc).isoformat()
    satirlar = []
    hatali = 0
    for o in oyuncular:
        kayit = wiki.get(o["transfermarkt_id"], {})
        izlenme = goruntulenme.get(kayit["trwiki_baslik"]) if kayit.get("trwiki_baslik") else 0
        if izlenme is None:
            hatali += 1
        satirlar.append({
            # Upsert, insert yolu için not null kolonları da ister; mevcut oyuncular olduğu için sadece güncellenir
            "id": o["id"], "transfermarkt_id": o["transfermarkt_id"], "isim": o["isim"],
            "wikidata_id": kayit.get("wikidata_id"),
            "wiki_dil_sayisi": kayit.get("wiki_dil_sayisi", 0),
            "trwiki_baslik": kayit.get("trwiki_baslik"),
            "trwiki_goruntulenme": izlenme,
            "wiki_cekim_tarihi": simdi if izlenme is not None else None,
        })

    supabase.table("oyuncular").upsert(satirlar, on_conflict="id").execute()
    return len(satirlar), len(wiki), hatali


if __name__ == "__main__":
    oyuncular = oyunculari_oku("--hepsi" in sys.argv)
    toplam = len(oyuncular)
    print(f"Wikipedia çekimi başlatılıyor. İşlenecek oyuncu: {toplam}, görüntülenme dönemi: son {GUN_SAYISI} gün")

    hata_sayisi = 0
    baslangic = time.time()
    try:
        for i in range(0, toplam, GRUP_BOYUTU):
            grup = oyuncular[i:i + GRUP_BOYUTU]
            try:
                yazilan, bulunan, hatali = grubu_isle(grup)
            except Exception as e:
                print(f"!! [{i + len(grup)}/{toplam}] grup kaydedilemedi: {e}")
                hata_sayisi += len(grup)
                continue

            hata_sayisi += hatali
            biten = i + len(grup)
            kalan_dk = (time.time() - baslangic) / biten * (toplam - biten) / 60
            if not yazilan:
                print(f"!! [{biten}/{toplam}] Wikidata sorgusu başarısız, grup atlandı.")
            else:
                hata = f", {hatali} görüntülenme alınamadı" if hatali else ""
                print(f">> [{biten}/{toplam}] {bulunan}/{len(grup)} oyuncu Wikipedia'da{hata} (kalan ~{kalan_dk:.0f} dk)")
    except KeyboardInterrupt:
        print("\nDurduruldu. Tekrar çalıştırınca kalan oyuncular çekilir.")
        exit(1)

    if hata_sayisi:
        print(f"\nİşlem tamamlandı ama {hata_sayisi} oyuncu işaretlenmedi. Tekrar çalıştırınca sadece eksikler çekilir.")
    else:
        print("\nİşlem hatasız tamamlandı.")
