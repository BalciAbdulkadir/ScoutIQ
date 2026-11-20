-- 012: Izgara örnek cevaplarına oyuncu fotoğrafı
-- Supabase SQL Editor'da tek seferde çalıştırılır. Hata olursa hiçbir değişiklik uygulanmaz.
-- 011_izgara.sql'den sonra çalıştırılmalıdır.
--
-- Oyun bitince boş kalan kutularda örnek cevabın ismiyle birlikte fotoğrafı da gösterilir.
-- Dönüş tipi değiştiği için fonksiyon silinip yeniden oluşturulur; kurallar 011'dekiyle aynıdır.

begin;

drop function if exists public.izgara_ornek_cevaplar(uuid);

create function public.izgara_ornek_cevaplar(p_oyun_id uuid)
returns table (hucre integer, oyuncu_isim text, foto_url text)
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
    select h, ornek.isim, ornek.foto_url
    from generate_series(0, 8) as h
    left join lateral (
        select o.isim::text as isim, o.foto_url::text as foto_url
        from public.izgara_baslik_oyunculari(v_tahta -> 'satirlar' -> (h / 3)) s(oyuncu_id)
        join public.izgara_baslik_oyunculari(v_tahta -> 'sutunlar' -> (h % 3)) u(oyuncu_id) using (oyuncu_id)
        join public.oyuncular o on o.id = s.oyuncu_id
        order by o.toplam_bonservis desc, o.isim
        limit 1
    ) ornek on true
    where v_tahta is not null;
end;
$$;

revoke execute on function public.izgara_ornek_cevaplar(uuid) from public, anon;
grant execute on function public.izgara_ornek_cevaplar(uuid) to authenticated;

commit;
