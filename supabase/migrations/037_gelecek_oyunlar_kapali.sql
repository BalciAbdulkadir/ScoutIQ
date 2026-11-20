-- 037: Gelecek tarihli oyunlar 00.00'dan önce hiçbir fonksiyondan oynanamaz ve cevabı alınamaz
-- Supabase SQL Editor'da tek seferde çalıştırılır. Hata olursa hiçbir değişiklik uygulanmaz.
-- 036_kesisim_kontrol_kapali.sql'den sonra çalıştırılmalıdır. Tekrar çalıştırılabilir.
-- Uygulamanın eski sürümlerini bozmaz: uygulama sadece bugünün oyunlarını açar.
--
-- Neden: Backend artık yarının oyunlarını bir gün önceden, Türkiye saatiyle 18.00'de üretiyor (Cloud Run işi,
-- backend/CLOUD_RUN.md). Yarının oyunları akşamdan veritabanında durur, kullanıcıya 00.00'da açılır.
--   - gunluk_oyunlar okuma politikası (002) bugünden sonrasını zaten gizler: uygulama yarının oyununu, id'sini de
--     göremez.
--   - Cevap tabloları (bonservis_cevaplari, kesisim_hedefleri, top10_cevaplari, top10_sorulari, bingo_eslesmeleri)
--     RLS açık ve politikasız olduğu için uygulamaya zaten kapalıdır.
--   - Ama oyun_id alan security definer fonksiyonların bir kısmı oyunun tarihine bakmıyordu, kayıt açma politikası da
--     kaydın oyun_id'sinin o günün oyunu olup olmadığına bakmıyordu. Yarının oyun id'sini bir yolla öğrenen biri o oyun
--     için bugün tarihli bir kayıt açıp pes edebilir, sonra örnek cevaplardan yarının cevaplarını okuyabilirdi.
--     Oyun id'leri tahmin edilemez (uuid), yine de gelecekteki bir oyunun cevabı hiçbir fonksiyondan dönmemeli.
--
-- Düzeltme:
--   1) Kayıt açma politikası: açılan kaydın oyun_id'si, kaydın oyun tipi ve tarihiyle (bugün) aynı olan oyunu
--      göstermelidir. Uygulama kaydı zaten günün oyunuyla açıyor (mobile/lib/services/oyun_deposu.dart, kayitAc).
--   2) Tarihe bakmayan fonksiyonlara "oyunun tarihi bugünden sonra değil" kontrolü eklenir. Gövdeler son hâllerinden
--      kopyalandı, değişen tek şey bu kontroldür:
--        izgara_sureyi_baslat (013), izgara_pes_et (011), izgara_ornek_cevaplar (012),
--        bingo_pes_et (021), bingo_ornek_cevaplar (021),
--        top10_pes_et (029), top10_cevaplar (029),
--        kesisim_ornek_cevaplar (019), bonservis_bedelleri (034)
--      Oyun yapan fonksiyonlar (pes etme, süre başlatma) gelecek tarihli oyunda 'Oyun bulunamadı' hatası verir,
--      cevap döndürenler boş döner.
--   Zaten kontrol eden fonksiyonlar değişmez: kesisim_cevap, bonservis_tahmin (034), izgara_tahmin (013),
--   bingo_hamle (023), top10_tahmin (031). bingo_siradaki, bonservis_bedeli, acik_kaydi_al ve kesisim_cevap_kontrol
--   uygulamaya kapalı iç yardımcılardır, onları çağıran fonksiyonlar tarihi kontrol eder. oyunu_bitir sadece kullanıcının
--   açık kaydını kapatır, oyun ya da cevap döndürmez.
--   create or replace izinleri korur; revoke ve grant satırları yine de tekrar yazıldı.
--
-- Kontrol (çalıştırdıktan sonra, SQL Editor'da): aşağıdaki sorgu 9 satır, hepsinde true döndürmelidir.
--   select p.proname, pg_get_functiondef(p.oid) ilike '%bugunun_tarihi()%'
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--   where n.nspname = 'public' and p.proname in ('izgara_sureyi_baslat', 'izgara_pes_et', 'izgara_ornek_cevaplar',
--     'bingo_pes_et', 'bingo_ornek_cevaplar', 'top10_pes_et', 'top10_cevaplar', 'kesisim_ornek_cevaplar',
--     'bonservis_bedelleri');
--   select with_check ilike '%gunluk_oyunlar%' from pg_policies
--   where tablename = 'kullanici_oyun_gecmisi' and policyname = 'kullanici_oyun_gecmisi_ekleme';
--     -> true olmalı

begin;

-- 1) Kayıt açma politikası (034'teki politikanın aynısı, son koşul yeni)
drop policy if exists "kullanici_oyun_gecmisi_ekleme" on public.kullanici_oyun_gecmisi;
create policy "kullanici_oyun_gecmisi_ekleme" on public.kullanici_oyun_gecmisi
    for insert to authenticated
    with check (
        kullanici_id = (select auth.uid())
        and tarih = (now() at time zone 'Europe/Istanbul')::date
        and skor = 0
        and durum = 'basladi'
        and ilerleme = '[]'::jsonb
        and sure_saniye is null
        and sure_baslangic is null
        and exists (
            select 1
            from public.gunluk_oyunlar g
            where g.id = kullanici_oyun_gecmisi.oyun_id
              and g.oyun_tipi = kullanici_oyun_gecmisi.oyun_tipi
              and g.tarih = kullanici_oyun_gecmisi.tarih
        )
    );

-- 2) Izgara

create or replace function public.izgara_sureyi_baslat(p_oyun_id uuid, p_sure integer default null)
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

    -- Gelecek tarihli oyun 00.00'dan önce oynanamaz (037)
    if not exists (
        select 1 from public.gunluk_oyunlar
        where id = p_oyun_id and tarih <= public.bugunun_tarihi()
    ) then
        raise exception 'Oyun bulunamadı';
    end if;

    if p_sure is not null then
        if p_sure not in (30, 60, 90) then
            raise exception 'Geçersiz süre';
        end if;

        -- Sadece bu kullanıcının açık (basladi) Izgara kaydı varsa süre başlatılır
        if not exists (
            select 1
            from public.kullanici_oyun_gecmisi
            where kullanici_id = v_kullanici
              and oyun_id = p_oyun_id
              and oyun_tipi like 'izgara\_%'
              and durum = 'basladi'
        ) then
            raise exception 'Oyun açık değil';
        end if;

        insert into public.izgara_sureleri (kullanici_id, oyun_id, sure_saniye)
        values (v_kullanici, p_oyun_id, p_sure)
        on conflict (kullanici_id, oyun_id) do nothing;
    end if;

    select s.sure_saniye, s.baslangic + make_interval(secs => s.sure_saniye) into v_sure, v_bitis
    from public.izgara_sureleri s
    where s.kullanici_id = v_kullanici and s.oyun_id = p_oyun_id;

    if v_bitis is null then
        return null;
    end if;

    return jsonb_build_object(
        'sure', v_sure,
        'kalan', greatest(0, ceil(extract(epoch from (v_bitis - now())))::integer));
end;
$$;

revoke execute on function public.izgara_sureyi_baslat(uuid, integer) from public, anon;
grant execute on function public.izgara_sureyi_baslat(uuid, integer) to authenticated;

create or replace function public.izgara_pes_et(p_oyun_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_kullanici uuid := (select auth.uid());
    v_skor integer;
begin
    if v_kullanici is null then
        raise exception 'Giriş yapılmamış';
    end if;

    -- Gelecek tarihli oyun 00.00'dan önce oynanamaz (037)
    if not exists (
        select 1 from public.gunluk_oyunlar
        where id = p_oyun_id and tarih <= public.bugunun_tarihi()
    ) then
        raise exception 'Oyun bulunamadı';
    end if;

    select count(hucre) into v_skor
    from public.izgara_tahminleri
    where kullanici_id = v_kullanici and oyun_id = p_oyun_id;

    update public.kullanici_oyun_gecmisi
    set skor = v_skor, durum = 'tamamlandi'
    where kullanici_id = v_kullanici
      and oyun_id = p_oyun_id
      and oyun_tipi like 'izgara\_%'
      and durum = 'basladi';

    return v_skor;
end;
$$;

revoke execute on function public.izgara_pes_et(uuid) from public, anon;
grant execute on function public.izgara_pes_et(uuid) to authenticated;

create or replace function public.izgara_ornek_cevaplar(p_oyun_id uuid)
returns table (hucre integer, oyuncu_isim text, foto_url text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_tahta jsonb;
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

    -- Gelecek tarihli oyunun tahtası okunmaz, cevap dönmez (037)
    select soru_verisi into v_tahta
    from public.gunluk_oyunlar
    where id = p_oyun_id and oyun_tipi like 'izgara\_%' and tarih <= public.bugunun_tarihi();

    return query
    select h, ornek.isim, ornek.foto_url
    from generate_series(0, 8) as h
    left join lateral (
        select o.isim::text as isim, o.foto_url::text as foto_url
        from public.izgara_baslik_oyunculari(v_tahta -> 'satirlar' -> (h / 3)) s(oyuncu_id)
        join public.izgara_baslik_oyunculari(v_tahta -> 'sutunlar' -> (h % 3)) u(oyuncu_id) using (oyuncu_id)
        join public.oyuncular o on o.id = s.oyuncu_id
        order by o.toplam_bonservis desc, o.isim
        limit 1
    ) ornek on true
    where v_tahta is not null;
end;
$$;

revoke execute on function public.izgara_ornek_cevaplar(uuid) from public, anon;
grant execute on function public.izgara_ornek_cevaplar(uuid) to authenticated;

-- 3) Bingo

create or replace function public.bingo_pes_et(p_oyun_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_kullanici uuid := (select auth.uid());
    v_skor integer;
begin
    if v_kullanici is null then
        raise exception 'Giriş yapılmamış';
    end if;

    -- Gelecek tarihli oyun 00.00'dan önce oynanamaz (037)
    if not exists (
        select 1 from public.gunluk_oyunlar
        where id = p_oyun_id and tarih <= public.bugunun_tarihi()
    ) then
        raise exception 'Oyun bulunamadı';
    end if;

    select count(*) filter (where dogru) into v_skor
    from public.bingo_hamleleri
    where kullanici_id = v_kullanici and oyun_id = p_oyun_id;

    update public.kullanici_oyun_gecmisi
    set skor = v_skor, durum = 'tamamlandi'
    where kullanici_id = v_kullanici
      and oyun_id = p_oyun_id
      and (oyun_tipi = 'bingo' or oyun_tipi like 'bingo\_%')
      and durum = 'basladi';

    return v_skor;
end;
$$;

revoke execute on function public.bingo_pes_et(uuid) from public, anon;
grant execute on function public.bingo_pes_et(uuid) to authenticated;

create or replace function public.bingo_ornek_cevaplar(p_oyun_id uuid)
returns table (hucre integer, oyuncu_isim text, foto_url text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_kullanici uuid := (select auth.uid());
    v_kutu integer;
begin
    if v_kullanici is null then
        raise exception 'Giriş yapılmamış';
    end if;

    if not exists (
        select 1 from public.kullanici_oyun_gecmisi g
        where g.kullanici_id = v_kullanici and g.oyun_id = p_oyun_id and g.durum = 'tamamlandi'
    ) then
        return;
    end if;

    -- Gelecek tarihli oyunun cevabı dönmez (037)
    if not exists (
        select 1 from public.gunluk_oyunlar
        where id = p_oyun_id and tarih <= public.bugunun_tarihi()
    ) then
        return;
    end if;

    select jsonb_array_length(soru_verisi -> 'hucreler') into v_kutu from public.gunluk_oyunlar where id = p_oyun_id;

    return query
    select h::integer,
           (go.soru_verisi -> 'oyuncular' -> (e.sira - 1) ->> 'isim'),
           (go.soru_verisi -> 'oyuncular' -> (e.sira - 1) ->> 'foto')
    from generate_series(0, coalesce(v_kutu, 0) - 1) as h
    join public.gunluk_oyunlar go on go.id = p_oyun_id
    cross join lateral (
        select be.sira
        from public.bingo_eslesmeleri be
        where be.oyun_id = p_oyun_id and h::smallint = any(be.hucreler)
        order by be.sira
        limit 1
    ) e
    where not exists (
        select 1 from public.bingo_hamleleri bh
        where bh.kullanici_id = v_kullanici and bh.oyun_id = p_oyun_id and bh.hucre = h and bh.dogru
    );
end;
$$;

revoke execute on function public.bingo_ornek_cevaplar(uuid) from public, anon;
grant execute on function public.bingo_ornek_cevaplar(uuid) to authenticated;

-- 4) Top 10

create or replace function public.top10_pes_et(p_oyun_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_kullanici uuid := (select auth.uid());
    v_skor integer;
begin
    if v_kullanici is null then
        raise exception 'Giriş yapılmamış';
    end if;

    -- Gelecek tarihli oyun 00.00'dan önce oynanamaz (037)
    if not exists (
        select 1 from public.gunluk_oyunlar
        where id = p_oyun_id and tarih <= public.bugunun_tarihi()
    ) then
        raise exception 'Oyun bulunamadı';
    end if;

    select count(sira) into v_skor
    from public.top10_tahminleri
    where kullanici_id = v_kullanici and oyun_id = p_oyun_id;

    update public.kullanici_oyun_gecmisi
    set skor = v_skor, durum = 'tamamlandi'
    where kullanici_id = v_kullanici
      and oyun_id = p_oyun_id
      and oyun_tipi = 'top10'
      and durum = 'basladi';

    return v_skor;
end;
$$;

revoke execute on function public.top10_pes_et(uuid) from public, anon;
grant execute on function public.top10_pes_et(uuid) to authenticated;

create or replace function public.top10_cevaplar(p_oyun_id uuid)
returns table (sira integer, oyuncu_isim text, foto_url text, deger text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_kullanici uuid := (select auth.uid());
    v_bitti boolean;
begin
    if v_kullanici is null then
        raise exception 'Giriş yapılmamış';
    end if;

    -- Gelecek tarihli oyunun cevabı dönmez (037)
    if not exists (
        select 1 from public.gunluk_oyunlar
        where id = p_oyun_id and tarih <= public.bugunun_tarihi()
    ) then
        return;
    end if;

    select exists (
        select 1 from public.kullanici_oyun_gecmisi g
        where g.kullanici_id = v_kullanici and g.oyun_id = p_oyun_id and g.durum = 'tamamlandi'
    ) into v_bitti;

    return query
    select c.sira::integer, c.oyuncu_isim, o.foto_url, c.deger
    from public.top10_cevaplari c
    join public.oyuncular o on o.id = c.oyuncu_id
    where c.oyun_id = p_oyun_id
      and (v_bitti or exists (
          select 1 from public.top10_tahminleri t
          where t.kullanici_id = v_kullanici and t.oyun_id = p_oyun_id and t.sira = c.sira
      ))
    order by c.sira;
end;
$$;

revoke execute on function public.top10_cevaplar(uuid) from public, anon;
grant execute on function public.top10_cevaplar(uuid) to authenticated;

-- 5) Kesişim ve Bonservis (cevap ve tahmin fonksiyonları 034'te kontrol ediyordu, bu ikisi etmiyordu)

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
      and go.oyun_tipi like 'kesisim%'
      and go.tarih <= public.bugunun_tarihi(); -- gelecek tarihli oyunun cevabı dönmez (037)
end;
$$;

revoke execute on function public.kesisim_ornek_cevaplar(uuid) from public, anon;
grant execute on function public.kesisim_ornek_cevaplar(uuid) to authenticated;

create or replace function public.bonservis_bedelleri(p_oyun_id uuid)
returns table (soru_index integer, rakip_bonservis bigint)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_kullanici uuid := (select auth.uid());
    v_durum text;
    v_cevaplanan integer;
    v_soru_sayisi integer;
begin
    if v_kullanici is null then
        raise exception 'Giriş yapılmamış';
    end if;

    select g.durum, jsonb_array_length(g.ilerleme) into v_durum, v_cevaplanan
    from public.kullanici_oyun_gecmisi g
    where g.kullanici_id = v_kullanici and g.oyun_id = p_oyun_id;
    if v_durum is null then
        return;
    end if;

    -- Gelecek tarihli oyunun bedelleri dönmez (037)
    select jsonb_array_length(soru_verisi) into v_soru_sayisi
    from public.gunluk_oyunlar
    where id = p_oyun_id and oyun_tipi like 'bonservis%' and tarih <= public.bugunun_tarihi();
    if v_soru_sayisi is null then
        return;
    end if;

    return query
    select i, public.bonservis_bedeli(p_oyun_id, i)
    from generate_series(0, case when v_durum = 'tamamlandi' then v_soru_sayisi else v_cevaplanan end - 1) as i;
end;
$$;

revoke execute on function public.bonservis_bedelleri(uuid) from public, anon;
grant execute on function public.bonservis_bedelleri(uuid) to authenticated;

commit;
