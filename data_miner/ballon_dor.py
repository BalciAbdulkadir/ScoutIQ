"""
Ballon d'Or sıralamalarını (1995'ten bugüne, her yılın aday listesi) İngilizce Wikipedia'dan çekip Supabase'deki
ballon_dor_siralamalari tablosuna yazar. Transfermarkt API'si Ballon d'Or sıralamasını vermediği için kaynak Wikipedia'dır;
sadece kazananlar oyuncu_basarilari tablosunda zaten vardır ("Winner Ballon d'Or").

Her yılın sayfasındaki erkekler sıralama tablosu okunur (Rank, Player, Points sütunları; 2010-2015 FIFA Ballon d'Or'da
puan yerine yüzde vardır). Oyuncular bizim oyuncular tablosuyla Wikidata kimliği üzerinden eşleştirilir:
  1) Wikipedia sayfasının Wikidata kimliği = oyuncular.wikidata_id
  2) Olmazsa Wikidata'daki Transfermarkt oyuncu ID'si (P2446) = oyuncular.transfermarkt_id
Eşleşmeyen oyuncular da yazılır (oyuncu_id boş); veritabanında olmayan oyuncuyu gösterir.

Kullanım:
    python ballon_dor.py                 # 1995'ten bugüne bütün yıllar, tablo baştan yazılır
    python ballon_dor.py --dene          # çeker ve özetler, veritabanına yazmaz
    python ballon_dor.py --yil 2015      # sadece verilen yıllar (birden fazla olabilir: --yil 2015 2016)

Önce supabase/migrations/028_ballon_dor.sql çalıştırılmış olmalıdır. İstenildiği kadar tekrar çalıştırılabilir:
bir yıl yazılırken o yılın eski satırları silinir.
"""
import re
import sys
import time
from datetime import datetime
from html.parser import HTMLParser

import requests

from main import supabase

WIKI_API = "https://en.wikipedia.org/w/api.php"
SPARQL = "https://query.wikidata.org/sparql"
# Wikimedia, User-Agent başlığı olmayan istekleri reddeder (wikipedia.py ile aynı başlık)
HEADERS = {"User-Agent": "ScoutIQ-data-miner/1.0 (https://github.com/BalciAbdulkadir/ScoutIQ)"}
ILK_YIL = 1995
VERILMEYEN_YILLAR = {2020}   # Ballon d'Or 2020'de verilmedi
BASLIK_GRUBU = 50            # Wikipedia API'sinin tek istekte kabul ettiği en fazla sayfa


def istek_at(yontem, url, **kwargs):
    """Wikimedia isteği; bağlantı ya da hız sınırı hatasında birkaç kez tekrar dener. Başarısızsa None."""
    for deneme in range(1, 6):
        try:
            r = requests.request(yontem, url, headers=HEADERS, timeout=60, **kwargs)
            if r.status_code == 429:
                time.sleep(10 * deneme)
                continue
            return r
        except requests.RequestException as e:
            print(f"Bağlantı hatası ({e}). Tekrar deneniyor... ({deneme}/5)")
            time.sleep(5)
    return None


def sayfa_adlari(yil):
    """Bir yılın Wikipedia sayfa adı adayları. 2010-2015 arası ödül FIFA Ballon d'Or adıyla verildi."""
    if 2010 <= yil <= 2015:
        return [f"{yil} FIFA Ballon d'Or"]
    return [f"{yil} Ballon d'Or", f"{yil} Men's Ballon d'Or"]


class TabloOkuyucu(HTMLParser):
    """Sayfadaki wikitable'ları okur: her tablo için başlık (caption) ve satırlar.
    Hücrede metin ve bağlantılar ([sayfa adı, bağlantı metni]) tutulur; dipnotlar ([1], [notes 1]) metinden silinir."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.tablolar = []
        self._derinlik = 0          # iç içe tablolar
        self._tablo = None
        self._satir = None
        self._hucre = None
        self._baglanti = None       # açık <a>
        self._dipnot = 0            # açık <sup> sayısı
        self._baslikta = False

    def handle_starttag(self, etiket, nitelikler):
        n = dict(nitelikler)
        if etiket == "table":
            self._derinlik += 1
            if self._derinlik == 1 and "wikitable" in (n.get("class") or ""):
                self._tablo = {"baslik": "", "satirlar": []}
            return
        if self._tablo is None or self._derinlik != 1:
            return
        if etiket == "caption":
            self._baslikta = True
        elif etiket == "tr":
            self._satir = []
        elif etiket in ("td", "th") and self._satir is not None:
            self._hucre = {"metin": "", "baglantilar": []}
        elif etiket == "sup":
            self._dipnot += 1
        elif etiket == "a" and self._hucre is not None and not self._dipnot:
            href = (n.get("href") or "").split("#")[0]
            if href.startswith("/wiki/") and ":" not in href[6:]:
                self._baglanti = [requests.utils.unquote(href[6:]).replace("_", " "), ""]
                self._hucre["baglantilar"].append(self._baglanti)

    def handle_endtag(self, etiket):
        if etiket == "table":
            if self._derinlik == 1 and self._tablo is not None:
                self.tablolar.append(self._tablo)
                self._tablo = None
            self._derinlik -= 1
            return
        if self._tablo is None or self._derinlik != 1:
            return
        if etiket == "a":
            self._baglanti = None
        elif etiket == "sup":
            self._dipnot = max(0, self._dipnot - 1)
        elif etiket == "caption":
            self._baslikta = False
        elif etiket in ("td", "th") and self._hucre is not None:
            metin = re.sub(r"\[[^\]]*\]", " ", self._hucre["metin"])
            self._hucre["metin"] = " ".join(metin.split())
            self._satir.append(self._hucre)
            self._hucre = None
        elif etiket == "tr" and self._satir is not None:
            self._tablo["satirlar"].append(self._satir)
            self._satir = None

    def handle_data(self, veri):
        if self._baslikta and self._tablo is not None:
            self._tablo["baslik"] += veri
        elif self._hucre is not None and not self._dipnot:
            self._hucre["metin"] += veri
            if self._baglanti is not None:
                self._baglanti[1] += veri


def sayi(metin):
    """'1,055' -> 1055.0, '27.31%' -> 27.31; sayı yoksa None"""
    m = re.search(r"\d[\d,]*(?:\.\d+)?", metin or "")
    return float(m.group().replace(",", "")) if m else None


def siralama_tablolari(tablolar, fifa):
    """Erkekler sıralama tabloları: başlık satırında Rank ve Player olan, kadınlar tablosu olmayan tablolar.
    Normalde en uzun tek tablo alınır (sayfada Kopa ve Yashin ödüllerinin tabloları da vardır).
    FIFA Ballon d'Or sayfalarında (2010-2015) ilk 3 ayrı tabloda, kalan adaylar bir sonraki tabloda olduğu için ilk iki tablo alınır."""
    uygunlar = []
    for t in tablolar:
        if not t["satirlar"]:
            continue
        basliklar = [h["metin"].lower() for h in t["satirlar"][0]]
        if not any("rank" in b for b in basliklar) or not any("player" in b for b in basliklar):
            continue
        if re.search(r"women|féminin|feminin", t["baslik"], re.I):
            continue
        uygunlar.append((t, basliklar))
    if not uygunlar:
        return uygunlar
    if fifa:
        # Sayfa erkekler ödülüyle başlar: ilk tablo 1-3. sıra, ikincisi kalan adaylar. Sonrakiler kadınlar ve Puskás.
        return uygunlar[:2]
    return [max(uygunlar, key=lambda u: len(u[0]["satirlar"]))]


def yili_cek(yil):
    """Bir yılın sıralaması: [{sira, isim, wiki_baslik, puan, yuzde, ulke, kulup}] ya da sayfa yoksa None."""
    for sayfa in sayfa_adlari(yil):
        r = istek_at("GET", WIKI_API, params={"action": "parse", "page": sayfa, "prop": "text",
                                              "format": "json", "redirects": 1})
        if r is None or r.status_code != 200 or "error" in r.json():
            continue
        okuyucu = TabloOkuyucu()
        okuyucu.feed(r.json()["parse"]["text"]["*"])
        satirlar = []
        for tablo, basliklar in siralama_tablolari(okuyucu.tablolar, fifa=2010 <= yil <= 2015):
            satirlar += tablo_satirlari(tablo, basliklar)
        # Aynı oyuncu iki tabloda geçerse bir kez sayılır
        tekil = {}
        for s in sorted(satirlar, key=lambda s: s["sira"]):
            tekil.setdefault(s["isim"], s)
        if tekil:
            return list(tekil.values())
    return None


def tablo_satirlari(tablo, basliklar):
    """Sıralama tablosunun satırları: [{sira, isim, wiki_baslik, puan, yuzde, ulke, kulup}]"""
    if True:
        def sutun(*adlar):
            return next((i for i, b in enumerate(basliklar) if any(a in b for a in adlar)), None)

        i_sira, i_oyuncu = sutun("rank"), sutun("player")
        i_puan, i_yuzde = sutun("point"), sutun("percent", "%")
        i_ulke, i_kulup = sutun("nation", "country"), sutun("club")

        satirlar = []
        son_sira = None
        for satir in tablo["satirlar"][1:]:
            # Eşit sıralarda sıra hücresi birden fazla satırı kaplar (rowspan): o satırlarda sıra sütunu eksiktir
            eksik = len(satir) < len(basliklar)
            hucreler = ([None] if eksik and i_sira == 0 else []) + satir
            if len(hucreler) < len(basliklar):
                continue
            sira = sayi(hucreler[i_sira]["metin"]) if hucreler[i_sira] else son_sira
            if sira is None:
                continue
            son_sira = sira
            oyuncu = hucreler[i_oyuncu]
            if not oyuncu["metin"]:
                continue
            # Hücrede bayrak bağlantısı da olabilir: oyuncunun sayfası, metni en uzun bağlantıdır
            baglanti = max(oyuncu["baglantilar"], key=lambda b: len(b[1].strip()), default=None)
            satirlar.append({
                "sira": int(sira),
                "isim": oyuncu["metin"].strip("*† "),
                "wiki_baslik": baglanti[0] if baglanti and baglanti[1].strip() else None,
                "puan": sayi(hucreler[i_puan]["metin"]) if i_puan is not None else None,
                "yuzde": sayi(hucreler[i_yuzde]["metin"]) if i_yuzde is not None else None,
                "ulke": hucreler[i_ulke]["metin"] if i_ulke is not None else None,
                "kulup": hucreler[i_kulup]["metin"] if i_kulup is not None else None,
            })
        return satirlar


def wikidata_kimlikleri(basliklar):
    """Wikipedia sayfa adı -> Wikidata kimliği (yönlendirmeler izlenir)"""
    sonuc = {}
    basliklar = sorted({b for b in basliklar if b})
    for bas in range(0, len(basliklar), BASLIK_GRUBU):
        grup = basliklar[bas:bas + BASLIK_GRUBU]
        r = istek_at("GET", WIKI_API, params={"action": "query", "prop": "pageprops", "ppprop": "wikibase_item",
                                              "titles": "|".join(grup), "redirects": 1, "format": "json"})
        if r is None or r.status_code != 200:
            continue
        veri = r.json().get("query", {})
        # İstenen ad -> son sayfa adı (normalleştirme ve yönlendirme)
        hedef = {b: b for b in grup}
        for adim in ("normalized", "redirects"):
            for d in veri.get(adim, []):
                for b, h in hedef.items():
                    if h == d["from"]:
                        hedef[b] = d["to"]
        kimlik = {p["title"]: p.get("pageprops", {}).get("wikibase_item") for p in veri.get("pages", {}).values()}
        for b, h in hedef.items():
            if kimlik.get(h):
                sonuc[b] = kimlik[h]
    return sonuc


def transfermarkt_idleri(qidler):
    """Wikidata kimliği -> Transfermarkt oyuncu ID'si (P2446)"""
    sonuc = {}
    qidler = sorted(set(qidler))
    for bas in range(0, len(qidler), 200):
        degerler = " ".join(f"wd:{q}" for q in qidler[bas:bas + 200])
        sorgu = f"SELECT ?item ?tm WHERE {{ VALUES ?item {{ {degerler} }} ?item wdt:P2446 ?tm . }}"
        r = istek_at("POST", SPARQL, data={"query": sorgu, "format": "json"})
        if r is None or r.status_code != 200:
            continue
        for b in r.json()["results"]["bindings"]:
            sonuc[b["item"]["value"].rsplit("/", 1)[-1]] = b["tm"]["value"]
    return sonuc


def oyuncu_eslestir(qidler, tm_idleri):
    """Wikidata kimliği -> oyuncular.id: önce wikidata_id, olmazsa Transfermarkt ID ile"""
    sonuc = {}
    qid_liste = sorted(set(qidler))
    for bas in range(0, len(qid_liste), 200):
        d = supabase.table("oyuncular").select("id, wikidata_id").in_("wikidata_id", qid_liste[bas:bas + 200]).execute().data
        sonuc.update({o["wikidata_id"]: o["id"] for o in d})
    eksik = {tm_idleri[q]: q for q in qid_liste if q not in sonuc and q in tm_idleri}
    tm_liste = sorted(eksik)
    for bas in range(0, len(tm_liste), 200):
        d = supabase.table("oyuncular").select("id, transfermarkt_id").in_("transfermarkt_id", tm_liste[bas:bas + 200]).execute().data
        sonuc.update({eksik[o["transfermarkt_id"]]: o["id"] for o in d})
    return sonuc


def yillari_oku():
    if "--yil" not in sys.argv:
        return [y for y in range(ILK_YIL, datetime.now().year + 1) if y not in VERILMEYEN_YILLAR]
    yillar = []
    for a in sys.argv[sys.argv.index("--yil") + 1:]:
        if a.startswith("--"):
            break
        if not a.isdigit():
            print("Kullanım: python ballon_dor.py [--dene] [--yil YIL ...]")
            exit(1)
        yillar.append(int(a))
    return yillar


if __name__ == "__main__":
    dene = "--dene" in sys.argv
    yillar = yillari_oku()
    print(f"Ballon d'Or sıralamaları çekiliyor: {yillar[0]}-{yillar[-1]} ({len(yillar)} yıl)")

    siralamalar = {}
    for yil in yillar:
        satirlar = yili_cek(yil)
        if satirlar is None:
            # Bu yılın ödülü henüz verilmemiş olabilir
            print(f"   {yil}: sıralama tablosu bulunamadı, atlandı.")
            continue
        siralamalar[yil] = satirlar

    basliklar = [s["wiki_baslik"] for satirlar in siralamalar.values() for s in satirlar]
    qid = wikidata_kimlikleri(basliklar)
    tm = transfermarkt_idleri(qid.values())
    oyuncu = oyuncu_eslestir(qid.values(), tm)

    toplam = eslesen = 0
    for yil, satirlar in siralamalar.items():
        for s in satirlar:
            s["wikidata_id"] = qid.get(s["wiki_baslik"])
            s["oyuncu_id"] = oyuncu.get(s["wikidata_id"])
        e = sum(1 for s in satirlar if s["oyuncu_id"])
        toplam += len(satirlar)
        eslesen += e
        ilk = ", ".join(f"{s['sira']}. {s['isim']}" for s in satirlar[:3])
        olcu = "yüzde" if satirlar[0]["yuzde"] is not None and satirlar[0]["puan"] is None else "puan"
        print(f"   {yil}: {len(satirlar)} aday ({olcu}), {e} eşleşti | {ilk}")
        eslesmeyen = [s["isim"] for s in satirlar if not s["oyuncu_id"]]
        if eslesmeyen:
            print(f"         eşleşmeyen: {', '.join(eslesmeyen)}")

    print(f"\nToplam {toplam} satır, {eslesen} oyuncu veritabanıyla eşleşti.")
    if dene:
        print("Deneme: veritabanına yazılmadı.")
        exit(0)

    for yil, satirlar in siralamalar.items():
        supabase.table("ballon_dor_siralamalari").delete().eq("yil", yil).execute()
        supabase.table("ballon_dor_siralamalari").insert([
            {"yil": yil, "sira": s["sira"], "oyuncu_isim": s["isim"], "oyuncu_id": s["oyuncu_id"],
             "wikidata_id": s["wikidata_id"], "puan": s["puan"], "yuzde": s["yuzde"],
             "ulke": s["ulke"], "kulup": s["kulup"]}
            for s in satirlar
        ]).execute()
    print("Sıralamalar yazıldı.")
