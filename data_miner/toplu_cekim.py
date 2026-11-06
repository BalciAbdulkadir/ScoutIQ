"""
Önem kriterleri için gereken tüm veri çekimlerini sırayla çalıştırır. Her adımın çıktısı terminalde canlı görünür.

Kullanım:
    python toplu_cekim.py           # tüm adımlar
    python toplu_cekim.py 3         # 3. adımdan başla (önceki adımlar bittiyse)

Önce supabase/migrations/015_onem_verileri.sql çalıştırılmış ve Transfermarkt API (Docker) açık olmalıdır.
Adımların hepsi kaldığı yerden devam eder: Ctrl+C ile durdurup aynı komutla (ya da adım numarasıyla) tekrar başlatmak güvenlidir.
Bir adımda bazı oyuncular hata alırsa ('!!' satırları) sonraki adıma geçilir; o oyuncular adım tekrar çalıştırılınca
yeniden denenir. Bir adım çökerse çekim durur ve hangi adımdan devam edileceği yazılır.

Sıra önemlidir: milli kadrolardan eklenen yeni oyuncuların sonraki adımlarda transferleri, milli takım kariyerleri
ve önem verileri de çekilir.
"""
import subprocess
import sys
import time

ADIMLAR = [
    ("milli_kadrolar.py", "Bilinen milli takımların kadrolarından eksik oyuncular"),
    ("transferler.py", "Yeni oyuncuların transferleri ve toplam bonservis"),
    ("milli_takimlar.py", "Yeni oyuncuların A milli takım kariyeri"),
    ("onem_verileri.py", "Tüm oyuncuların istatistik, piyasa değeri ve başarıları"),
    ("logolar.py", "Yeni kulüplerin logoları"),
]


def baslangic_adimi():
    if len(sys.argv) == 1:
        return 1
    try:
        adim = int(sys.argv[1])
        if 1 <= adim <= len(ADIMLAR):
            return adim
    except ValueError:
        pass
    print(f"Kullanım: python toplu_cekim.py [adım 1-{len(ADIMLAR)}]")
    exit(1)


if __name__ == "__main__":
    ilk = baslangic_adimi()
    baslangic = time.time()

    for no, (betik, aciklama) in enumerate(ADIMLAR, start=1):
        if no < ilk:
            continue
        print(f"\n{'=' * 70}\nADIM {no}/{len(ADIMLAR)}: {aciklama} ({betik})\n{'=' * 70}", flush=True)
        adim_baslangic = time.time()
        try:
            sonuc = subprocess.run([sys.executable, "-u", betik])
        except KeyboardInterrupt:
            print(f"\nDurduruldu. Devam etmek için: python toplu_cekim.py {no}")
            exit(1)

        sure_dk = (time.time() - adim_baslangic) / 60
        if sonuc.returncode != 0:
            print(f"\nAdım {no} hata koduyla bitti ({sure_dk:.0f} dk). Devam etmek için: python toplu_cekim.py {no}")
            exit(1)
        print(f"\nAdım {no} bitti ({sure_dk:.0f} dk).", flush=True)

    print(f"\nTüm adımlar bitti. Toplam süre: {(time.time() - baslangic) / 60:.0f} dk.")
