-- 013: Önem kriterleri için ham veri (genel tanınmışlık ve kulüp önemi)
-- Supabase SQL Editor'da tek seferde çalıştırılır. Hata olursa hiçbir değişiklik uygulanmaz.
-- Bu dosyadan sonra veri data_miner/onem_verileri.py ile çekilir (ya da hepsi birden: python toplu_cekim.py).
--
-- Tablolar ham veriyi özet olarak tutar; tanınmışlık ve kulüp önemi puanları kriterler kesinleşince bunlardan hesaplanacak.
-- Kulüpler Transfermarkt ID'si ile tutulur: oyuncuların kariyerindeki kulüplerin çoğu kulupler tablomuzda yok.

begin;

-- Oyuncunun kariyerindeki en yüksek ve bugünkü piyasa değeri (Euro)
alter table public.oyuncular
    add column zirve_piyasa_degeri bigint,
    add column guncel_piyasa_degeri bigint,
    -- İstatistik, piyasa değeri ve başarılar çekilmiş oyuncular bu tarihle işaretlenir (çekim yarıda kalırsa devam edilir)
    add column onem_verisi_cekim_tarihi timestamptz;

-- Oyuncunun bir kulüpteki toplam performansı (tüm turnuvalar, tüm sezonlar).
-- Altyapı takımları da Transfermarkt'ta ayrı kulüp olduğu için ayrı satırdır. Milli maçlar burada yok, milli_takim_kariyeri'nde.
create table public.oyuncu_kulup_istatistikleri (
    oyuncu_id uuid not null references public.oyuncular (id) on delete cascade,
    kulup_tm_id varchar not null,
    mac integer not null default 0,
    gol integer not null default 0,
    asist integer not null default 0,
    dakika integer not null default 0,
    sezon_sayisi integer not null default 0,
    ilk_sezon integer,                 -- 2015 = 2015/16
    son_sezon integer,
    zirve_piyasa_degeri bigint,        -- O kulüpteyken ulaştığı en yüksek piyasa değeri (Euro)
    primary key (oyuncu_id, kulup_tm_id)
);

create index oyuncu_kulup_istatistikleri_kulup_idx on public.oyuncu_kulup_istatistikleri (kulup_tm_id);

-- Oyuncunun kazandığı başlıklar ("UEFA Champions League winner", "World Cup winner", "Ballon d'Or" ...).
-- Kulüple kazanılanlar kulüp başına ayrı satırdır; kulübe bağlı olmayanlarda kulup_tm_id boş metindir.
create table public.oyuncu_basarilari (
    oyuncu_id uuid not null references public.oyuncular (id) on delete cascade,
    baslik text not null,
    kulup_tm_id varchar not null default '',
    adet integer not null,
    primary key (oyuncu_id, baslik, kulup_tm_id)
);

-- Uygulamaya kapalı (politika yok): sadece backend ve veri betikleri kullanır
alter table public.oyuncu_kulup_istatistikleri enable row level security;
alter table public.oyuncu_basarilari enable row level security;

commit;
