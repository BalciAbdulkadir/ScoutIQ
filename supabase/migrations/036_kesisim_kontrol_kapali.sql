-- 036: Kesişim cevap kontrolü ve Bonservis bedelleri uygulamaya kapatılır
-- Supabase SQL Editor'da tek seferde çalıştırılır. Hata olursa hiçbir değişiklik uygulanmaz.
-- 034_skor_sunucuda.sql'den sonra çalıştırılmalıdır (kesisim_cevap ve bonservis_tahmin orada eklendi).
-- Tekrar çalıştırılabilir: ikinci çalıştırma aynı sonucu verir.
--
-- 1) Kesişim
-- Sorun: kesisim_cevap_kontrol'ü giriş yapmış her kullanıcı çalıştırabiliyordu (izin 003'te verildi, 019'da yine
-- verildi). Fonksiyon açık kayıt, süre ve sıra kontrolü yapmaz. Doğrudan veritabanına istek atan biri oyunu hiç
-- başlatmadan, sınırsız sayıda oyuncu deneyip her sorunun cevabını bulabiliyor, sonra gerçek oyunda tam puan alabiliyordu
-- (28 Ekim 2026 güvenlik raporu, madde 3).
-- Düzeltme: çalıştırma izni authenticated rolünden alınır (public ve anon'da zaten yoktu). Fonksiyon silinmez:
-- kesisim_cevap'ın içinden çağrılan bir iç yardımcı olarak kalır. kesisim_cevap security definer olduğu için fonksiyonu
-- sahibinin yetkisiyle çağırır, izin kalkınca da çalışır. Uygulama kesisim_cevap_kontrol'ü doğrudan çağırmaz
-- (mobile/lib/services/oyun_deposu.dart sadece kesisim_cevap'ı çağırır).
--
-- 2) Bonservis
-- Sorun: Bonservis sorusu sağdaki oyuncunun id'sini taşır (oyuncu_b_id) ve oyuncular tablosu giriş yapmış herkese
-- bütün kolonlarıyla açıktır. Doğrudan istek atan biri oyuncular.toplam_bonservis'ten sağdaki oyuncunun bedelini, yani
-- cevabı okuyabiliyordu. 034'te bedelin soruyla gönderilmemesi bu yüzden yetmiyordu.
-- Düzeltme: authenticated rolü oyuncular'da toplam_bonservis dışındaki bütün kolonları okumaya devam eder.
-- Tablo tamamen kapatılamaz: oyuncu_ara (öneri listesi) tabloyu kullanıcının yetkisiyle okur. oyuncu_ara
-- toplam_bonservis'e bakmaz. Bedele bakan fonksiyonlar (bonservis_tahmin, bonservis_bedeli) security definer'dır,
-- etkilenmez. Backend secret key kullanır, etkilenmez. Uygulama oyuncular tablosunu doğrudan okumaz.
-- DİKKAT: Bundan sonra oyuncular'a eklenen yeni bir kolonu uygulama okuyacaksa, o dosyada
-- "grant select (yeni_kolon) on public.oyuncular to authenticated;" yazılmalıdır.
--
-- Kontrol (çalıştırdıktan sonra, SQL Editor'da):
--   select has_function_privilege('authenticated', 'public.kesisim_cevap_kontrol(uuid, integer, uuid)', 'execute');
--     -> false olmalı
--   select has_function_privilege('authenticated', 'public.kesisim_cevap(uuid, integer, uuid)', 'execute');
--     -> true olmalı
--   select has_column_privilege('authenticated', 'public.oyuncular', 'toplam_bonservis', 'select');
--     -> false olmalı
--   select has_column_privilege('authenticated', 'public.oyuncular', 'isim', 'select');
--     -> true olmalı

begin;

-- 1) Kesişim cevap kontrolü sadece kesisim_cevap'ın içinden çağrılır
revoke execute on function public.kesisim_cevap_kontrol(uuid, integer, uuid) from public, anon, authenticated;

-- 2) oyuncular.toplam_bonservis uygulamaya kapalı. Kolon bazında izin, tablo bazında izin varken geri alınamaz:
--    önce tablo izni alınır, sonra toplam_bonservis dışındaki kolonlara izin verilir.
do $$
declare
    v_kolonlar text;
begin
    select string_agg(quote_ident(column_name), ', ' order by ordinal_position) into v_kolonlar
    from information_schema.columns
    where table_schema = 'public' and table_name = 'oyuncular' and column_name <> 'toplam_bonservis';

    revoke select on public.oyuncular from authenticated;
    revoke select (toplam_bonservis) on public.oyuncular from authenticated;
    execute format('grant select (%s) on public.oyuncular to authenticated', v_kolonlar);
end;
$$;

commit;
