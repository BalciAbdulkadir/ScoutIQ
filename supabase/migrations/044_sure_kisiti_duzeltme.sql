-- 044: 40 saniyelik oyunlar açılmıyor; süre kısıtları 40 saniyeyi de kabul eder
-- Supabase SQL Editor'da tek seferde çalıştırılır. Hata olursa hiçbir değişiklik uygulanmaz.
-- 043_sure_40_bingo_ceza.sql'den sonra çalıştırılmalıdır. Tekrar çalıştırılabilir.
-- Eski uygulama sürümünü bozmaz: 30 saniye eski kayıtlar ve eski sürüm için kabul edilmeye devam eder.
--
-- KURAL (bundan sonrası için): süre seçeneği değişirse şu dört yer BİRLİKTE değişir:
--   1) oyun_ac'taki süre kontrolü (son hâli 043_sure_40_bingo_ceza.sql)
--   2) puan_hesapla'daki süre çarpanı (son hâli 043_sure_40_bingo_ceza.sql)
--   3) kullanici_oyun_gecmisi_sure_saniye_check (018_oyun_devam.sql, son hâli bu dosya)
--   4) izgara_sureleri_sure_saniye_check (013_izgara_sure.sql, son hâli bu dosya)
-- Aynı kural "güncellemelerde dikkat edilecekler.md"de de yazar.
--
-- Sorun: 043 oyun_ac'ın 40 saniyeyi kabul etmesini sağladı ama tablolardaki kısıtlara dokunmadı. İki kısıt hâlâ
-- sadece 30, 60 ve 90 saniyeye izin veriyordu. Uygulama 40 saniye gönderince oyun_ac kabul ediyor, kayıt eklenirken
-- kısıt hata veriyordu (Postgres logu: 23514 ... violates check constraint ...sure_saniye_check). Uygulama bunu
-- "Bağlantı sorunu" olarak gösteriyordu. Uygulamanın testleri yakalamadı, çünkü sahte depo veritabanı kısıtlarını
-- bilmez.
--
-- Kontrol (çalıştırdıktan sonra; iki satır, ikisinde de true):
--   select conname, pg_get_constraintdef(oid) like '%40%' as kirk_var
--   from pg_constraint
--   where conname in ('kullanici_oyun_gecmisi_sure_saniye_check', 'izgara_sureleri_sure_saniye_check');

begin;

-- 1) Kesişim, Bonservis ve Bingo'nun süresi (018). Süresiz oyunda sure_saniye null'dır, kısıt null'ı kabul eder.
alter table public.kullanici_oyun_gecmisi
    drop constraint if exists kullanici_oyun_gecmisi_sure_saniye_check;
alter table public.kullanici_oyun_gecmisi
    add constraint kullanici_oyun_gecmisi_sure_saniye_check check (sure_saniye in (30, 40, 60, 90));

-- 2) Izgara'nın süresi (013). Süresiz Izgara'da satır açılmaz.
alter table public.izgara_sureleri
    drop constraint if exists izgara_sureleri_sure_saniye_check;
alter table public.izgara_sureleri
    add constraint izgara_sureleri_sure_saniye_check check (sure_saniye in (30, 40, 60, 90));

commit;
