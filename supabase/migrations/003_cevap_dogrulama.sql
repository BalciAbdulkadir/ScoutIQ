-- 003: Tarih ve cevap doğrulama fonksiyonları, oyun kaydının güncellenmesi
-- Supabase SQL Editor'da tek seferde çalıştırılır. Hata olursa hiçbir değişiklik uygulanmaz.

begin;

-- 1) Türkiye saatine göre bugünün tarihi.
--    Uygulama telefonun saatine güvenmez, oyun günü her yerde aynıdır.
create or replace function public.bugunun_tarihi()
returns date
language sql
stable
set search_path = ''
as $$
    select (now() at time zone 'Europe/Istanbul')::date;
$$;

revoke execute on function public.bugunun_tarihi() from public, anon;
grant execute on function public.bugunun_tarihi() to authenticated;

-- 2) İsimleri karşılaştırmak için sadeleştirir: büyük/küçük harf, Türkçe ve aksanlı harfler,
--    boşluk, tire ve kesme işareti fark etmez. "N'Golo Kanté" ve "ngolo kante" eşit sayılır.
create extension if not exists unaccent with schema extensions;

create or replace function public.isim_sadelestir(p_isim text)
returns text
language sql
immutable
set search_path = ''
as $$
    select regexp_replace(
        lower(extensions.unaccent('extensions.unaccent'::regdictionary, coalesce(p_isim, ''))),
        '[^a-z0-9]', '', 'g'
    );
$$;

-- 3) Kesişim cevabını sunucuda kontrol eder.
--    kariyer_gecmisi uygulamaya kapalı olduğu için security definer ile çalışır.
--    Kulüpler istemciden alınmaz, oyunun kendi sorusundan okunur: böylece fonksiyon
--    rastgele kulüp çiftlerini sorgulamak için kullanılamaz ve yarının sorularına erişilemez.
create or replace function public.kesisim_cevap_kontrol(p_oyun_id uuid, p_soru_index integer, p_cevap text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_soru jsonb;
    v_cevap text := public.isim_sadelestir(p_cevap);
begin
    if (select auth.uid()) is null then
        raise exception 'Giriş yapılmamış';
    end if;

    if v_cevap = '' then
        return false;
    end if;

    select soru_verisi -> p_soru_index into v_soru
    from public.gunluk_oyunlar
    where id = p_oyun_id
      and oyun_tipi = 'kesisim'
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
          and public.isim_sadelestir(o.isim) = v_cevap
    );
end;
$$;

revoke execute on function public.kesisim_cevap_kontrol(uuid, integer, text) from public, anon;
grant execute on function public.kesisim_cevap_kontrol(uuid, integer, text) to authenticated;

-- 4) Günde tek atış: bir kullanıcının aynı gün aynı oyun için tek kaydı olabilir.
create unique index if not exists kullanici_oyun_gecmisi_gunluk_tek_idx
    on kullanici_oyun_gecmisi (kullanici_id, oyun_tipi, tarih);

-- 5) Oyun kaydı oyun başlarken 'basladi' olarak atılır, bitince güncellenir.
--    Sadece kendi 'basladi' durumundaki kaydı güncellenebilir; 'tamamlandi' olduktan sonra kilitlenir.
--    Sadece skor ve durum değiştirilebilir, kullanıcı/tarih/oyun bilgisi değiştirilemez.
--    Gece yarısını geçen oyun bitirilebilsin diye tarih şartı yok (tarih zaten değiştirilemez).
create policy "kullanici_oyun_gecmisi_guncelleme" on kullanici_oyun_gecmisi
    for update to authenticated
    using (kullanici_id = (select auth.uid()) and durum = 'basladi')
    with check (kullanici_id = (select auth.uid()));

revoke update on kullanici_oyun_gecmisi from anon, authenticated;
grant update (skor, durum) on kullanici_oyun_gecmisi to authenticated;

commit;
