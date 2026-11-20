-- 034: Kesişim ve Bonservis'te skor sunucuda hesaplanır
-- Supabase SQL Editor'da tek seferde çalıştırılır. Hata olursa hiçbir değişiklik uygulanmaz.
-- 033_hesabimi_sil.sql'den sonra çalıştırılmalıdır (sırası önemli değil, ikisi bağımsızdır).
--
-- ÖNEMLİ: Bu dosya çalıştırılınca eski uygulama sürümlerinde Kesişim ve Bonservis'in skoru yazılamaz
-- (eskiler skoru kendisi yazıyordu). Yeni sürüm kurulduktan sonra çalıştırılmalıdır.
--
-- Sorun: Kesişim ve Bonservis'te skoru telefon hesaplayıp kullanici_oyun_gecmisi'ne kendisi yazıyordu; isteyen 10/10
-- yazabiliyordu. Bonservis'te tahmin edilecek oyuncunun bedeli de soruyla birlikte telefona geliyordu.
--
-- Düzeltme:
--   1) bonservis_cevaplari: tahmin edilen (sağdaki) oyuncunun bedeli. Uygulamaya kapalıdır, backend yazar.
--      Yeni Bonservis sorularının soru_verisi'nde bu bedel yoktur. Eski oyunlarda bedel soru_verisi'nde durur,
--      fonksiyonlar tablo boşsa oradan okur.
--   2) kesisim_cevap: cevabı kontrol eder, skoru (doğru cevap 2 puan) ve ilerlemeyi yazar, son soruda oyunu bitirir.
--   3) bonservis_tahmin: tahmini kontrol eder, skoru ve ilerlemeyi yazar, tahminden sonra bedeli döndürür.
--   4) bonservis_bedelleri: cevaplanmış soruların bedelleri; oyun bittiyse hepsi (bitiş özeti için).
--   5) oyunu_bitir: süre dolunca uygulama oyunu o anki skorla kapatır. Skora dokunmaz.
--   6) İstemci kullanici_oyun_gecmisi'ni artık güncelleyemez (UPDATE yetkisi ve politikası kaldırıldı).
--      Kayıt açarken sadece boş kayıt açabilir: skor 0, durum 'basladi', ilerleme boş, süre yok.
--      Bütün güncellemeler security definer fonksiyonlarla yapılır (Izgara, Bingo, Top 10 zaten öyleydi).
--
-- Süre: tahmin süre dolduktan sonra gelirse (3 saniye toleransla) kabul edilmez, oyun o anki skorla biter.
-- Sıra: soru index'i ilerlemeyle uyuşmalıdır (aynı soru iki kez cevaplanamaz, soru atlanamaz).

begin;

-- 1) Bonservis cevapları
create table if not exists public.bonservis_cevaplari (
    oyun_id uuid not null references public.gunluk_oyunlar (id) on delete cascade,
    soru_index smallint not null check (soru_index >= 0),
    rakip_bonservis bigint not null,
    primary key (oyun_id, soru_index)
);

alter table public.bonservis_cevaplari enable row level security;

-- Açık kaydı kilitleyip okur; süre dolduysa kaydı kapatır. Sadece bu dosyadaki fonksiyonlar kullanır.
-- Dönüş: kayıt yoksa null; varsa { skor, ilerleme, sure_doldu }
create or replace function public.acik_kaydi_al(p_kullanici uuid, p_oyun_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_kayit record;
begin
    select g.skor, g.ilerleme, g.sure_saniye, g.sure_baslangic into v_kayit
    from public.kullanici_oyun_gecmisi g
    where g.kullanici_id = p_kullanici
      and g.oyun_id = p_oyun_id
      and g.durum = 'basladi'
    for update;
    if not found then
        return null;
    end if;

    if v_kayit.sure_saniye is not null
       and now() > v_kayit.sure_baslangic + make_interval(secs => v_kayit.sure_saniye + 3) then
        update public.kullanici_oyun_gecmisi
        set durum = 'tamamlandi'
        where kullanici_id = p_kullanici and oyun_id = p_oyun_id and durum = 'basladi';
        return jsonb_build_object('skor', v_kayit.skor, 'ilerleme', v_kayit.ilerleme, 'sure_doldu', true);
    end if;

    return jsonb_build_object('skor', v_kayit.skor, 'ilerleme', v_kayit.ilerleme, 'sure_doldu', false);
end;
$$;

revoke execute on function public.acik_kaydi_al(uuid, uuid) from public, anon, authenticated;

-- 2) Kesişim cevabı
--    Dönüş: { dogru, skor, bitti, sure_doldu }
create or replace function public.kesisim_cevap(p_oyun_id uuid, p_soru_index integer, p_oyuncu_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    c_puan constant integer := 2;
    v_kullanici uuid := (select auth.uid());
    v_soru_sayisi integer;
    v_isim text;
    v_kayit jsonb;
    v_ilerleme jsonb;
    v_skor integer;
    v_dogru boolean;
    v_bitti boolean;
begin
    if v_kullanici is null then
        raise exception 'Giriş yapılmamış';
    end if;

    select jsonb_array_length(soru_verisi) into v_soru_sayisi
    from public.gunluk_oyunlar
    where id = p_oyun_id and oyun_tipi like 'kesisim%' and tarih <= public.bugunun_tarihi();
    if v_soru_sayisi is null then
        raise exception 'Oyun bulunamadı';
    end if;

    select isim into v_isim from public.oyuncular where id = p_oyuncu_id;
    if v_isim is null then
        raise exception 'Oyuncu bulunamadı';
    end if;

    v_kayit := public.acik_kaydi_al(v_kullanici, p_oyun_id);
    if v_kayit is null then
        raise exception 'Oyun açık değil';
    end if;
    v_skor := (v_kayit ->> 'skor')::integer;
    v_ilerleme := v_kayit -> 'ilerleme';

    if (v_kayit ->> 'sure_doldu')::boolean then
        return jsonb_build_object('dogru', false, 'skor', v_skor, 'bitti', true, 'sure_doldu', true);
    end if;

    if p_soru_index <> jsonb_array_length(v_ilerleme) or p_soru_index >= v_soru_sayisi then
        raise exception 'Sıra hatalı' using hint = 'soru_sira';
    end if;

    v_dogru := public.kesisim_cevap_kontrol(p_oyun_id, p_soru_index, p_oyuncu_id);
    v_skor := v_skor + case when v_dogru then c_puan else 0 end;
    v_ilerleme := v_ilerleme || jsonb_build_array(jsonb_build_object('dogru', v_dogru, 'cevap', v_isim));
    v_bitti := jsonb_array_length(v_ilerleme) >= v_soru_sayisi;

    update public.kullanici_oyun_gecmisi
    set skor = v_skor,
        ilerleme = v_ilerleme,
        durum = case when v_bitti then 'tamamlandi' else durum end
    where kullanici_id = v_kullanici and oyun_id = p_oyun_id and durum = 'basladi';

    return jsonb_build_object('dogru', v_dogru, 'skor', v_skor, 'bitti', v_bitti, 'sure_doldu', false);
end;
$$;

revoke execute on function public.kesisim_cevap(uuid, integer, uuid) from public, anon;
grant execute on function public.kesisim_cevap(uuid, integer, uuid) to authenticated;

-- Bir Bonservis sorusunun iki bedeli: soldaki görünen oyuncu (soru verisinde) ve sağdaki tahmin edilen
-- (bonservis_cevaplari'nda; eski oyunlarda soru verisinde). Sadece bu dosyadaki fonksiyonlar kullanır.
create or replace function public.bonservis_bedeli(p_oyun_id uuid, p_soru_index integer)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
    select coalesce(
        (select c.rakip_bonservis from public.bonservis_cevaplari c
         where c.oyun_id = p_oyun_id and c.soru_index = p_soru_index),
        (select (g.soru_verisi -> p_soru_index ->> 'oyuncu_b_bonservis')::bigint from public.gunluk_oyunlar g
         where g.id = p_oyun_id));
$$;

revoke execute on function public.bonservis_bedeli(uuid, integer) from public, anon, authenticated;

-- 3) Bonservis tahmini: sağdaki oyuncunun bedeli soldakinden daha fazla mı (p_daha_fazla true) daha az mı
--    Dönüş: { dogru, rakip_bonservis, skor, bitti, sure_doldu }. Süre dolduysa bedel dönmez.
create or replace function public.bonservis_tahmin(p_oyun_id uuid, p_soru_index integer, p_daha_fazla boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    c_puan constant integer := 2;
    v_kullanici uuid := (select auth.uid());
    v_soru jsonb;
    v_soru_sayisi integer;
    v_referans bigint;
    v_rakip bigint;
    v_kayit jsonb;
    v_ilerleme jsonb;
    v_skor integer;
    v_dogru boolean;
    v_bitti boolean;
begin
    if v_kullanici is null then
        raise exception 'Giriş yapılmamış';
    end if;
    if p_daha_fazla is null then
        raise exception 'Tahmin eksik';
    end if;

    select soru_verisi -> p_soru_index, jsonb_array_length(soru_verisi) into v_soru, v_soru_sayisi
    from public.gunluk_oyunlar
    where id = p_oyun_id and oyun_tipi like 'bonservis%' and tarih <= public.bugunun_tarihi();
    if v_soru_sayisi is null then
        raise exception 'Oyun bulunamadı';
    end if;

    v_kayit := public.acik_kaydi_al(v_kullanici, p_oyun_id);
    if v_kayit is null then
        raise exception 'Oyun açık değil';
    end if;
    v_skor := (v_kayit ->> 'skor')::integer;
    v_ilerleme := v_kayit -> 'ilerleme';

    if (v_kayit ->> 'sure_doldu')::boolean then
        return jsonb_build_object('dogru', false, 'rakip_bonservis', null, 'skor', v_skor, 'bitti', true, 'sure_doldu', true);
    end if;

    if v_soru is null or p_soru_index <> jsonb_array_length(v_ilerleme) then
        raise exception 'Sıra hatalı' using hint = 'soru_sira';
    end if;

    v_referans := (v_soru ->> 'oyuncu_a_bonservis')::bigint;
    v_rakip := public.bonservis_bedeli(p_oyun_id, p_soru_index);
    if v_referans is null or v_rakip is null then
        raise exception 'Bedel bulunamadı';
    end if;

    -- Eşit bedelde "daha az" doğru sayılır (uygulamanın eski davranışı)
    v_dogru := p_daha_fazla = (v_rakip > v_referans);
    v_skor := v_skor + case when v_dogru then c_puan else 0 end;
    v_ilerleme := v_ilerleme || jsonb_build_array(jsonb_build_object('dogru', v_dogru));
    v_bitti := jsonb_array_length(v_ilerleme) >= v_soru_sayisi;

    update public.kullanici_oyun_gecmisi
    set skor = v_skor,
        ilerleme = v_ilerleme,
        durum = case when v_bitti then 'tamamlandi' else durum end
    where kullanici_id = v_kullanici and oyun_id = p_oyun_id and durum = 'basladi';

    return jsonb_build_object('dogru', v_dogru, 'rakip_bonservis', v_rakip, 'skor', v_skor, 'bitti', v_bitti,
                              'sure_doldu', false);
end;
$$;

revoke execute on function public.bonservis_tahmin(uuid, integer, boolean) from public, anon;
grant execute on function public.bonservis_tahmin(uuid, integer, boolean) to authenticated;

-- 4) Sağdaki oyuncuların bedelleri: cevaplanmış sorularınkiler her zaman, oyun bittiyse hepsi.
--    Dönüş: [ { soru_index, rakip_bonservis } ]
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

    select jsonb_array_length(soru_verisi) into v_soru_sayisi
    from public.gunluk_oyunlar
    where id = p_oyun_id and oyun_tipi like 'bonservis%';
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

-- 5) Oyunu o anki skorla bitirir (Kesişim ve Bonservis; süre dolunca uygulama çağırır). Skor ve ilerleme değişmez.
--    Kayıt zaten kapalıysa bir şey yapmaz. Dönüş: kayıttaki skor (kayıt yoksa null).
create or replace function public.oyunu_bitir(p_oyun_id uuid)
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

    update public.kullanici_oyun_gecmisi
    set durum = 'tamamlandi'
    where kullanici_id = v_kullanici
      and oyun_id = p_oyun_id
      and durum = 'basladi'
      and (oyun_tipi like 'kesisim%' or oyun_tipi like 'bonservis%');

    select skor into v_skor
    from public.kullanici_oyun_gecmisi
    where kullanici_id = v_kullanici and oyun_id = p_oyun_id;
    return v_skor;
end;
$$;

revoke execute on function public.oyunu_bitir(uuid) from public, anon;
grant execute on function public.oyunu_bitir(uuid) to authenticated;

-- 6) İstemci kaydı artık güncelleyemez, sadece boş kayıt açabilir
drop policy if exists "kullanici_oyun_gecmisi_guncelleme" on public.kullanici_oyun_gecmisi;
revoke update on public.kullanici_oyun_gecmisi from anon, authenticated;

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
    );

commit;
