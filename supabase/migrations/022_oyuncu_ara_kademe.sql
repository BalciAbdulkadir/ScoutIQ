-- 022: Oyuncu arama önerileri kelime başına ve kademeye göre sıralanır
-- Supabase SQL Editor'da tek seferde çalıştırılır. Hata olursa hiçbir değişiklik uygulanmaz.
-- 017_oyuncu_havuzu.sql'den sonra çalıştırılmalıdır (kademe, kademe_override ve bilinirlik kolonları).
--
-- Sıralama:
--   1) İsmindeki bir kelime yazılanla başlayanlar önce ("mes" -> Lionel Messi, Mesut Özil), ismin ortasında
--      geçenler sonra ("mes" -> James Rodríguez).
--   2) Kademe: ünlü, bilinen, diğer, en sonda havuz dışındakiler ('cevap' ya da boş). Elle düzeltme (kademe_override) doluysa o geçerlidir.
--   3) Bilinirlik skoru yüksek olan önce. Havuz dışındakilerin skoru yoktur, onlar alfabetik sıralanır.
-- Aynı isimli oyuncular eskisi gibi tek satırdır; satır, aralarındaki en bilinen oyuncunun kademesinden sıralanır.
-- Arama (sadeleştirilmiş isimde geçme, en az 2 harf, en fazla 8 öneri) değişmedi.

begin;

create or replace function public.oyuncu_ara(p_arama text)
returns table (id uuid, isim text, foto_url text)
language sql
stable
set search_path = ''
as $$
    with arama as (
        select public.isim_sadelestir(p_arama) as metin,
               -- Kelimeleri korunmuş hali: "Arda Gü" -> "arda gu"
               trim(regexp_replace(
                   lower(extensions.unaccent('extensions.unaccent'::regdictionary, coalesce(p_arama, ''))),
                   '[^a-z0-9]+', ' ', 'g')) as kelimeler
    )
    select (array_agg(o.id order by o.id))[1] as id,
           o.isim::text,
           (array_agg(o.foto_url order by o.id))[1] as foto_url
    from public.oyuncular o, arama a
    where length(a.metin) >= 2
      and public.isim_sadelestir(o.isim) like '%' || a.metin || '%'
    group by o.isim, a.kelimeler
    order by
        -- İsimdeki bir kelime yazılanla başlıyor mu (kelimeler sadece harf, rakam ve boşluk: like için güvenli)
        (' ' || trim(regexp_replace(
                  lower(extensions.unaccent('extensions.unaccent'::regdictionary, o.isim)),
                  '[^a-z0-9]+', ' ', 'g'))) like '% ' || a.kelimeler || '%' desc,
        min(case coalesce(o.kademe_override, o.kademe)
                when 'unlu' then 0
                when 'bilinen' then 1
                when 'diger' then 2
                else 3
            end),
        max(o.bilinirlik) desc nulls last,
        o.isim
    limit 8;
$$;

revoke execute on function public.oyuncu_ara(text) from public, anon;
grant execute on function public.oyuncu_ara(text) to authenticated;

commit;
