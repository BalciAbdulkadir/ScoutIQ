-- 011: 3x3 Izgara oyunu
-- Supabase SQL Editor'da tek seferde çalıştırılır. Hata olursa hiçbir değişiklik uygulanmaz.
-- 009_milli_takim_kariyeri.sql'den sonra çalıştırılmalıdır (milli takım başlıkları milli_takim_kariyeri'ni kullanır).
--
-- Kurallar:
--   - Kolay, orta ve zor ayrı oyunlardır (izgara_kolay, izgara_orta, izgara_zor), her biri günde bir kez oynanır.
--   - Toplam 9 tahmin hakkı vardır; doğru ya da yanlış her tahmin bir hak yer.
--   - Kullanıcı hücre seçmez: yazdığı oyuncu boş bir hücreye uyuyorsa oraya yerleşir.
--     Birden fazla boş hücreye uyuyorsa en az cevabı olan (en zor) hücreye yerleşir.
--   - Aynı oyuncu bir tahtada iki kez kullanılamaz; tekrar yazılırsa hak yemez.
--   - Skor dolu hücre sayısıdır (0-9). Pes edilirse oyun o anki skorla biter.
-- Tahminler sunucuda tutulur: uygulama kapanıp açılsa da haklar ve dolu hücreler kaybolmaz, skor istemciden alınmaz.
--
-- gunluk_oyunlar.soru_verisi biçimi (backend DailyQuestionJob üretir):
--   { "satirlar": [baslik x3], "sutunlar": [baslik x3], "cevap_sayilari": [9 sayı, hücre = satır * 3 + sütun] }
--   baslik: { "tip": "kulup", "id": <kulüp uuid>, "tm_id", "isim", "logo" } ya da { "tip": "milli", "tm_id", "isim" }

begin;

-- 1) Yeni oyun tipleri
alter table gunluk_oyunlar drop constraint gunluk_oyunlar_oyun_tipi_check;
alter table gunluk_oyunlar add constraint gunluk_oyunlar_oyun_tipi_check
    check (oyun_tipi in ('kesisim', 'bonservis', 'izgara_kolay', 'izgara_orta', 'izgara_zor'));

alter table kullanici_oyun_gecmisi drop constraint kullanici_oyun_gecmisi_oyun_tipi_check;
alter table kullanici_oyun_gecmisi add constraint kullanici_oyun_gecmisi_oyun_tipi_check
    check (oyun_tipi in ('kesisim', 'bonservis', 'izgara_kolay', 'izgara_orta', 'izgara_zor'));

-- 2) Kullanıcının bir tahtadaki tahminleri. hucre null: yanlış tahmin.
--    Satırlar sadece izgara_tahmin fonksiyonuyla eklenir; kullanıcı kendi tahminlerini okuyabilir.
create table public.izgara_tahminleri (
    id uuid primary key default gen_random_uuid(),
    kullanici_id uuid not null,
    oyun_id uuid not null references public.gunluk_oyunlar (id) on delete cascade,
    sira smallint not null check (sira between 1 and 9),
    oyuncu_id uuid not null references public.oyuncular (id) on delete cascade,
    oyuncu_isim text not null,
    hucre smallint check (hucre between 0 and 8),
    olusturma_zamani timestamptz not null default now(),
    unique (kullanici_id, oyun_id, sira),
    unique (kullanici_id, oyun_id, hucre)
);

alter table public.izgara_tahminleri enable row level security;

create policy "izgara_tahminleri_okuma" on public.izgara_tahminleri
    for select to authenticated
    using (kullanici_id = (select auth.uid()));

-- 3) Bir başlığa (kulüp ya da milli takım) uyan oyuncular. Sadece aşağıdaki fonksiyonların içinden çağrılır:
--    kariyer verisi uygulamaya kapalı olduğu için istemciye açılmaz.
create or replace function public.izgara_baslik_oyunculari(p_baslik jsonb)
returns setof uuid
language sql
stable
set search_path = ''
as $$
    select k.oyuncu_id
    from public.kariyer_gecmisi k
    where p_baslik ->> 'tip' = 'kulup'
      and k.kulup_id = (p_baslik ->> 'id')::uuid
    union
    select m.oyuncu_id
    from public.milli_takim_kariyeri m
    where p_baslik ->> 'tip' = 'milli'
      and m.milli_takim_tm_id = p_baslik ->> 'tm_id';
$$;

revoke execute on function public.izgara_baslik_oyunculari(jsonb) from public, anon, authenticated;

-- 4) Tahmin. Listeden seçilen oyuncunun id'sini alır, oyuncuyu uygun boş hücreye yerleştirir.
--    Oyun kaydı (kullanici_oyun_gecmisi) uygulama tarafından 'basladi' olarak açılmış olmalıdır.
--    Listede aynı isimli oyuncular tek satır olduğu için, Kesişim'deki gibi isim eşleşmesi yeterli sayılır.
--    Dönüş: { dogru, hucre, tekrar, oyuncu_isim, foto_url, kalan_hak, skor, bitti }
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
    v_kalan integer;
    v_bitti boolean;
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

    -- Kayıt kilitlenir: aynı anda gelen iki tahmin sırayla işlenir, hak sayısı aşılamaz
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

    if v_tahmin_sayisi >= 9 then
        raise exception 'Tahmin hakkı kalmadı';
    end if;

    -- Aynı oyuncu ikinci kez yazılırsa hak yemez
    if exists (
        select 1 from public.izgara_tahminleri
        where kullanici_id = v_kullanici and oyun_id = p_oyun_id and oyuncu_isim = v_isim
    ) then
        return jsonb_build_object(
            'dogru', false, 'hucre', null, 'tekrar', true, 'oyuncu_isim', v_isim, 'foto_url', v_foto,
            'kalan_hak', 9 - v_tahmin_sayisi, 'skor', v_skor, 'bitti', false);
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
    v_kalan := 9 - (v_tahmin_sayisi + 1);
    v_bitti := v_kalan = 0 or v_skor = 9;

    update public.kullanici_oyun_gecmisi
    set skor = v_skor,
        durum = case when v_bitti then 'tamamlandi' else durum end
    where kullanici_id = v_kullanici
      and oyun_id = p_oyun_id
      and durum = 'basladi';

    return jsonb_build_object(
        'dogru', v_hucre is not null, 'hucre', v_hucre, 'tekrar', false, 'oyuncu_isim', v_isim, 'foto_url', v_foto,
        'kalan_hak', v_kalan, 'skor', v_skor, 'bitti', v_bitti);
end;
$$;

revoke execute on function public.izgara_tahmin(uuid, uuid) from public, anon;
grant execute on function public.izgara_tahmin(uuid, uuid) to authenticated;

-- 5) Pes etme: oyun o anki skorla (dolu hücre sayısı) biter
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

-- 6) Oyun bitince her hücre için örnek bir doğru cevap (boş kalan hücrelerde gösterilir).
--    Kesişim'deki gibi sadece oyunu bitirmiş kullanıcıya döner ve en tanınmış oyuncu
--    (toplam bonservisi en yüksek, eşitlikte isim sırası) seçilir.
create or replace function public.izgara_ornek_cevaplar(p_oyun_id uuid)
returns table (hucre integer, oyuncu_isim text)
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

    select soru_verisi into v_tahta
    from public.gunluk_oyunlar
    where id = p_oyun_id and oyun_tipi like 'izgara\_%';

    return query
    select h,
           (
               select o.isim::text
               from public.izgara_baslik_oyunculari(v_tahta -> 'satirlar' -> (h / 3)) s(oyuncu_id)
               join public.izgara_baslik_oyunculari(v_tahta -> 'sutunlar' -> (h % 3)) u(oyuncu_id) using (oyuncu_id)
               join public.oyuncular o on o.id = s.oyuncu_id
               order by o.toplam_bonservis desc, o.isim
               limit 1
           )
    from generate_series(0, 8) as h
    where v_tahta is not null;
end;
$$;

revoke execute on function public.izgara_ornek_cevaplar(uuid) from public, anon;
grant execute on function public.izgara_ornek_cevaplar(uuid) to authenticated;

commit;
