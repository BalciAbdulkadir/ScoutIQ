-- 046: Izgara'da oyuncu birden fazla boş kutuya uyuyorsa kutuyu kullanıcı seçer
-- Supabase SQL Editor'da tek seferde çalıştırılır. Hata olursa hiçbir değişiklik uygulanmaz.
-- 045_top10_cansiz.sql'den sonra çalıştırılmalıdır. 047_bingo_olu_oyuncu_gelmez.sql bundan sonra çalıştırılır.
-- SIRA: PR birleşir -> bu dosya çalıştırılır -> yeni uygulama sürümü yayınlanır.
-- Yeni uygulama bu dosya olmadan Izgara'da tahmin gönderemez (p_hucre / p_kutu_sor parametreleri yok).
-- Eski uygulama sürümünü bozmaz: eski sürüm izgara_tahmin'i iki parametreyle çağırır, eskisi gibi çalışır
-- (oyuncu en az cevabı olan boş kutuya kendiliğinden yerleşir).
--
-- Ürün sahibinin 27 Kasım 2026 kararı (test geri bildirimi):
--   - Doğru oyuncu tek boş kutuya uyuyorsa oraya kendiliğinden yerleşir.
--   - Birden fazla boş kutuya uyuyorsa uyduğu kutular uygulamada vurgulanır, kullanıcı birini seçer.
--     Seçim beklenirken tahmin sayılmaz (kayıt açılmaz).
--
-- Değişenler:
--   izgara_tahmin : 013'teki gövde (giriş, oyun, kilit, süre ve tekrar kontrolleri aynı), sadece kutu seçimi değişti.
--     Yeni parametreler:
--       p_hucre    : kullanıcının seçtiği kutu (0-8). Oyuncunun uyduğu boş kutulardan biri değilse hata
--                    ('Kutu uygun değil', hint 'izgara_kutu'); uygunsa tahmin o kutuyla kaydedilir.
--       p_kutu_sor : true ve p_hucre boşken oyuncu birden fazla boş kutuya uyuyorsa kayıt yapılmaz, şu döner:
--                    { dogru: false, secim: true, hucreler: [...], hucre: null, tekrar: false, oyuncu_isim, foto_url,
--                      skor, bitti: false, sure_doldu: false }
--     Diğer durumlarda eskisi gibi: en az cevabı olan uygun boş kutu (yoksa yanlış tahmin). Bütün dönüşlere
--     'secim' alanı eklendi (normal cevapta false).
--     İmza değiştiği için eski (uuid, uuid) hâli silinir: iki fonksiyon kalırsa PostgREST iki parametreli çağrıda
--     hangisini seçeceğini bilemez. Eski sürüm aynı adlı parametrelerle yenisini çağırır.
--   Puan sistemi etkilenmez: puan, skor güncellenince sunucuda yazılır (038).
--
-- Kontrol (çalıştırdıktan sonra):
--   select pg_get_function_identity_arguments(oid) from pg_proc where proname = 'izgara_tahmin';
--     -> 1 satır: p_oyun_id uuid, p_oyuncu_id uuid, p_hucre integer, p_kutu_sor boolean
--   select has_function_privilege('anon', 'public.izgara_tahmin(uuid, uuid, integer, boolean)', 'execute');  -> false

begin;

drop function if exists public.izgara_tahmin(uuid, uuid);

create function public.izgara_tahmin(
    p_oyun_id uuid,
    p_oyuncu_id uuid,
    p_hucre integer default null,
    p_kutu_sor boolean default false)
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
    v_hucreler integer[];
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
            'dogru', false, 'secim', false, 'hucre', null, 'tekrar', false, 'oyuncu_isim', v_isim, 'foto_url', v_foto,
            'skor', v_skor, 'bitti', true, 'sure_doldu', true);
    end if;

    -- Aynı oyuncu ikinci kez yazılırsa tahmin sayılmaz
    if exists (
        select 1 from public.izgara_tahminleri
        where kullanici_id = v_kullanici and oyun_id = p_oyun_id and oyuncu_isim = v_isim
    ) then
        return jsonb_build_object(
            'dogru', false, 'secim', false, 'hucre', null, 'tekrar', true, 'oyuncu_isim', v_isim, 'foto_url', v_foto,
            'skor', v_skor, 'bitti', false, 'sure_doldu', false);
    end if;

    -- Oyuncunun uyduğu boş hücrelerin hepsi, en az cevabı olandan başlayarak
    select coalesce(array_agg(h order by (v_tahta -> 'cevap_sayilari' ->> h)::integer, h), '{}')
    into v_hucreler
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
          );

    if p_hucre is not null then
        -- Kullanıcının seçtiği kutu: oyuncunun uyduğu boş kutulardan biri olmalı
        if not (p_hucre = any(v_hucreler)) then
            raise exception 'Kutu uygun değil' using hint = 'izgara_kutu';
        end if;
        v_hucre := p_hucre;
    elsif p_kutu_sor and cardinality(v_hucreler) > 1 then
        -- Birden fazla boş kutuya uyuyor: kayıt yapılmaz, tahmin sayılmaz, kullanıcı kutuyu seçer
        return jsonb_build_object(
            'dogru', false, 'secim', true, 'hucreler', to_jsonb(v_hucreler), 'hucre', null, 'tekrar', false,
            'oyuncu_isim', v_isim, 'foto_url', v_foto, 'skor', v_skor, 'bitti', false, 'sure_doldu', false);
    else
        -- Eski davranış (eski uygulama sürümü ve tek kutuya uyan oyuncu): en az cevabı olan kutu, yoksa yanlış
        v_hucre := v_hucreler[1];
    end if;

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
        'dogru', v_hucre is not null, 'secim', false, 'hucre', v_hucre, 'tekrar', false, 'oyuncu_isim', v_isim, 'foto_url', v_foto,
        'skor', v_skor, 'bitti', v_bitti, 'sure_doldu', false);
end;
$$;

revoke execute on function public.izgara_tahmin(uuid, uuid, integer, boolean) from public, anon;
grant execute on function public.izgara_tahmin(uuid, uuid, integer, boolean) to authenticated;

commit;
