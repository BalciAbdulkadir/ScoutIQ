-- 032: Oyuncuların doğum tarihleri
-- Supabase SQL Editor'da tek seferde çalıştırılır. Hata olursa hiçbir değişiklik uygulanmaz.
--
-- Doğum tarihi Transfermarkt API'nin oyuncu profilinden çekilir (data_miner/dogum_tarihleri.py).
-- Aynı isimli oyuncuları ayırt etmek (öneri listesinde doğum yılı) ve yaşa bağlı sorular için kullanılır.

begin;

alter table public.oyuncular add column dogum_tarihi date;

-- Doğum tarihi çekilen oyuncular işaretlenir: çekim yarıda kalırsa kaldığı yerden devam eder.
-- Profilinde doğum tarihi olmayan oyuncu da işaretlenir (dogum_tarihi boş kalır), tekrar denenmez.
alter table public.oyuncular add column dogum_tarihi_cekim_tarihi timestamptz;

commit;
 