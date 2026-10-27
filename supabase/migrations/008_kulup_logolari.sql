-- 008: Kulüp logoları
-- Supabase SQL Editor'da çalıştırılır.
-- Bu dosyadan sonra mevcut kulüplerin logoları data_miner/logolar.py ile doldurulur.

-- Logolar kopyalanmaz, Transfermarkt'taki adresleri tutulur. null: logo yok.
alter table public.kulupler add column logo_url text;
