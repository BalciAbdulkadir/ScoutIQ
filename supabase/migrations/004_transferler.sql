-- 004: Bonservis oyunu için transfer geçmişi
-- Supabase SQL Editor'da tek seferde çalıştırılır. Hata olursa hiçbir değişiklik uygulanmaz.
-- Bu dosyadan sonra veri data_miner/transferler.py ile çekilir.

begin;

-- Oyuncuların tüm transferleri (kiralık, bedelsiz, kiralık dönüşü dahil).
-- Kulüpler isim ve Transfermarkt ID'si olarak tutulur: transferlerin çoğu bizim
-- kulupler tablomuzda olmayan kulüplerden ya da kulüplere yapılır.
create table public.transferler (
    id uuid primary key default gen_random_uuid(),
    transfermarkt_id varchar not null unique,
    oyuncu_id uuid not null references public.oyuncular (id) on delete cascade,
    eski_kulup_tm_id varchar,
    eski_kulup_isim text,
    yeni_kulup_tm_id varchar,
    yeni_kulup_isim text,
    tarih date,
    sezon varchar,          -- Transfermarkt biçiminde, ör. '18/19'
    tip varchar not null,   -- transfer, loan, freeTransfer, endOfLoan, internal ...
    bedel bigint,           -- Euro. null: bedel yok ya da bilinmiyor
    piyasa_degeri bigint    -- Transfer anındaki piyasa değeri, Euro
);

create index transferler_oyuncu_id_idx on public.transferler (oyuncu_id);

-- Uygulamaya kapalı (politika yok): bedeller Bonservis oyununun cevabıdır,
-- kariyer_gecmisi gibi kontrol sunucuda yapılacak.
alter table public.transferler enable row level security;

-- Çekim saatler sürdüğü için yarıda kalırsa kaldığı yerden devam edilir:
-- transferleri çekilmiş oyuncular bu tarihle işaretlenir.
alter table public.oyuncular add column transfer_cekim_tarihi timestamptz;

commit;
