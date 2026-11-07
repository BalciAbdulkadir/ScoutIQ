-- 018: Her oyunda kolay, orta ve zor mod
-- Supabase SQL Editor'da tek seferde çalıştırılır. Hata olursa hiçbir değişiklik uygulanmaz.
-- 017_oyuncu_havuzu.sql'den sonra çalıştırılmalıdır (oyuncular.bilinirlik kullanılır).
--
-- Kurallar:
--   - Kesişim ve Bonservis de Izgara gibi üç ayrı günlük oyundur: kesisim_kolay, kesisim_orta, kesisim_zor,
--     bonservis_kolay, ... Soruların kademe dağılımı backend'de (ScoutIQ.API/Oyunlar/Zorluk.cs).
--   - Kullanıcı her oyunda günde yalnızca bir modu oynar. 014'teki Izgara kuralı bütün oyunlara genişletilir.
--   - Eski 'kesisim' ve 'bonservis' kayıtları geçmişte kalır, yeni oyun bu tiplerle üretilmez.

begin;

-- 1) Yeni oyun tipleri
alter table public.gunluk_oyunlar drop constraint gunluk_oyunlar_oyun_tipi_check;
alter table public.gunluk_oyunlar add constraint gunluk_oyunlar_oyun_tipi_check
    check (oyun_tipi in ('kesisim', 'bonservis',
                         'kesisim_kolay', 'kesisim_orta', 'kesisim_zor',
                         'bonservis_kolay', 'bonservis_orta', 'bonservis_zor',
                         'izgara_kolay', 'izgara_orta', 'izgara_zor'));

alter table public.kullanici_oyun_gecmisi drop constraint kullanici_oyun_gecmisi_oyun_tipi_check;
alter table public.kullanici_oyun_gecmisi add constraint kullanici_oyun_gecmisi_oyun_tipi_check
    check (oyun_tipi in ('kesisim', 'bonservis',
                         'kesisim_kolay', 'kesisim_orta', 'kesisim_zor',
                         'bonservis_kolay', 'bonservis_orta', 'bonservis_zor',
                         'izgara_kolay', 'izgara_orta', 'izgara_zor'));

-- 2) Kesişim cevap kontrolü: 003'teki fonksiyonun aynısı, Kesişim'in bütün modlarını kabul eder
create or replace function public.kesisim_cevap_kontrol(p_oyun_id uuid, p_soru_index integer, p_oyuncu_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_soru jsonb;
    v_isim text;
begin
    if (select auth.uid()) is null then
        raise exception 'Giriş yapılmamış';
    end if;

    select isim into v_isim from public.oyuncular where id = p_oyuncu_id;
    if v_isim is null then
        return false;
    end if;

    select soru_verisi -> p_soru_index into v_soru
    from public.gunluk_oyunlar
    where id = p_oyun_id
      and oyun_tipi like 'kesisim%'
      and tarih <= public.bugunun_tarihi();

    if v_soru is null then
        return false;
    end if;

    return exists (
        select 1
        from public.kariyer_gecmisi ka
        join public.kariyer_gecmisi kb on kb.oyuncu_id = ka.oyuncu_id
        join public.oyuncular o on o.id = ka.oyuncu_id
        where ka.kulup_id = (v_soru ->> 'kulup_a_id')::uuid
          and kb.kulup_id = (v_soru ->> 'kulup_b_id')::uuid
          and o.isim = v_isim
    );
end;
$$;

revoke execute on function public.kesisim_cevap_kontrol(uuid, integer, uuid) from public, anon;
grant execute on function public.kesisim_cevap_kontrol(uuid, integer, uuid) to authenticated;

-- 3) Kesişim örnek cevapları: 006'daki fonksiyonun aynısı, iki farkla: bütün modları kabul eder ve
--    en tanınmış cevap toplam bonservis yerine bilinirlik skoruyla seçilir (havuz dışındakiler en sona, sonra bonservis).
create or replace function public.kesisim_ornek_cevaplar(p_oyun_id uuid)
returns table (soru_index integer, oyuncu_isim text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
    if (select auth.uid()) is null then
        raise exception 'Giriş yapılmamış';
    end if;

    if not exists (
        select 1
        from public.kullanici_oyun_gecmisi g
        where g.kullanici_id = (select auth.uid())
          and g.oyun_id = p_oyun_id
          and g.durum = 'tamamlandi'
    ) then
        return;
    end if;

    return query
    select (s.idx - 1)::integer,
           (
               select o.isim::text
               from public.kariyer_gecmisi ka
               join public.kariyer_gecmisi kb on kb.oyuncu_id = ka.oyuncu_id
               join public.oyuncular o on o.id = ka.oyuncu_id
               where ka.kulup_id = (s.soru ->> 'kulup_a_id')::uuid
                 and kb.kulup_id = (s.soru ->> 'kulup_b_id')::uuid
               order by o.bilinirlik desc nulls last, o.toplam_bonservis desc, o.isim
               limit 1
           )
    from public.gunluk_oyunlar go,
         jsonb_array_elements(go.soru_verisi) with ordinality as s(soru, idx)
    where go.id = p_oyun_id
      and go.oyun_tipi like 'kesisim%';
end;
$$;

revoke execute on function public.kesisim_ornek_cevaplar(uuid) from public, anon;
grant execute on function public.kesisim_ornek_cevaplar(uuid) to authenticated;

-- 4) Günde tek mod: 014'teki Izgara tetikleyicisinin yerini alır, bütün modlu oyunlarda çalışır.
--    Oyun, tipin alt çizgiden önceki kısmıdır (kesisim_kolay -> kesisim). Bir modu açılmış oyunda kullanıcı
--    o gün başka bir mod için kayıt açamaz. Daha önce açılmış kayıtlara dokunmaz.
drop trigger if exists izgara_gunde_bir on public.kullanici_oyun_gecmisi;
drop function if exists public.izgara_gunde_bir();

create or replace function public.oyun_gunde_bir()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_oyun text := split_part(new.oyun_tipi, '_', 1);
begin
    if new.oyun_tipi like '%\_%' then
        -- Aynı anda gelen iki kayıt isteği sırayla işlenir, ikisi birden geçemez
        perform pg_advisory_xact_lock(hashtext(v_oyun || ':' || new.kullanici_id::text || ':' || new.tarih::text));

        if exists (
            select 1
            from public.kullanici_oyun_gecmisi
            where kullanici_id = new.kullanici_id
              and tarih = new.tarih
              and split_part(oyun_tipi, '_', 1) = v_oyun
              and oyun_tipi like '%\_%'
              and oyun_tipi <> new.oyun_tipi
        ) then
            raise exception 'Bugün bu oyunun başka bir modu oynandı' using hint = 'oyun_gunde_bir';
        end if;
    end if;
    return new;
end;
$$;

revoke execute on function public.oyun_gunde_bir() from public, anon, authenticated;

create trigger oyun_gunde_bir
    before insert on public.kullanici_oyun_gecmisi
    for each row execute function public.oyun_gunde_bir();

commit;
