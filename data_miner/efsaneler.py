"""
Efsane oyuncuları ve kulüp kariyerlerini Transfermarkt API'den çekip Supabase'e yazar.
Mevcut veri 2015/2016'dan sonraki kadrolardan geldiği için eski oyuncular ve eski kulüp dönemleri yoktur.

Kullanım:
    python efsaneler.py

Önce supabase/migrations/010_efsaneler.sql çalıştırılmış olmalıdır.
- Veritabanında olmayan efsaneler oyuncular tablosuna eklenir (isim, uyruk, fotoğraf).
  Zaten olanların (Iniesta, Buffon ...) oyuncu kaydına dokunulmaz, sadece eski kulüp dönemleri eklenir.
- Kulüp dönemleri transfer geçmişinden çıkarılır. Altyapı, B ve U takımları alınmaz.
  İlk kulübe geliş transferi kayıtlı değilse dönem kulüpten ayrıldığı sezondan başlar: yıllar yaklaşıktır,
  Kesişim için önemli olan oyuncunun kulüpte oynamış olmasıdır.
- 6 ana ligde olmayan kulüpler ligsiz eklenir, Kesişim'de soru olarak çıkmazlar.
  Yeni kulüplerin logoları için sonra: python logolar.py
- Milli takım kariyerleri için sonra: python milli_takimlar.py (eklenen efsaneleri de çeker)
- Transferler (bonservis bedelleri) çekilmez, Bonservis oyunu etkilenmez.
Tekrar çalıştırmak güvenlidir: kayıtlar transfermarkt_id üzerinden eşleşir, kariyer yılları birleştirilir.
"""
import re
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import date

from main import api_istek_at, foto_adresi, supabase

IS_SAYISI = 4

# Transfermarkt ID -> isim (isim sadece okunabilirlik için, veritabanına Transfermarkt'taki isim yazılır)
EFSANELER = {
    "17121": "Pelé", "8024": "Diego Maradona", "8021": "Johan Cruyff", "72347": "Franz Beckenbauer",
    "135778": "Alfredo Di Stéfano", "88994": "Michel Platini", "103092": "Ferenc Puskás", "3111": "Zinedine Zidane",
    "3140": "Ronaldo Nazário", "74471": "Marco van Basten", "174987": "Lev Yashin", "174986": "George Best",
    "151263": "Garrincha", "5803": "Paolo Maldini", "174874": "Bobby Charlton", "42049": "Franco Baresi",
    "35604": "Gerd Müller", "89230": "Eusébio", "117619": "Zico", "7607": "Xavi Hernández",
    "7600": "Andrés Iniesta", "3373": "Ronaldinho", "1527": "Lothar Matthäus", "4153": "Roberto Baggio",
    "31909": "Toni Kroos", "17259": "Manuel Neuer", "101045": "Ruud Gullit", "7942": "Romário",
    "5023": "Gianluigi Buffon", "196086": "Bobby Moore", "72343": "Karl-Heinz Rummenigge", "8023": "Michael Laudrup",
    "7518": "Roberto Carlos", "5937": "Cafu", "3207": "Thierry Henry", "183779": "Giuseppe Meazza",
    "105334": "Nándor Hidegkuti", "212779": "Stanley Matthews", "3979": "Iker Casillas", "137264": "Didi",
    "172315": "Luis Suárez (İspanyol)", "170730": "Raymond Kopa", "117633": "Sócrates", "170723": "Paco Gento",
    "89229": "Dino Zoff", "3372": "Rivaldo", "145347": "Gianni Rivera", "136482": "Sándor Kocsis",
    "116740": "Gaetano Scirea", "3465": "Peter Schmeichel", "8542": "George Weah", "116735": "Daniel Passarella",
    "229662": "Carlos Alberto", "135269": "Kenny Dalglish", "70667": "Frank Rijkaard", "7938": "Hristo Stoichkov",
    "135643": "Johan Neeskens", "3187": "Dennis Bergkamp", "4257": "Samuel Eto'o", "5775": "Fabio Cannavaro",
    "3446": "Luís Figo", "291722": "Valentino Mazzola", "200627": "Gordon Banks", "137265": "Nílton Santos",
    "85458": "Kevin Keegan", "3455": "Zlatan Ibrahimović", "5817": "Andrea Pirlo", "50816": "Omar Sívori",
    "10201": "Rivelino", "3406": "Ryan Giggs", "7939": "Gheorghe Hagi", "3924": "Didier Drogba",
    "4360": "Arjen Robben", "145193": "Giacinto Facchetti", "13766": "Paul Breitner", "206": "Oliver Kahn",
    "84528": "Hugo Sánchez", "5959": "Gabriel Batistuta", "7349": "Raúl González", "58358": "Thomas Müller",
    "2219": "Philipp Lahm", "65230": "Sergio Busquets", "14132": "Pepe", "77010": "Matthias Sammer",
    "135621": "Ruud Krol", "1161": "Javier Zanetti", "45320": "Ángel Di María", "151245": "Just Fontaine",
    "22068": "Franck Ribéry", "4168": "Clarence Seedorf", "4171": "Alessandro Nesta", "137269": "Djalma Santos",
    "3516": "Edwin van der Sar", "72381": "Karl-Heinz Schnellinger", "145743": "Ian Rush", "88989": "Roger Milla",
    "6657": "Abedi Pelé", "7476": "Xabi Alonso", "4289": "Alessandro Del Piero", "3332": "Wayne Rooney",
}

# Kariyere sayılmayan takımlar: "Barcelona U19", "Bayern Munich II", "Real Madrid C (- 2015)", "Jong Ajax" ...
ALT_TAKIM = re.compile(
    r"\bU\d{2}\b|\bUnder \d{2}\b|\bSub-\d{2}\b|\bII\b|\s[BC](\s\(|$)|Youth|Jugend|Yth\.?$|Castilla|Atl[eè]tic$|Primavera|Reserves?\b|Academy|^Jong |Amateur|Juvenil",
    re.IGNORECASE,
)


def gercek_kulup(kulup):
    """Emekli, Kulüpsüz, Kariyer arası gibi sahte kulüplerin ülkesi yoktur (countryId 0)"""
    return bool(
        kulup and kulup.get("id") and kulup.get("name")
        and kulup.get("countryId") not in (None, "0")
        and not ALT_TAKIM.search(kulup["name"])
    )


# Transfer tarihinden sezon: yaz döneminde gelen oyuncu o sezon oynar, yaz döneminde giden bir önceki sezon oynamıştır
def gelis_sezonu(tarih):
    return tarih.year if tarih.month >= 6 else tarih.year - 1


def ayrilis_sezonu(tarih):
    return tarih.year if tarih.month >= 10 else tarih.year - 1


def kulup_donemleri(transferler):
    """Transfer geçmişinden kulüp dönemleri: kulüp tm_id -> (isim, ilk sezon, son sezon)"""
    sezonlar = {}
    isimler = {}
    for t in transferler:
        if not t.get("date") or t.get("upcoming"):
            continue
        tarih = date.fromisoformat(t["date"])
        for kulup, sezon in ((t.get("clubTo"), gelis_sezonu(tarih)), (t.get("clubFrom"), ayrilis_sezonu(tarih))):
            if gercek_kulup(kulup):
                sezonlar.setdefault(kulup["id"], []).append(sezon)
                isimler[kulup["id"]] = kulup["name"]
    return {tm_id: (isimler[tm_id], min(s), max(s)) for tm_id, s in sezonlar.items()}


def kulupleri_oku():
    """Veritabanındaki kulüpler: transfermarkt_id -> id (207 kulüp, sayfalamaya gerek yok)"""
    return {k["transfermarkt_id"]: k["id"] for k in supabase.table("kulupler").select("id, transfermarkt_id").execute().data}


def efsane_getir(tm_id):
    """API istekleri iş parçacıklarında atılır; veritabanına yazma ana akışta yapılır."""
    profil = api_istek_at(f"/players/{tm_id}/profile")
    transferler = api_istek_at(f"/players/{tm_id}/transfers")
    time.sleep(0.3)  # Rate limit'e takılmamak için nefes aldırıyoruz
    return tm_id, profil, transferler


def oyuncu_id_bul_ya_da_ekle(tm_id, profil):
    """Oyuncu veritabanındaysa id'sini döndürür, değilse ekler. (id, yeni mi) döndürür."""
    mevcut = supabase.table("oyuncular").select("id").eq("transfermarkt_id", tm_id).execute().data
    if mevcut:
        return mevcut[0]["id"], False

    uyruklar = profil.get("citizenship") or []
    res = supabase.table("oyuncular").insert({
        "transfermarkt_id": tm_id,
        "isim": profil["name"],
        "uyruk": uyruklar[0] if uyruklar else None,
        "foto_url": foto_adresi(profil),
    }).execute()
    return res.data[0]["id"], True


def kulup_id_bul_ya_da_ekle(kulupler, tm_id, isim):
    """Kulüp veritabanındaysa id'sini döndürür, değilse ligsiz ekler. (id, yeni mi) döndürür."""
    if tm_id in kulupler:
        return kulupler[tm_id], False
    res = supabase.table("kulupler").insert({"transfermarkt_id": tm_id, "isim": isim, "lig": None}).execute()
    kulupler[tm_id] = res.data[0]["id"]
    return kulupler[tm_id], True


def kariyer_ekle(kulup_id, oyuncu_id, ilk, son):
    # Oyuncu-kulüp çifti zaten varsa (ör. 2015 sonrası kadrolardan) yıl aralığı genişletilir
    for sezon in {ilk, son}:
        supabase.rpc("kariyer_sezon_ekle", {
            "p_kulup_id": kulup_id, "p_sezon": sezon, "p_oyuncu_ids": [oyuncu_id],
        }).execute()


if __name__ == "__main__":
    kulupler = kulupleri_oku()
    toplam = len(EFSANELER)
    print(f"Efsane çekimi başlatılıyor. Efsane: {toplam}, veritabanındaki kulüp: {len(kulupler)}")

    hata_sayisi = 0
    yeni_oyuncu_sayisi = 0
    yeni_kulupler = []

    with ThreadPoolExecutor(max_workers=IS_SAYISI) as havuz:
        for sira, (tm_id, profil, transferler) in enumerate(havuz.map(efsane_getir, EFSANELER), start=1):
            isim = EFSANELER[tm_id]
            if not profil or not profil.get("name") or transferler is None or "transfers" not in transferler:
                print(f"!! [{sira}/{toplam}] {isim}: profil ya da transferler alınamadı.")
                hata_sayisi += 1
                continue

            try:
                oyuncu_id, yeni = oyuncu_id_bul_ya_da_ekle(tm_id, profil)
                donemler = kulup_donemleri(transferler["transfers"])
                for kulup_tm_id, (kulup_isim, ilk, son) in sorted(donemler.items(), key=lambda d: d[1][1]):
                    kulup_id, yeni_kulup = kulup_id_bul_ya_da_ekle(kulupler, kulup_tm_id, kulup_isim)
                    if yeni_kulup:
                        yeni_kulupler.append(kulup_isim)
                    kariyer_ekle(kulup_id, oyuncu_id, ilk, son)
            except Exception as e:
                print(f"!! [{sira}/{toplam}] {isim} kaydedilemedi: {e}")
                hata_sayisi += 1
                continue

            yeni_oyuncu_sayisi += yeni
            ozet = ", ".join(f"{k} ({ilk}-{son})" for k, ilk, son in sorted(donemler.values(), key=lambda d: d[1]))
            print(f">> [{sira}/{toplam}] {profil['name']}{' (yeni)' if yeni else ''}: {ozet or 'kulüp dönemi bulunamadı'}")

    print(f"\n{yeni_oyuncu_sayisi} yeni oyuncu, {len(yeni_kulupler)} yeni kulüp eklendi.")
    if yeni_kulupler:
        print("Yeni kulüpler: " + ", ".join(sorted(yeni_kulupler)))
    if hata_sayisi:
        print(f"{hata_sayisi} efsanede hata oluştu. '!!' ile başlayan satırlara bakın; tekrar çalıştırmak güvenlidir.")
    else:
        print("İşlem hatasız tamamlandı.")
