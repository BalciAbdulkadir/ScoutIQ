-- 009: Oyuncuların A milli takım kariyeri
-- Supabase SQL Editor'da tek seferde çalıştırılır. Hata olursa hiçbir değişiklik uygulanmaz.
-- Bu dosyadan sonra veri data_miner/milli_takimlar.py ile çekilir.

begin;

-- Oyuncunun forma giydiği A milli takımlar (alt yaş ve olimpiyat takımları alınmaz).
-- Bir oyuncu birden fazla A milli takımda oynamış olabilir, ör. önce İrlanda sonra İngiltere.
-- Milli takımlar isim ve Transfermarkt ID'si olarak tutulur.
create table public.milli_takim_kariyeri (
    id uuid primary key default gen_random_uuid(),
    oyuncu_id uuid not null references public.oyuncular (id) on delete cascade,
    milli_takim_tm_id varchar not null,
    milli_takim_isim text not null,
    mac_sayisi integer not null,
    gol integer not null default 0,
    unique (oyuncu_id, milli_takim_tm_id)
);

-- Uygulamaya kapalı (politika yok): hangi oyunda kullanılacağı henüz belli değil,
-- kariyer_gecmisi gibi cevap verisi olabilir.
alter table public.milli_takim_kariyeri enable row level security;

-- Çekim saatler sürdüğü için yarıda kalırsa kaldığı yerden devam edilir:
-- milli takım kariyeri çekilmiş oyuncular bu tarihle işaretlenir.
alter table public.oyuncular add column milli_takim_cekim_tarihi timestamptz;

commit;
