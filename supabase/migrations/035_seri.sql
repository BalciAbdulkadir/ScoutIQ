-- 035: Seri sayacı
-- Supabase SQL Editor'da tek seferde çalıştırılır. Hata olursa hiçbir değişiklik uygulanmaz.
-- 034_skor_sunucuda.sql'den sonra çalıştırılmalıdır (bağımsızdır, sırası önemli değil).
--
-- seri_getir(): kullanıcının art arda en az bir oyunu bitirdiği ('tamamlandi') gün sayısı, Türkiye saatine göre.
--   - Bugün henüz bir oyun bitirilmediyse seri dünden geriye sayılır (gün bitmeden seri sıfırlanmış görünmesin).
--   - Gün, kaydın oyun günüdür (kullanici_oyun_gecmisi.tarih): gece yarısını geçip biten oyun kendi gününe sayılır.
--   - Puan değildir, sıralamada kullanılmaz; sadece ana menüde "🔥 6 gün" olarak gösterilir.
--   - Sadece kendi serisini döndürür (auth.uid()). Giriş yapılmamışsa 0.

begin;

create or replace function public.seri_getir()
returns integer
language sql
stable
security definer
set search_path = ''
as $$
    with bugun as (
        select public.bugunun_tarihi() as gun
    ),
    gunler as (
        select distinct g.tarih
        from public.kullanici_oyun_gecmisi g, bugun b
        where g.kullanici_id = (select auth.uid())
          and g.durum = 'tamamlandi'
          and g.tarih <= b.gun
    ),
    baslangic as (
        select case when exists (select 1 from gunler, bugun b where gunler.tarih = b.gun)
                    then b.gun else b.gun - 1 end as gun
        from bugun b
    ),
    sirali as (
        select gunler.tarih, row_number() over (order by gunler.tarih desc) as n
        from gunler, baslangic
        where gunler.tarih <= baslangic.gun
    )
    -- Başlangıçtan geriye kesintisiz giden günler: ilk boşluktan sonraki hiçbir gün bu eşitliği sağlamaz
    select count(*)::integer
    from sirali, baslangic
    where sirali.tarih = baslangic.gun - (sirali.n - 1)::integer;
$$;

revoke execute on function public.seri_getir() from public, anon;
grant execute on function public.seri_getir() to authenticated;

commit;
