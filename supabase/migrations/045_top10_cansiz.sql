-- 045: Top 10'da cansız mod (puansız, sadece eğlence için)
-- Supabase SQL Editor'da tek seferde çalıştırılır. Hata olursa hiçbir değişiklik uygulanmaz.
-- 044_sure_kisiti_duzeltme.sql'den sonra çalıştırılmalıdır. Tekrar çalıştırılabilir.
-- SIRA: PR birleşir -> bu dosya çalıştırılır -> yeni uygulama sürümü kurulur.
-- Eski uygulama sürümünü bozmaz: eski sürüm oyun_ac'ı p_cansiz göndermeden çağırır, Top 10 eskisi gibi 3 canla açılır.
-- Yeni sürüm sadece cansız Top 10 açarken p_cansiz gönderir; bu dosyadan önce kurulursa sadece cansız Top 10 açılmaz.
--
-- Ürün sahibinin 24 Kasım 2026 kararı:
--   - Top 10 iki şekilde oynanabilir: 3 canla (puanlı, eskisi gibi) ya da cansız (puansız). Soru aynıdır.
--   - Seçim oyun açılırken bir kez yapılır, sonradan değişmez. Günde yine tek Top 10 oynanır.
--   - Cansız oyunda yanlış tahmin can götürmez, tahmin sınırı yoktur. Oyun 10 oyuncu bulununca ya da pes edilince
--     biter. Puan yazılmaz (puan null, sebep 'cansiz'), liderlik tablosuna girmez. Seri sayılır (oyun bitirilmiştir).
--
-- Değişenler:
--   kullanici_oyun_gecmisi.cansiz : yeni kolon (varsayılan false). Uygulama bunu oyun_ac'ın dönüşünden okur.
--                                   Tablonun okuma izni kolon bazında değildir; kullanıcı sadece kendi satırlarını
--                                   görür (002), kendi oyununun modu gizli bilgi değildir. Yazma izni yoktur (034, 040).
--   oyun_ac      : 043'teki gövde. Yeni parametre p_cansiz (varsayılan false, sadece top10), dönüşe 'cansiz' eklendi.
--                  İmza değiştiği için eski (text, integer) hâli silinir; eski sürüm aynı adlı parametrelerle yenisini
--                  çağırır.
--   top10_tahmin : 031'deki gövde. Cansız oyunda can sayılmaz, 'kalan_can' null döner.
--   puan_yaz     : 038'deki gövde. Cansız oyunun puanı yazılmaz.
--
-- Kontrol (çalıştırdıktan sonra):
--   select pg_get_function_identity_arguments(oid) from pg_proc where proname = 'oyun_ac';
--     -> 1 satır: p_oyun_tipi text, p_sure integer, p_cansiz boolean
--   select column_name, column_default from information_schema.columns
--   where table_name = 'kullanici_oyun_gecmisi' and column_name = 'cansiz';            -> 1 satır, false
--   select prosrc like '%cansiz%' from pg_proc where proname in ('top10_tahmin', 'puan_yaz');  -> 2 satır, true

begin;

-- 1) Kaydın modu
alter table public.kullanici_oyun_gecmisi
    add column if not exists cansiz boolean not null default false;

-- 2) Oyun açılırken mod seçimi
drop function if exists public.oyun_ac(text, integer);

create or replace function public.oyun_ac(p_oyun_tipi text, p_sure integer default null, p_cansiz boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_kullanici uuid := (select auth.uid());
    v_bugun date := public.bugunun_tarihi();
    v_oyun text := split_part(p_oyun_tipi, '_', 1);
    v_oyun_id uuid;
    v_soru jsonb;
    v_kayit record;
    v_durum text;
    v_yeni boolean := false;
    v_sure integer;
    v_baslangic timestamptz;
    v_kalan integer;
    v_sure_doldu boolean := false;
    v_soru_sayisi integer;
    v_siradaki smallint;
    v_gorulen smallint[];
begin
    if v_kullanici is null then
        raise exception 'Giriş yapılmamış';
    end if;

    if p_oyun_tipi is null or p_oyun_tipi not in ('kesisim_kolay', 'kesisim_orta', 'kesisim_zor',
                                                  'bonservis_kolay', 'bonservis_orta', 'bonservis_zor',
                                                  'izgara_kolay', 'izgara_orta', 'izgara_zor',
                                                  'bingo', 'top10') then
        raise exception 'Geçersiz oyun';
    end if;

    -- Süre seçenekleri: 40, 60, 90 sn (043). 30 sn sadece eski sürüm uygulamalar için kabul edilir. Bingo'da 30 ve 40 sn
    -- yoktur, Top 10 süresizdir.
    if p_sure is not null and (v_oyun = 'top10' or p_sure not in (30, 40, 60, 90)
                               or (v_oyun = 'bingo' and p_sure in (30, 40))) then
        raise exception 'Geçersiz süre';
    end if;

    -- Cansız oyun sadece Top 10'da vardır (045)
    if coalesce(p_cansiz, false) and v_oyun <> 'top10' then
        raise exception 'Geçersiz mod';
    end if;

    select g.id, g.soru_verisi into v_oyun_id, v_soru
    from public.gunluk_oyunlar g
    where g.oyun_tipi = p_oyun_tipi and g.tarih = v_bugun;
    if v_oyun_id is null then
        return jsonb_build_object('durum', 'yok', 'tarih', v_bugun);
    end if;

    -- Kayıt yoksa açılır, süreli oyunda saat aynı anda başlar. Top 10'da can seçimi (cansiz) aynı anda yazılır, sonradan
    -- değişmez; kayıt varsa p_cansiz yok sayılır. Aynı anda gelen iki istekten biri açar, diğeri o kaydı
    -- okur. Izgara'nın süresi ayrı tablodadır (013).
    if not exists (
        select 1 from public.kullanici_oyun_gecmisi
        where kullanici_id = v_kullanici and oyun_tipi = p_oyun_tipi and tarih = v_bugun
    ) then
        insert into public.kullanici_oyun_gecmisi (kullanici_id, oyun_id, oyun_tipi, tarih, skor, durum, sure_saniye, sure_baslangic,
                                                  cansiz)
        values (v_kullanici, v_oyun_id, p_oyun_tipi, v_bugun, 0, 'basladi',
                case when v_oyun <> 'izgara' then p_sure end,
                case when v_oyun <> 'izgara' and p_sure is not null then now() end,
                coalesce(p_cansiz, false))
        on conflict (kullanici_id, oyun_tipi, tarih) do nothing;
        v_yeni := found;

        if v_yeni and v_oyun = 'izgara' and p_sure is not null then
            insert into public.izgara_sureleri (kullanici_id, oyun_id, sure_saniye)
            values (v_kullanici, v_oyun_id, p_sure)
            on conflict (kullanici_id, oyun_id) do nothing;
        end if;
    end if;

    select g.skor, g.durum, g.ilerleme, g.sure_saniye, g.sure_baslangic, g.cansiz into v_kayit
    from public.kullanici_oyun_gecmisi g
    where g.kullanici_id = v_kullanici and g.oyun_tipi = p_oyun_tipi and g.tarih = v_bugun
    for update;
    v_durum := v_kayit.durum;

    if v_oyun = 'izgara' then
        select s.sure_saniye, s.baslangic into v_sure, v_baslangic
        from public.izgara_sureleri s
        where s.kullanici_id = v_kullanici and s.oyun_id = v_oyun_id;
    else
        v_sure := v_kayit.sure_saniye;
        v_baslangic := v_kayit.sure_baslangic;
    end if;
    if v_sure is not null then
        v_kalan := greatest(0, ceil(extract(epoch from (v_baslangic + make_interval(secs => v_sure) - now())))::integer);
    end if;

    -- Oyun kapalıyken süre dolmuş: kayıt o anki skorla kapatılır (skoru hamle fonksiyonları yazar, değişmez)
    if v_durum = 'basladi' and v_kalan = 0 then
        update public.kullanici_oyun_gecmisi
        set durum = 'tamamlandi'
        where kullanici_id = v_kullanici and oyun_tipi = p_oyun_tipi and tarih = v_bugun and durum = 'basladi';
        v_durum := 'tamamlandi';
        v_sure_doldu := true;
    end if;

    if v_oyun in ('kesisim', 'bonservis') then
        v_soru_sayisi := jsonb_array_length(v_soru);
    end if;

    -- Açık oyunda henüz sırası gelmemiş soru ve oyuncu gönderilmez
    if v_durum = 'basladi' then
        if v_oyun in ('kesisim', 'bonservis') then
            -- Cevaplanmış sorular + sıradaki soru. Eski Bonservis sorularındaki sağdaki oyuncunun bedeli çıkarılır.
            select coalesce(jsonb_agg(t.e - 'oyuncu_b_bonservis' order by t.i), '[]'::jsonb) into v_soru
            from jsonb_array_elements(v_soru) with ordinality as t(e, i)
            where t.i <= jsonb_array_length(v_kayit.ilerleme) + 1;
        elsif v_oyun = 'bingo' then
            v_siradaki := public.bingo_siradaki(v_oyun_id, v_kullanici);
            select coalesce(array_agg(h.oyuncu), '{}') into v_gorulen
            from public.bingo_hamleleri h
            where h.kullanici_id = v_kullanici and h.oyun_id = v_oyun_id;

            v_soru := jsonb_set(v_soru, '{oyuncular}', (
                select coalesce(jsonb_agg(case when t.i = v_siradaki or t.i::smallint = any(v_gorulen) then t.e
                                               else 'null'::jsonb end order by t.i), '[]'::jsonb)
                from jsonb_array_elements(v_soru -> 'oyuncular') with ordinality as t(e, i)));
        end if;
    end if;

    return jsonb_build_object(
        'durum', v_durum,
        'yeni', v_yeni,
        'oyun_id', v_oyun_id,
        'tarih', v_bugun,
        'skor', v_kayit.skor,
        'ilerleme', v_kayit.ilerleme,
        'sure', v_sure,
        'kalan', v_kalan,
        'sure_doldu', v_sure_doldu,
        'soru_sayisi', v_soru_sayisi,
        'siradaki', v_siradaki,
        'soru_verisi', v_soru,
        'cansiz', v_kayit.cansiz);
end;
$$;

revoke execute on function public.oyun_ac(text, integer, boolean) from public, anon;
grant execute on function public.oyun_ac(text, integer, boolean) to authenticated;
-- 3) Top 10 tahmini: cansız oyunda can yoktur
--    Dönüş: { dogru, sira, deger, tekrar, oyuncu_isim, foto_url, skor, kalan_can, bitti }; cansız oyunda kalan_can null.
create or replace function public.top10_tahmin(p_oyun_id uuid, p_oyuncu_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    c_can constant integer := 3;
    v_kullanici uuid := (select auth.uid());
    v_isim text;
    v_foto text;
    v_cevap_foto text;
    v_sira smallint;
    v_deger text;
    v_skor integer;
    v_yanlis integer;
    v_bitti boolean;
    v_cansiz boolean;
begin
    if v_kullanici is null then
        raise exception 'Giriş yapılmamış';
    end if;

    select isim, foto_url into v_isim, v_foto from public.oyuncular where id = p_oyuncu_id;
    if v_isim is null then
        raise exception 'Oyuncu bulunamadı';
    end if;

    if not exists (
        select 1 from public.gunluk_oyunlar
        where id = p_oyun_id and oyun_tipi = 'top10' and tarih <= public.bugunun_tarihi()
    ) then
        raise exception 'Oyun bulunamadı';
    end if;

    -- Kayıt kilitlenir: aynı anda gelen iki tahmin sırayla işlenir
    select cansiz into v_cansiz
    from public.kullanici_oyun_gecmisi
    where kullanici_id = v_kullanici
      and oyun_id = p_oyun_id
      and durum = 'basladi'
    for update;
    if not found then
        raise exception 'Oyun açık değil';
    end if;

    select count(sira), count(*) filter (where sira is null) into v_skor, v_yanlis
    from public.top10_tahminleri
    where kullanici_id = v_kullanici and oyun_id = p_oyun_id;

    -- Canı bitmiş oyun (031'den önce 3'ten fazla yanlış yapılmış olabilir): tahmin alınmaz, oyun biter
    if not v_cansiz and v_yanlis >= c_can then
        update public.kullanici_oyun_gecmisi
        set skor = v_skor, durum = 'tamamlandi'
        where kullanici_id = v_kullanici and oyun_id = p_oyun_id and durum = 'basladi';

        return jsonb_build_object(
            'dogru', false, 'sira', null, 'deger', null, 'tekrar', false, 'oyuncu_isim', v_isim, 'foto_url', v_foto,
            'skor', v_skor, 'kalan_can', 0, 'bitti', true);
    end if;

    -- Daha önce doğru bilinmiş ya da yanlış denenmiş oyuncu: tahmin sayılmaz, can gitmez
    if exists (
        select 1 from public.top10_tahminleri
        where kullanici_id = v_kullanici and oyun_id = p_oyun_id and oyuncu_isim = v_isim
    ) then
        return jsonb_build_object(
            'dogru', false, 'sira', null, 'deger', null, 'tekrar', true, 'oyuncu_isim', v_isim, 'foto_url', v_foto,
            'skor', v_skor, 'kalan_can', case when v_cansiz then null else c_can - v_yanlis end, 'bitti', false);
    end if;

    -- Listede bu isimde ve henüz bulunmamış bir oyuncu varsa onun sırası ve fotoğrafı
    select c.sira, c.deger, o.foto_url into v_sira, v_deger, v_cevap_foto
    from public.top10_cevaplari c
    join public.oyuncular o on o.id = c.oyuncu_id
    where c.oyun_id = p_oyun_id
      and o.isim = v_isim
      and not exists (
          select 1 from public.top10_tahminleri t
          where t.kullanici_id = v_kullanici and t.oyun_id = p_oyun_id and t.sira = c.sira
      )
    order by c.sira
    limit 1;

    insert into public.top10_tahminleri (kullanici_id, oyun_id, oyuncu_id, oyuncu_isim, sira)
    values (v_kullanici, p_oyun_id, p_oyuncu_id, v_isim, v_sira);

    if v_sira is not null then
        v_skor := v_skor + 1;
    else
        v_yanlis := v_yanlis + 1;
    end if;
    v_bitti := v_skor = 10 or (not v_cansiz and v_yanlis >= c_can);

    update public.kullanici_oyun_gecmisi
    set skor = v_skor,
        durum = case when v_bitti then 'tamamlandi' else durum end
    where kullanici_id = v_kullanici
      and oyun_id = p_oyun_id
      and durum = 'basladi';

    return jsonb_build_object(
        'dogru', v_sira is not null, 'sira', v_sira, 'deger', v_deger, 'tekrar', false, 'oyuncu_isim', v_isim,
        'foto_url', case when v_sira is not null then coalesce(v_cevap_foto, v_foto) else v_foto end,
        'skor', v_skor, 'kalan_can', case when v_cansiz then null else greatest(c_can - v_yanlis, 0) end,
        'bitti', v_bitti);
end;
$$;

revoke execute on function public.top10_tahmin(uuid, uuid) from public, anon;
grant execute on function public.top10_tahmin(uuid, uuid) to authenticated;

-- 4) Puan: cansız oyun puansızdır
create or replace function public.puan_yaz()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_sure integer := new.sure_saniye;
    v_baslangic timestamptz := new.sure_baslangic;
begin
    if old.durum = 'basladi' and new.durum = 'tamamlandi' then
        new.bitis_zamani := now();

        -- Cansız Top 10 (045): puan yazılmaz, liderlik tablosuna girmez
        if new.cansiz then
            new.puan_detay := jsonb_build_object('puan', null, 'sebep', 'cansiz');
            new.puan := null;
            return new;
        end if;

        -- Izgara'nın süresi ayrı tablodadır (013)
        if new.oyun_tipi like 'izgara\_%' then
            select s.sure_saniye, s.baslangic into v_sure, v_baslangic
            from public.izgara_sureleri s
            where s.kullanici_id = new.kullanici_id and s.oyun_id = new.oyun_id;
        end if;

        new.puan_detay := public.puan_hesapla(new.oyun_tipi, new.kullanici_id, new.oyun_id, new.skor,
                                              v_sure, v_baslangic, new.bitis_zamani);
        new.puan := (new.puan_detay ->> 'puan')::integer;
    else
        new.puan := old.puan;
        new.puan_detay := old.puan_detay;
        new.bitis_zamani := old.bitis_zamani;
    end if;
    return new;
end;
$$;

revoke execute on function public.puan_yaz() from public, anon, authenticated;

commit;

-- PostgREST yeni oyun_ac imzasını hemen görsün
notify pgrst, 'reload schema';
