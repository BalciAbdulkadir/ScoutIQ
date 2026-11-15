-- 025: Gol krallıkları
-- Supabase SQL Editor'da tek seferde çalıştırılır. Hata olursa hiçbir değişiklik uygulanmaz.
--
-- Oyuncuların gol krallıklarını tutan tablo. Veri Transfermarkt'ın başarılar sayfasındaki "Top goal scorer"
-- başlığından gelir (data_miner/gol_kralliklari.py). Her satır bir gol krallığıdır: oyuncu, sezon, müsabaka ve
-- o sezon forma giydiği kulüp ya da milli takım. Gol sayısı kaynakta yoktur.
-- Bütün müsabakalar yazılır (ligler, kupalar, milli turnuvalar, alt ligler); oyunlar istediğini müsabaka koduyla seçer.

begin;

create table public.gol_kralliklari (
    oyuncu_id uuid not null references public.oyuncular (id) on delete cascade,
    sezon integer not null,                    -- 2015 = 2015/16; turnuvalarda turnuvanın sezonu
    musabaka_tm_id varchar not null,           -- Transfermarkt müsabaka kodu: GB1, TR1, CL ...
    musabaka_isim text,
    kulup_tm_id varchar not null default '',   -- Kulüp ya da milli takımın Transfermarkt ID'si; bilinmiyorsa boş
    kulup_isim text,
    primary key (oyuncu_id, sezon, musabaka_tm_id, kulup_tm_id)
);

create index gol_kralliklari_musabaka_idx on public.gol_kralliklari (musabaka_tm_id, sezon);

-- Uygulamaya kapalı (politika yok): sadece backend ve veri betikleri kullanır
alter table public.gol_kralliklari enable row level security;

-- Gol krallığı verisi çekilen oyuncular işaretlenir: çekim yarıda kalırsa kaldığı yerden devam eder
alter table public.oyuncular add column gol_kralligi_cekim_tarihi timestamptz;

commit;
