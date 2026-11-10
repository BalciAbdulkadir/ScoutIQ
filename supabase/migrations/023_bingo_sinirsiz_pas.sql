-- 023: Bingo'da sınırsız pas, pas geçilen oyuncu tekrar gelir
-- Supabase SQL Editor'da tek seferde çalıştırılır. Hata olursa hiçbir değişiklik uygulanmaz.
-- 021_bingo_tek_mod.sql'den sonra çalıştırılmalıdır.
--
-- Kurallar:
--   - Deste 32 oyuncudur (backend seçer): kartı dolduran 12, en az bir kutuya uyan 16 ve hiçbir kutuya uymayan 4 oyuncu.
--   - Pas sınırsızdır. Destede sıra döner: pas geçilen oyuncu destenin sonuna gider, sırası gelince tekrar gelir.
--     Kutuya yerleşen oyuncu bir daha gelmez.
--   - Sıradaki oyuncu: son gelen oyuncudan sonraki, henüz yerleşmemiş ilk oyuncu (destenin sonundan başa döner).
--   - Oyun bütün kutular dolunca, pes edilince ya da süre dolunca biter. Kalan oyuncuların hiçbiri boş kutulara
--     uymuyorsa da biter (kart artık doldurulamaz, sonsuza kadar pas geçilmesin).
--   - Hamle sayısı (sira) artık destedeki sırayla aynı değildir: her hamlede gelen oyuncu, oyuncu kolonunda tutulur.

begin;

-- 1) Hamlede gelen oyuncu: destedeki sırası (1'den başlar). Eski hamlelerde ikisi aynıydı.
alter table public.bingo_hamleleri add column if not exists oyuncu smallint;
update public.bingo_hamleleri set oyuncu = sira where oyuncu is null;
alter table public.bingo_hamleleri alter column oyuncu set not null;
alter table public.bingo_hamleleri add constraint bingo_hamleleri_oyuncu_check check (oyuncu >= 1);

-- 2) Sıradaki oyuncu (destedeki sırası); kart dolduysa ya da yerleşmemiş oyuncu kalmadıysa null.
--    Sadece bu dosyadaki fonksiyonlar kullanır, uygulamaya kapalıdır.
create or replace function public.bingo_siradaki(p_oyun_id uuid, p_kullanici uuid)
returns smallint
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_son integer;
    v_deste integer;
    v_siradaki smallint;
begin
    select oyuncu into v_son
    from public.bingo_hamleleri
    where kullanici_id = p_kullanici and oyun_id = p_oyun_id
    order by sira desc
    limit 1;
    v_son := coalesce(v_son, 0);

    select count(*) into v_deste from public.bingo_eslesmeleri where oyun_id = p_oyun_id;

    -- Son oyuncudan sonraki ilk yerleşmemiş oyuncu; destenin sonundan başa dönülür
    select be.sira into v_siradaki
    from public.bingo_eslesmeleri be
    where be.oyun_id = p_oyun_id
      and not exists (
          select 1 from public.bingo_hamleleri bh
          where bh.kullanici_id = p_kullanici and bh.oyun_id = p_oyun_id and bh.dogru and bh.oyuncu = be.sira
      )
    order by (be.sira - v_son - 1 + v_deste) % v_deste
    limit 1;

    return v_siradaki;
end;
$$;

revoke execute on function public.bingo_siradaki(uuid, uuid) from public, anon, authenticated;

-- 3) Hamle: p_sira kullanıcının kaçıncı hamlesi olduğudur (1'den başlar). Hamle sıradaki oyuncu için yapılır;
--    p_hucre null ise pas geçilir. Yanlış kutu kaydedilmez, oyuncu sırada kalır.
--    Dönüş: { dogru, hucre, skor, bitti, sure_doldu, siradaki } (siradaki: sıradaki oyuncunun destedeki sırası)
create or replace function public.bingo_hamle(p_oyun_id uuid, p_sira integer, p_hucre integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_kullanici uuid := (select auth.uid());
    v_kutu integer;
    v_bitis timestamptz;
    v_hamle_sayisi integer;
    v_skor integer;
    v_oyuncu smallint;
    v_eslesme smallint[];
    v_dogru boolean;
    v_bitti boolean;
begin
    if v_kullanici is null then
        raise exception 'Giriş yapılmamış';
    end if;

    select jsonb_array_length(soru_verisi -> 'hucreler') into v_kutu
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
                                  'siradaki', null);
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
            -- Yanlış kutu: hamle sayılmaz, oyuncu sırada kalır
            return jsonb_build_object('dogru', false, 'hucre', p_hucre, 'skor', v_skor, 'bitti', false, 'sure_doldu', false,
                                      'siradaki', v_oyuncu);
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

    return jsonb_build_object('dogru', v_dogru, 'hucre', p_hucre, 'skor', v_skor, 'bitti', v_bitti, 'sure_doldu', false,
                              'siradaki', case when v_bitti then null else public.bingo_siradaki(p_oyun_id, v_kullanici) end);
end;
$$;

revoke execute on function public.bingo_hamle(uuid, integer, integer) from public, anon;
grant execute on function public.bingo_hamle(uuid, integer, integer) to authenticated;

commit;
