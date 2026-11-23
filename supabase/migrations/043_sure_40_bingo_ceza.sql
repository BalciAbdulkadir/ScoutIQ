-- 043: 30 saniye yerine 40 saniye; Bingo'da süreli oyunda her yanlış kutu 2 saniye götürür
-- Supabase SQL Editor'da tek seferde çalıştırılır. Hata olursa hiçbir değişiklik uygulanmaz.
-- 042_bitmis_oyun_sorulari.sql'den sonra çalıştırılmalıdır. Tekrar çalıştırılabilir.
-- Eski uygulama sürümünü bozmaz:
--   - oyun_ac 30 saniyeyi kabul etmeye devam eder (eski sürüm 30 gönderir), puan çarpanı yine 1.5'tir.
--   - Eski sürüm Bingo'da yanlış kutuda sayacından 2 saniye düşmez; süreyi sunucu tuttuğu için süre dolunca hamle
--     yine kabul edilmez ve oyun sunucunun saatiyle biter. Ekrandaki sayaç sadece birkaç saniye geç kalır.
--
-- Ürün sahibinin 23 Kasım 2026 kararları:
--   1) Süre seçenekleri: süre yok, 40, 60, 90 saniye (30 saniye kalkar). Bingo'da süre yok, 60, 90 (değişmez).
--      40 saniyenin süre çarpanı 30 saniyeninki gibi 1.5'tir.
--   2) Bingo'da süreli oyunda (zorluk fark etmeksizin) yanlış kutuya konan her oyuncu süreden 2 saniye düşer.
--      Pas geçmek ceza değildir. Süresiz Bingo'da ceza yoktur. Ceza süreyi bitirirse oyun o anki skorla biter.
--      Uygulama: kayıttaki sure_baslangic 2 saniye geri alınır. Süre (sure_saniye) ve dolayısıyla süre çarpanı
--      değişmez; sürenin dolduğu an, kalan süre (oyun_ac, bingo_hamle, suresi_dolan_oyunlari_kapat) ve hız bonusu
--      (puan_hesapla) cezayı kendiliğinden içerir.
--      bingo_hamle yanlış kutuda dönüşe kalan saniyeyi ekler ('kalan'; süresiz oyunda null), uygulama sayacını
--      buna göre düzeltir.
--
-- Değişen fonksiyonlar (son hâlleri):
--   oyun_ac      : 040_oyun_ac.sql'deki gövde; sadece süre kontrolü değişti.
--   puan_hesapla : 039_puan_her_dogruya.sql'deki gövde; sadece süre çarpanına 40 eklendi.
--   bingo_hamle  : 040_oyun_ac.sql'deki gövde; sadece yanlış kutu dalı değişti.
--
-- Kontrol (çalıştırdıktan sonra):
--   select puan_hesapla('kesisim_zor', null, null, 10, 40, now() - interval '30 seconds', now());
--     -> "puan": 315, "sure_carpani": 1.5, "hiz_bonusu": 15
--   select puan_hesapla('kesisim_zor', null, null, 10, 30, now() - interval '22 seconds', now());
--     -> "puan": 316 (eski 30 saniyelik kayıtlar aynen hesaplanır)
--   select prosrc like '%2 seconds%' from pg_proc where proname = 'bingo_hamle';   -> true
--   select prosrc like '%(30, 40, 60, 90)%' from pg_proc where proname = 'oyun_ac'; -> true

begin;

-- 1) Süre seçenekleri
create or replace function public.oyun_ac(p_oyun_tipi text, p_sure integer default null)
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

    select g.id, g.soru_verisi into v_oyun_id, v_soru
    from public.gunluk_oyunlar g
    where g.oyun_tipi = p_oyun_tipi and g.tarih = v_bugun;
    if v_oyun_id is null then
        return jsonb_build_object('durum', 'yok', 'tarih', v_bugun);
    end if;

    -- Kayıt yoksa açılır, süreli oyunda saat aynı anda başlar. Aynı anda gelen iki istekten biri açar, diğeri o kaydı
    -- okur. Izgara'nın süresi ayrı tablodadır (013).
    if not exists (
        select 1 from public.kullanici_oyun_gecmisi
        where kullanici_id = v_kullanici and oyun_tipi = p_oyun_tipi and tarih = v_bugun
    ) then
        insert into public.kullanici_oyun_gecmisi (kullanici_id, oyun_id, oyun_tipi, tarih, skor, durum, sure_saniye, sure_baslangic)
        values (v_kullanici, v_oyun_id, p_oyun_tipi, v_bugun, 0, 'basladi',
                case when v_oyun <> 'izgara' then p_sure end,
                case when v_oyun <> 'izgara' and p_sure is not null then now() end)
        on conflict (kullanici_id, oyun_tipi, tarih) do nothing;
        v_yeni := found;

        if v_yeni and v_oyun = 'izgara' and p_sure is not null then
            insert into public.izgara_sureleri (kullanici_id, oyun_id, sure_saniye)
            values (v_kullanici, v_oyun_id, p_sure)
            on conflict (kullanici_id, oyun_id) do nothing;
        end if;
    end if;

    select g.skor, g.durum, g.ilerleme, g.sure_saniye, g.sure_baslangic into v_kayit
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
        'soru_verisi', v_soru);
end;
$$;

revoke execute on function public.oyun_ac(text, integer) from public, anon;
grant execute on function public.oyun_ac(text, integer) to authenticated;

-- 2) Puan: 40 saniyenin çarpanı 1.5
create or replace function public.puan_hesapla(
    p_oyun_tipi text,
    p_kullanici uuid,
    p_oyun_id uuid,
    p_skor integer,
    p_sure_saniye integer,
    p_sure_baslangic timestamptz,
    p_bitis timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    c_can constant integer := 3;
    v_oyun text := split_part(p_oyun_tipi, '_', 1);
    v_zorluk text := split_part(p_oyun_tipi, '_', 2);
    v_skor integer := greatest(coalesce(p_skor, 0), 0);
    v_taban integer;
    v_kusursuz boolean;
    v_kalan_can integer;
    v_zorluk_c numeric;
    v_sure_c numeric;
    v_kalan numeric;
    v_ana integer;
    v_hiz integer := 0;
begin
    -- Top 10 dışındaki oyunlar sadece süreliyse puanlanır
    if v_oyun <> 'top10' and p_sure_saniye is null then
        return jsonb_build_object('puan', null, 'sebep', 'suresiz');
    end if;

    case v_oyun
        when 'kesisim' then
            v_taban := least(v_skor / 2, 5) * 20;
            v_kusursuz := v_skor >= 10;
        when 'bonservis' then
            v_taban := least(v_skor / 2, 5) * 12;
            v_kusursuz := v_skor >= 10;
        when 'izgara' then
            v_kusursuz := v_skor >= 9;
            v_taban := least(v_skor, 9) * 10 + case when v_kusursuz then 10 else 0 end;
        when 'bingo' then
            v_kusursuz := v_skor >= 12;
            v_taban := least(v_skor, 12) * 8 + case when v_kusursuz then 4 else 0 end;
        when 'top10' then
            v_kusursuz := v_skor >= 10;
            select greatest(c_can - count(*), 0)::integer into v_kalan_can
            from public.top10_tahminleri t
            where t.kullanici_id = p_kullanici and t.oyun_id = p_oyun_id and t.sira is null;
            v_taban := least(v_skor, 10) * 10 + case when v_kusursuz then coalesce(v_kalan_can, 0) * 10 else 0 end;
        else
            return jsonb_build_object('puan', null, 'sebep', 'bilinmeyen_oyun');
    end case;

    v_zorluk_c := case
        when v_oyun in ('bingo', 'top10') then 1.5
        when v_zorluk = 'kolay' then 1.0
        when v_zorluk = 'orta' then 1.5
        when v_zorluk = 'zor' then 2.0
        else 1.0                                       -- eski, zorluksuz kesisim/bonservis kayıtları
    end;

    v_sure_c := case p_sure_saniye when 30 then 1.5 when 40 then 1.5 when 60 then 1.25 else 1.0 end;  -- 30: eski kayıtlar

    v_ana := round(v_taban * v_zorluk_c * v_sure_c)::integer;

    if p_sure_saniye is not null and p_sure_baslangic is not null and p_bitis is not null then
        v_kalan := least(p_sure_saniye,
                         greatest(0, p_sure_saniye - extract(epoch from (p_bitis - p_sure_baslangic))));
        -- Hız bonusu sadece kusursuz bitişte
        if v_kusursuz then
            v_hiz := round(v_ana * 0.2 * v_kalan / p_sure_saniye)::integer;
        end if;
    end if;

    return jsonb_build_object(
        'puan', v_ana + v_hiz,
        'taban', v_taban,
        'kusursuz', v_kusursuz,
        'zorluk_carpani', v_zorluk_c,
        'sure_carpani', v_sure_c,
        'sure', p_sure_saniye,
        'kalan_saniye', floor(v_kalan),
        'hiz_bonusu', v_hiz,
        'kalan_can', v_kalan_can);
end;
$$;

revoke execute on function public.puan_hesapla(text, uuid, uuid, integer, integer, timestamptz, timestamptz)
    from public, anon, authenticated;

-- 3) Bingo: süreli oyunda yanlış kutu 2 saniye götürür
create or replace function public.bingo_hamle(p_oyun_id uuid, p_sira integer, p_hucre integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_kullanici uuid := (select auth.uid());
    v_kutu integer;
    v_deste jsonb;
    v_bitis timestamptz;
    v_hamle_sayisi integer;
    v_skor integer;
    v_oyuncu smallint;
    v_eslesme smallint[];
    v_dogru boolean;
    v_bitti boolean;
    v_kalan integer;
    v_siradaki smallint;
begin
    if v_kullanici is null then
        raise exception 'Giriş yapılmamış';
    end if;

    select jsonb_array_length(soru_verisi -> 'hucreler'), soru_verisi -> 'oyuncular' into v_kutu, v_deste
    from public.gunluk_oyunlar
    where id = p_oyun_id
      and (oyun_tipi = 'bingo' or oyun_tipi like 'bingo\_%')
      and tarih <= public.bugunun_tarihi();
    if v_kutu is null then
        raise exception 'Oyun bulunamadı';
    end if;

    -- Kayıt kilitlenir: aynı anda gelen iki hamle sırayla işlenir
    select g.sure_baslangic + make_interval(secs => g.sure_saniye + 3) into v_bitis
    from public.kullanici_oyun_gecmisi g
    where g.kullanici_id = v_kullanici
      and g.oyun_id = p_oyun_id
      and g.durum = 'basladi'
    for update;
    if not found then
        raise exception 'Oyun açık değil';
    end if;

    select count(*), count(*) filter (where dogru) into v_hamle_sayisi, v_skor
    from public.bingo_hamleleri
    where kullanici_id = v_kullanici and oyun_id = p_oyun_id;

    -- Süre dolduysa (3 saniye toleransla) hamle kabul edilmez, oyun o anki skorla biter
    if v_bitis is not null and now() > v_bitis then
        update public.kullanici_oyun_gecmisi
        set skor = v_skor, durum = 'tamamlandi'
        where kullanici_id = v_kullanici and oyun_id = p_oyun_id and durum = 'basladi';

        return jsonb_build_object('dogru', false, 'hucre', null, 'skor', v_skor, 'bitti', true, 'sure_doldu', true,
                                  'siradaki', null, 'siradaki_oyuncu', null);
    end if;

    if p_sira <> v_hamle_sayisi + 1 then
        raise exception 'Sıra hatalı' using hint = 'bingo_sira';
    end if;

    v_oyuncu := public.bingo_siradaki(p_oyun_id, v_kullanici);
    select hucreler into v_eslesme from public.bingo_eslesmeleri where oyun_id = p_oyun_id and sira = v_oyuncu;
    if v_eslesme is null then
        raise exception 'Oyuncu bulunamadı';
    end if;

    if p_hucre is not null then
        if p_hucre < 0 or p_hucre >= v_kutu then
            raise exception 'Geçersiz kutu';
        end if;
        if exists (
            select 1 from public.bingo_hamleleri
            where kullanici_id = v_kullanici and oyun_id = p_oyun_id and hucre = p_hucre and dogru
        ) then
            raise exception 'Kutu dolu' using hint = 'bingo_kutu_dolu';
        end if;

        v_dogru := p_hucre::smallint = any(v_eslesme);
        if not v_dogru then
            -- Yanlış kutu: hamle sayılmaz, oyuncu sırada kalır. Süreli oyunda süreden 2 saniye düşer (043): başlangıç
            -- 2 saniye geri alınır, böylece sürenin dolduğu an, kalan süre ve hız bonusu hep birlikte kısalır.
            if v_bitis is not null then
                update public.kullanici_oyun_gecmisi
                set sure_baslangic = sure_baslangic - interval '2 seconds'
                where kullanici_id = v_kullanici and oyun_id = p_oyun_id and durum = 'basladi'
                returning greatest(0, ceil(extract(epoch from (sure_baslangic + make_interval(secs => sure_saniye) - now())))::integer)
                into v_kalan;

                -- Ceza süreyi bitirdiyse oyun o anki skorla biter
                if v_kalan = 0 then
                    update public.kullanici_oyun_gecmisi
                    set skor = v_skor, durum = 'tamamlandi'
                    where kullanici_id = v_kullanici and oyun_id = p_oyun_id and durum = 'basladi';

                    return jsonb_build_object('dogru', false, 'hucre', p_hucre, 'skor', v_skor, 'bitti', true,
                                              'sure_doldu', true, 'kalan', 0, 'siradaki', null, 'siradaki_oyuncu', null);
                end if;
            end if;
            return jsonb_build_object('dogru', false, 'hucre', p_hucre, 'skor', v_skor, 'bitti', false, 'sure_doldu', false,
                                      'kalan', v_kalan, 'siradaki', v_oyuncu, 'siradaki_oyuncu', v_deste -> (v_oyuncu - 1));
        end if;
    else
        v_dogru := false;
    end if;

    insert into public.bingo_hamleleri (kullanici_id, oyun_id, sira, oyuncu, hucre, dogru)
    values (v_kullanici, p_oyun_id, p_sira, v_oyuncu, p_hucre, v_dogru);

    v_skor := v_skor + v_dogru::integer;

    -- Kart doldu ya da kalan oyuncuların hiçbiri boş kutulara uymuyor
    v_bitti := v_skor = v_kutu or not exists (
        select 1
        from public.bingo_eslesmeleri be
        cross join lateral unnest(be.hucreler) as u(hucre)
        where be.oyun_id = p_oyun_id
          and not exists (
              select 1 from public.bingo_hamleleri bh
              where bh.kullanici_id = v_kullanici and bh.oyun_id = p_oyun_id and bh.dogru and bh.oyuncu = be.sira
          )
          and not exists (
              select 1 from public.bingo_hamleleri bh
              where bh.kullanici_id = v_kullanici and bh.oyun_id = p_oyun_id and bh.dogru and bh.hucre = u.hucre
          )
    );

    update public.kullanici_oyun_gecmisi
    set skor = v_skor,
        durum = case when v_bitti then 'tamamlandi' else durum end
    where kullanici_id = v_kullanici and oyun_id = p_oyun_id and durum = 'basladi';

    if not v_bitti then
        v_siradaki := public.bingo_siradaki(p_oyun_id, v_kullanici);
    end if;

    return jsonb_build_object('dogru', v_dogru, 'hucre', p_hucre, 'skor', v_skor, 'bitti', v_bitti, 'sure_doldu', false,
                              'siradaki', v_siradaki,
                              'siradaki_oyuncu', case when v_siradaki is null then null else v_deste -> (v_siradaki - 1) end);
end;
$$;

revoke execute on function public.bingo_hamle(uuid, integer, integer) from public, anon;
grant execute on function public.bingo_hamle(uuid, integer, integer) to authenticated;

commit;
