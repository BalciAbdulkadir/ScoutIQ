-- 020: Bingo
-- Supabase SQL Editor'da tek seferde çalıştırılır. Hata olursa hiçbir değişiklik uygulanmaz.
-- 019_zorluk_modlari.sql'den sonra çalıştırılmalıdır.
--
-- Kurallar:
--   - Kart 4x4'tür (16 kategori: kulüp, milli takım, lig, başarı), deste 20 oyuncudur. Oyuncular sırayla gelir.
--   - Kullanıcı gelen oyuncuyu bir kutuya koyar ya da pas geçer. Oyuncu kutuya uyuyorsa kutu dolar; uymuyorsa oyuncu yanar.
--     Dolu kutuya oyuncu konamaz. Pas geçilen oyuncu da yanar, ceza yoktur.
--   - Oyun 16 kutu dolunca, deste bitince, pes edilince ya da süre dolunca biter. Skor dolu kutu sayısıdır.
--   - Kolay, orta ve zor ayrı günlük oyundur (bingo_kolay, bingo_orta, bingo_zor); kullanıcı günde birini oynar (019'daki tetikleyici).
--   - Süre seçimi Kesişim ve Bonservis'teki gibidir (018_oyun_devam.sql): kayıtta tutulur, oyundan çıkınca işlemeye devam eder.
--     Ağ gecikmesi yüzünden son saniyedeki hamle yanmasın diye 3 saniye tolerans vardır.
--   - Hangi oyuncunun hangi kutuya uyduğu soru verisinde yoktur; backend bingo_eslesmeleri tablosuna yazar,
--     hamleler sunucuda bu tabloya göre kontrol edilir.

begin;

-- 1) Yeni oyun tipleri
alter table public.gunluk_oyunlar drop constraint gunluk_oyunlar_oyun_tipi_check;
alter table public.gunluk_oyunlar add constraint gunluk_oyunlar_oyun_tipi_check
    check (oyun_tipi in ('kesisim', 'bonservis',
                         'kesisim_kolay', 'kesisim_orta', 'kesisim_zor',
                         'bonservis_kolay', 'bonservis_orta', 'bonservis_zor',
                         'izgara_kolay', 'izgara_orta', 'izgara_zor',
                         'bingo_kolay', 'bingo_orta', 'bingo_zor'));

alter table public.kullanici_oyun_gecmisi drop constraint kullanici_oyun_gecmisi_oyun_tipi_check;
alter table public.kullanici_oyun_gecmisi add constraint kullanici_oyun_gecmisi_oyun_tipi_check
    check (oyun_tipi in ('kesisim', 'bonservis',
                         'kesisim_kolay', 'kesisim_orta', 'kesisim_zor',
                         'bonservis_kolay', 'bonservis_orta', 'bonservis_zor',
                         'izgara_kolay', 'izgara_orta', 'izgara_zor',
                         'bingo_kolay', 'bingo_orta', 'bingo_zor'));

-- 2) Destedeki her oyuncunun uyduğu kutular (0-15). Uygulamaya kapalıdır (politika yok), backend yazar.
create table public.bingo_eslesmeleri (
    oyun_id uuid not null references public.gunluk_oyunlar (id) on delete cascade,
    sira smallint not null check (sira >= 1),
    hucreler smallint[] not null,
    primary key (oyun_id, sira)
);

alter table public.bingo_eslesmeleri enable row level security;

-- 3) Kullanıcının hamleleri, sırayla. hucre null: pas. Satırlar sadece bingo_hamle fonksiyonuyla eklenir;
--    kullanıcı kendi hamlelerini okuyabilir (yarım kalan oyun bunlarla kurulur).
create table public.bingo_hamleleri (
    kullanici_id uuid not null,
    oyun_id uuid not null references public.gunluk_oyunlar (id) on delete cascade,
    sira smallint not null check (sira >= 1),
    hucre smallint check (hucre between 0 and 15),
    dogru boolean not null,
    created_at timestamptz not null default now(),
    primary key (kullanici_id, oyun_id, sira)
);

alter table public.bingo_hamleleri enable row level security;

create policy "bingo_hamleleri_okuma" on public.bingo_hamleleri
    for select to authenticated
    using (kullanici_id = (select auth.uid()));

-- 4) Hamle: destedeki p_sira. oyuncuyu p_hucre kutusuna koyar, p_hucre null ise pas geçer.
--    Sıra, kullanıcının bir sonraki oyuncusu olmalıdır. Dönüş: { dogru, hucre, skor, bitti, sure_doldu }
create or replace function public.bingo_hamle(p_oyun_id uuid, p_sira integer, p_hucre integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_kullanici uuid := (select auth.uid());
    v_bitis timestamptz;
    v_hamle_sayisi integer;
    v_skor integer;
    v_eslesme smallint[];
    v_deste integer;
    v_dogru boolean;
    v_bitti boolean;
begin
    if v_kullanici is null then
        raise exception 'Giriş yapılmamış';
    end if;

    if not exists (
        select 1 from public.gunluk_oyunlar
        where id = p_oyun_id and oyun_tipi like 'bingo\_%' and tarih <= public.bugunun_tarihi()
    ) then
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

        return jsonb_build_object('dogru', false, 'hucre', null, 'skor', v_skor, 'bitti', true, 'sure_doldu', true);
    end if;

    if p_sira <> v_hamle_sayisi + 1 then
        raise exception 'Sıra hatalı' using hint = 'bingo_sira';
    end if;

    select hucreler into v_eslesme from public.bingo_eslesmeleri where oyun_id = p_oyun_id and sira = p_sira;
    if v_eslesme is null then
        raise exception 'Oyuncu bulunamadı';
    end if;

    if p_hucre is null then
        v_dogru := false;
    else
        if p_hucre < 0 or p_hucre > 15 then
            raise exception 'Geçersiz kutu';
        end if;
        if exists (
            select 1 from public.bingo_hamleleri
            where kullanici_id = v_kullanici and oyun_id = p_oyun_id and hucre = p_hucre and dogru
        ) then
            raise exception 'Kutu dolu' using hint = 'bingo_kutu_dolu';
        end if;
        v_dogru := p_hucre::smallint = any(v_eslesme);
    end if;

    insert into public.bingo_hamleleri (kullanici_id, oyun_id, sira, hucre, dogru)
    values (v_kullanici, p_oyun_id, p_sira, p_hucre, v_dogru);

    select count(*) into v_deste from public.bingo_eslesmeleri where oyun_id = p_oyun_id;
    v_skor := v_skor + v_dogru::integer;
    v_bitti := v_skor = 16 or p_sira >= v_deste;

    update public.kullanici_oyun_gecmisi
    set skor = v_skor,
        durum = case when v_bitti then 'tamamlandi' else durum end
    where kullanici_id = v_kullanici and oyun_id = p_oyun_id and durum = 'basladi';

    return jsonb_build_object('dogru', v_dogru, 'hucre', p_hucre, 'skor', v_skor, 'bitti', v_bitti, 'sure_doldu', false);
end;
$$;

revoke execute on function public.bingo_hamle(uuid, integer, integer) from public, anon;
grant execute on function public.bingo_hamle(uuid, integer, integer) to authenticated;

-- 5) Pes et: oyunu o anki skorla bitirir, skoru döndürür
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

    select count(*) filter (where dogru) into v_skor
    from public.bingo_hamleleri
    where kullanici_id = v_kullanici and oyun_id = p_oyun_id;

    update public.kullanici_oyun_gecmisi
    set skor = v_skor, durum = 'tamamlandi'
    where kullanici_id = v_kullanici
      and oyun_id = p_oyun_id
      and oyun_tipi like 'bingo\_%'
      and durum = 'basladi';

    return v_skor;
end;
$$;

revoke execute on function public.bingo_pes_et(uuid) from public, anon;
grant execute on function public.bingo_pes_et(uuid) to authenticated;

-- 6) Oyun bitince boş kalan her kutu için desteden ona uyan ilk oyuncu. Sadece oyunu bitirmiş kullanıcıya döner,
--    böylece fonksiyon cevaplara önceden bakmak için kullanılamaz.
create or replace function public.bingo_ornek_cevaplar(p_oyun_id uuid)
returns table (hucre integer, oyuncu_isim text, foto_url text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_kullanici uuid := (select auth.uid());
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

    return query
    select h::integer,
           (go.soru_verisi -> 'oyuncular' -> (e.sira - 1) ->> 'isim'),
           (go.soru_verisi -> 'oyuncular' -> (e.sira - 1) ->> 'foto')
    from generate_series(0, 15) as h
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

-- 7) Süre: 019'daki fonksiyonun aynısı, tek farkı Bingo'nun oyun tiplerini de kabul etmesi
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

    if p_oyun_tipi not in ('kesisim', 'bonservis',
                           'kesisim_kolay', 'kesisim_orta', 'kesisim_zor',
                           'bonservis_kolay', 'bonservis_orta', 'bonservis_zor',
                           'bingo_kolay', 'bingo_orta', 'bingo_zor') then
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

commit;
