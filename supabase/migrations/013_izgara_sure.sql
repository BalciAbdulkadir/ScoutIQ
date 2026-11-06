-- 013: Izgara'ya süre, tahmin hakkı sınırının kaldırılması
-- Supabase SQL Editor'da tek seferde çalıştırılır. Hata olursa hiçbir değişiklik uygulanmaz.
-- 011_izgara.sql'den sonra çalıştırılmalıdır.
--
-- Kurallar:
--   - Oyuncu tahtaya başlarken süre seçer: süre yok, 30, 60 ya da 90 saniye. Süre bütün tahta içindir.
--   - Başlangıç zamanı sunucuda tutulur: uygulama kapatılıp açılsa da süre işlemeye devam eder.
--   - Süre seçimi bir kez yapılır, sonradan değiştirilemez.
--   - Süre dolduktan sonra gelen tahmin kabul edilmez, oyun o anki skorla biter.
--     Ağ gecikmesi yüzünden son saniyedeki tahmin yanmasın diye 3 saniye tolerans vardır.
--   - Tahmin hakkı sınırı yoktur (011'deki 9 hak kaldırıldı). Oyun dokuz kutu dolunca,
--     pes edilince ya da süre dolunca biter. Dönüşteki 'kalan_hak' alanı kaldırıldı.

begin;

-- 0) Tahmin sırası artık 9 ile sınırlı değil
alter table public.izgara_tahminleri drop constraint if exists izgara_tahminleri_sira_check;
alter table public.izgara_tahminleri add constraint izgara_tahminleri_sira_check check (sira >= 1);

-- 1) Süreli tahtalar. Süresiz oynanan tahtanın satırı yoktur.
--    Satırlar sadece izgara_sureyi_baslat fonksiyonuyla eklenir; kullanıcı kendi satırlarını okuyabilir.
create table public.izgara_sureleri (
    kullanici_id uuid not null,
    oyun_id uuid not null references public.gunluk_oyunlar (id) on delete cascade,
    sure_saniye smallint not null check (sure_saniye in (30, 60, 90)),
    baslangic timestamptz not null default now(),
    primary key (kullanici_id, oyun_id)
);

alter table public.izgara_sureleri enable row level security;

create policy "izgara_sureleri_okuma" on public.izgara_sureleri
    for select to authenticated
    using (kullanici_id = (select auth.uid()));

-- 2) Süreyi başlatır, { "sure": toplam saniye, "kalan": kalan saniye } döndürür (süresiz tahtada null).
--    p_sure null ise sadece kalan süre sorulur: uygulama yarım kalan tahtayı açarken böyle çağırır.
--    Süre zaten başlatılmışsa yeni süre yok sayılır, saat sıfırlanmaz.
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

-- 3) Tahmin: 011'deki fonksiyonun aynısı, iki farkla: süre dolduysa tahmin kabul edilmez ve oyun biter;
--    tahmin hakkı sınırı yoktur. Dönüş: { dogru, hucre, tekrar, oyuncu_isim, foto_url, skor, bitti, sure_doldu }
create or replace function public.izgara_tahmin(p_oyun_id uuid, p_oyuncu_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_kullanici uuid := (select auth.uid());
    v_isim text;
    v_foto text;
    v_tahta jsonb;
    v_tahmin_sayisi integer;
    v_hucre integer;
    v_skor integer;
    v_bitti boolean;
    v_bitis timestamptz;
begin
    if v_kullanici is null then
        raise exception 'Giriş yapılmamış';
    end if;

    select isim, foto_url into v_isim, v_foto from public.oyuncular where id = p_oyuncu_id;
    if v_isim is null then
        raise exception 'Oyuncu bulunamadı';
    end if;

    select soru_verisi into v_tahta
    from public.gunluk_oyunlar
    where id = p_oyun_id
      and oyun_tipi like 'izgara\_%'
      and tarih <= public.bugunun_tarihi();
    if v_tahta is null then
        raise exception 'Oyun bulunamadı';
    end if;

    -- Kayıt kilitlenir: aynı anda gelen iki tahmin sırayla işlenir
    perform 1
    from public.kullanici_oyun_gecmisi
    where kullanici_id = v_kullanici
      and oyun_id = p_oyun_id
      and durum = 'basladi'
    for update;
    if not found then
        raise exception 'Oyun açık değil';
    end if;

    select count(*), count(hucre) into v_tahmin_sayisi, v_skor
    from public.izgara_tahminleri
    where kullanici_id = v_kullanici and oyun_id = p_oyun_id;

    -- Süre dolduysa (3 saniye toleransla) tahmin kabul edilmez, oyun o anki skorla biter
    select s.baslangic + make_interval(secs => s.sure_saniye + 3) into v_bitis
    from public.izgara_sureleri s
    where s.kullanici_id = v_kullanici and s.oyun_id = p_oyun_id;

    if v_bitis is not null and now() > v_bitis then
        update public.kullanici_oyun_gecmisi
        set skor = v_skor, durum = 'tamamlandi'
        where kullanici_id = v_kullanici
          and oyun_id = p_oyun_id
          and durum = 'basladi';

        return jsonb_build_object(
            'dogru', false, 'hucre', null, 'tekrar', false, 'oyuncu_isim', v_isim, 'foto_url', v_foto,
            'skor', v_skor, 'bitti', true, 'sure_doldu', true);
    end if;

    -- Aynı oyuncu ikinci kez yazılırsa tahmin sayılmaz
    if exists (
        select 1 from public.izgara_tahminleri
        where kullanici_id = v_kullanici and oyun_id = p_oyun_id and oyuncu_isim = v_isim
    ) then
        return jsonb_build_object(
            'dogru', false, 'hucre', null, 'tekrar', true, 'oyuncu_isim', v_isim, 'foto_url', v_foto,
            'skor', v_skor, 'bitti', false, 'sure_doldu', false);
    end if;

    -- Oyuncunun uyduğu boş hücrelerden en az cevabı olanı
    select h into v_hucre
    from generate_series(0, 8) as h
    where not exists (
              select 1 from public.izgara_tahminleri t
              where t.kullanici_id = v_kullanici and t.oyun_id = p_oyun_id and t.hucre = h
          )
      and exists (
              select 1
              from public.izgara_baslik_oyunculari(v_tahta -> 'satirlar' -> (h / 3)) s(oyuncu_id)
              join public.izgara_baslik_oyunculari(v_tahta -> 'sutunlar' -> (h % 3)) u(oyuncu_id) using (oyuncu_id)
              join public.oyuncular o on o.id = s.oyuncu_id
              where o.isim = v_isim
          )
    order by (v_tahta -> 'cevap_sayilari' ->> h)::integer, h
    limit 1;

    insert into public.izgara_tahminleri (kullanici_id, oyun_id, sira, oyuncu_id, oyuncu_isim, hucre)
    values (v_kullanici, p_oyun_id, v_tahmin_sayisi + 1, p_oyuncu_id, v_isim, v_hucre);

    v_skor := v_skor + (v_hucre is not null)::integer;
    v_bitti := v_skor = 9;

    update public.kullanici_oyun_gecmisi
    set skor = v_skor,
        durum = case when v_bitti then 'tamamlandi' else durum end
    where kullanici_id = v_kullanici
      and oyun_id = p_oyun_id
      and durum = 'basladi';

    return jsonb_build_object(
        'dogru', v_hucre is not null, 'hucre', v_hucre, 'tekrar', false, 'oyuncu_isim', v_isim, 'foto_url', v_foto,
        'skor', v_skor, 'bitti', v_bitti, 'sure_doldu', false);
end;
$$;

revoke execute on function public.izgara_tahmin(uuid, uuid) from public, anon;
grant execute on function public.izgara_tahmin(uuid, uuid) to authenticated;

commit;
