-- 010: Efsane oyuncular için eski kulüpler
-- Supabase SQL Editor'da çalıştırılır.
-- Bu dosyadan sonra efsaneler data_miner/efsaneler.py ile çekilir.

-- Efsanelerin oynadığı ve 6 ana ligde olmayan kulüpler (Santos, Boca Juniors, Ajax ...) ligsiz eklenir.
-- Kesişim bu kulüpleri soru olarak seçmez, ama kariyer_gecmisi'nde yer aldıkları için
-- cevap kontrolü efsanelerin tüm kulüplerini görür.
alter table public.kulupler alter column lig drop not null;
