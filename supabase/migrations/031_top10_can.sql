-- 031: Top 10'da 3 can
-- Supabase SQL Editor'da tek seferde çalıştırılır. Hata olursa hiçbir değişiklik uygulanmaz.
-- 030_ayni_isim_en_bilinen.sql'den sonra çalıştırılmalıdır (top10_tahmin'in 030'daki hâli üzerine kurulur).
--
-- Kurallar (ürün sahibinin 17 Kasım 2026 kararı):
--   - Kullanıcının 3 canı vardır. Listede olmayan oyuncuyu tahmin etmek bir can götürür.
--   - Daha önce denenmiş oyuncu (doğru ya da yanlış) tahmin sayılmaz, can da götürmez.
--   - Üçüncü yanlış tahminde oyun o anki skorla (bulunan oyuncu sayısı) biter.
--   - Kalan can, kullanıcının yanlış tahminlerinden (top10_tahminleri'nde sira null satırlar) hesaplanır;
--     ayrı bir kolon tutulmaz. Oyundan çıkıp girince canlar aynı kalır.
--   - Oyun yine 10 oyuncu bulununca ya da pes edilince de biter.
--
-- top10_tahmin dönüşüne 'kalan_can' eklendi: { dogru, sira, deger, tekrar, oyuncu_isim, foto_url, skor, kalan_can, bitti }

begin;

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
    perform 1
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
    if v_yanlis >= c_can then
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
            'skor', v_skor, 'kalan_can', c_can - v_yanlis, 'bitti', false);
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
    v_bitti := v_skor = 10 or v_yanlis >= c_can;

    update public.kullanici_oyun_gecmisi
    set skor = v_skor,
        durum = case when v_bitti then 'tamamlandi' else durum end
    where kullanici_id = v_kullanici
      and oyun_id = p_oyun_id
      and durum = 'basladi';

    return jsonb_build_object(
        'dogru', v_sira is not null, 'sira', v_sira, 'deger', v_deger, 'tekrar', false, 'oyuncu_isim', v_isim,
        'foto_url', case when v_sira is not null then coalesce(v_cevap_foto, v_foto) else v_foto end,
        'skor', v_skor, 'kalan_can', greatest(c_can - v_yanlis, 0), 'bitti', v_bitti);
end;
$$;

revoke execute on function public.top10_tahmin(uuid, uuid) from public, anon;
grant execute on function public.top10_tahmin(uuid, uuid) to authenticated;

commit;
