-- 028: Ballon d'Or sıralamaları
-- Supabase SQL Editor'da tek seferde çalıştırılır. Hata olursa hiçbir değişiklik uygulanmaz.
--
-- Her yılın Ballon d'Or aday sıralaması (1995'ten bugüne; 2020'de ödül verilmedi). Kaynak İngilizce Wikipedia'dır,
-- çünkü Transfermarkt API'si sıralamayı vermez (data_miner/ballon_dor.py). Sadece kazananlar ayrıca oyuncu_basarilari
-- tablosunda "Winner Ballon d'Or" başlığıyla vardır.
-- 2010-2015 arası ödül FIFA Ballon d'Or adıyla verildi; bu yıllarda puan yerine oy yüzdesi vardır.
-- oyuncu_id: oyuncular tablosundaki karşılığı (Wikidata kimliği ya da Transfermarkt ID'si ile eşleştirilir);
-- veritabanında olmayan oyuncularda boştur.

begin;

create table public.ballon_dor_siralamalari (
    id bigint generated always as identity primary key,
    yil smallint not null,                     -- Ödülün yılı (sayfa adındaki yıl)
    sira smallint not null,                    -- Eşit puanlı oyuncuların sırası aynıdır
    oyuncu_isim text not null,                 -- Wikipedia'daki isim
    oyuncu_id uuid references public.oyuncular (id) on delete set null,
    wikidata_id varchar,
    puan numeric,                              -- 2010-2015 dışında
    yuzde numeric,                             -- Sadece 2010-2015 (oy yüzdesi)
    ulke text,                                 -- O yılki milli takımı
    kulup text,                                -- O yılki kulübü
    unique (yil, oyuncu_isim)
);

create index ballon_dor_siralamalari_oyuncu_idx on public.ballon_dor_siralamalari (oyuncu_id);

-- Uygulamaya kapalı (politika yok): sadece backend ve veri betikleri kullanır
alter table public.ballon_dor_siralamalari enable row level security;

commit;
