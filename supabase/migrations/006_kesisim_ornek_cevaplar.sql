-- 006: Kesişim oyunu bitince her soru için örnek bir doğru cevap
-- Supabase SQL Editor'da tek seferde çalıştırılır. Hata olursa hiçbir değişiklik uygulanmaz.
-- 005_toplam_bonservis.sql'den sonra çalıştırılmalıdır (oyuncular.toplam_bonservis kullanılır).

begin;

-- Oyun sonundaki özette yanlış cevapların yanında gösterilir.
-- kariyer_gecmisi uygulamaya kapalı olduğu için security definer ile çalışır.
-- Cevaplar sadece oyunu bitirmiş kullanıcıya döner: oyun sürerken çağrılırsa boş döner,
-- böylece fonksiyon cevaplara önceden bakmak için kullanılamaz.
-- Bir soruda birden fazla doğru cevap varsa en tanınmış olanı, yani toplam bonservisi en yüksek
-- oyuncu seçilir (eşitlikte isim sırası). Kulüpler oyunun kendi sorusundan okunur, istemciden alınmaz.
create or replace function public.kesisim_ornek_cevaplar(p_oyun_id uuid)
returns table (soru_index integer, oyuncu_isim text)
language plpgsql
stable
security definer
set search_path = ''
as $$
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

    return query
    select (s.idx - 1)::integer,
           (
               select o.isim::text
               from public.kariyer_gecmisi ka
               join public.kariyer_gecmisi kb on kb.oyuncu_id = ka.oyuncu_id
               join public.oyuncular o on o.id = ka.oyuncu_id
               where ka.kulup_id = (s.soru ->> 'kulup_a_id')::uuid
                 and kb.kulup_id = (s.soru ->> 'kulup_b_id')::uuid
               order by o.toplam_bonservis desc, o.isim
               limit 1
           )
    from public.gunluk_oyunlar go,
         jsonb_array_elements(go.soru_verisi) with ordinality as s(soru, idx)
    where go.id = p_oyun_id
      and go.oyun_tipi = 'kesisim';
end;
$$;

revoke execute on function public.kesisim_ornek_cevaplar(uuid) from public, anon;
grant execute on function public.kesisim_ornek_cevaplar(uuid) to authenticated;

commit;
