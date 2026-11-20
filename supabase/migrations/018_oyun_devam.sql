-- 018: Kesişim ve Bonservis'te süre ve kaldığı yerden devam
-- Supabase SQL Editor'da tek seferde çalıştırılır. Hata olursa hiçbir değişiklik uygulanmaz.
-- 003_cevap_dogrulama.sql'den sonra çalıştırılmalıdır. (015–017 onem_verileri branch'indedir, bu dosyadan bağımsızdır.)
--
-- Kurallar:
--   - Oyuncu başlarken süre seçer: süre yok, 30, 60 ya da 90 saniye. Süre bütün sorular içindir.
--   - Oyundan çıkınca oyun bitmez. Süre arkada işlemeye devam eder; süre bitmediyse (ya da oyun süresizse)
--     oyuncu kaldığı sorudan devam eder. Süre dolduysa oyun o anki skorla biter.
--   - Başlangıç zamanı sunucuda tutulur ve sadece oyun_sureyi_baslat fonksiyonuyla bir kez yazılır.
--   - Süre dolduktan sonra gelen skor güncellemesi kabul edilmez, kayıt o anki skorla kilitlenir.
--     Ağ gecikmesi yüzünden son saniyedeki cevap yanmasın diye 3 saniye tolerans vardır.

begin;

-- 1) Kayda ilerleme ve süre alanları.
--    ilerleme: cevaplanan sorular sırayla, ör. [{"dogru": true, "cevap": "Arda Güler"}, {"dogru": false}]
alter table public.kullanici_oyun_gecmisi
    add column if not exists ilerleme jsonb not null default '[]'::jsonb,
    add column if not exists sure_saniye smallint check (sure_saniye in (30, 60, 90)),
    add column if not exists sure_baslangic timestamptz;

-- Uygulama ilerlemeyi skorla birlikte yazar; süre alanlarını yazamaz
grant update (ilerleme) on public.kullanici_oyun_gecmisi to authenticated;

-- 2) Süreyi başlatır, { "sure": toplam saniye, "kalan": kalan saniye } döndürür (süresiz oyunda null).
--    p_sure null ise sadece kalan süre sorulur: uygulama yarım kalan oyunu açarken böyle çağırır.
--    Süre zaten başlatılmışsa yeni süre yok sayılır, saat sıfırlanmaz.
create or replace function public.oyun_sureyi_baslat(p_oyun_tipi text, p_tarih date, p_sure integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_kullanici uuid := (select auth.uid());
    v_sure integer;
    v_bitis timestamptz;
begin
    if v_kullanici is null then
        raise exception 'Giriş yapılmamış';
    end if;

    if p_oyun_tipi not in ('kesisim', 'bonservis') then
        raise exception 'Geçersiz oyun';
    end if;

    if p_sure is not null then
        if p_sure not in (30, 60, 90) then
            raise exception 'Geçersiz süre';
        end if;

        -- Sadece açık (basladi) ve henüz süresi olmayan kayda süre verilir
        update public.kullanici_oyun_gecmisi
        set sure_saniye = p_sure, sure_baslangic = now()
        where kullanici_id = v_kullanici
          and oyun_tipi = p_oyun_tipi
          and tarih = p_tarih
          and durum = 'basladi'
          and sure_saniye is null;
    end if;

    select g.sure_saniye, g.sure_baslangic + make_interval(secs => g.sure_saniye) into v_sure, v_bitis
    from public.kullanici_oyun_gecmisi g
    where g.kullanici_id = v_kullanici
      and g.oyun_tipi = p_oyun_tipi
      and g.tarih = p_tarih;

    if v_bitis is null then
        return null;
    end if;

    return jsonb_build_object(
        'sure', v_sure,
        'kalan', greatest(0, ceil(extract(epoch from (v_bitis - now())))::integer));
end;
$$;

revoke execute on function public.oyun_sureyi_baslat(text, date, integer) from public, anon;
grant execute on function public.oyun_sureyi_baslat(text, date, integer) to authenticated;

-- 3) Süresi dolmuş kayıt güncellenmek istenirse skor ve ilerleme değiştirilmez, kayıt kapatılır.
--    Süresiz kayıtlarda (Izgara dahil) hiçbir şey değişmez.
create or replace function public.oyun_suresi_kontrol()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    if old.durum = 'basladi'
       and old.sure_saniye is not null
       and now() > old.sure_baslangic + make_interval(secs => old.sure_saniye + 3) then
        new.skor := old.skor;
        new.ilerleme := old.ilerleme;
        new.durum := 'tamamlandi';
    end if;
    return new;
end;
$$;

drop trigger if exists oyun_suresi_kontrol on public.kullanici_oyun_gecmisi;
create trigger oyun_suresi_kontrol
    before update on public.kullanici_oyun_gecmisi
    for each row execute function public.oyun_suresi_kontrol();

commit;
