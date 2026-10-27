-- 007: Oyuncu fotoğrafları
-- Supabase SQL Editor'da tek seferde çalıştırılır. Hata olursa hiçbir değişiklik uygulanmaz.
-- Bu dosyadan sonra mevcut oyuncuların fotoğrafları data_miner/fotograflar.py ile doldurulur.

begin;

-- Fotoğraflar kopyalanmaz, Transfermarkt'taki adresleri tutulur. null: fotoğraf yok.
alter table public.oyuncular add column foto_url text;

-- oyuncu_ara öneri listesinde fotoğrafı da döndürür. Dönüş tipi değiştiği için fonksiyon yeniden oluşturulur.
-- Aynı isimli oyuncular tek satır olduğu için fotoğraf, döndürülen id ile aynı oyuncudan alınır.
drop function public.oyuncu_ara(text);

create function public.oyuncu_ara(p_arama text)
returns table (id uuid, isim text, foto_url text)
language sql
stable
set search_path = ''
as $$
    with arama as (
        select public.isim_sadelestir(p_arama) as metin
    )
    select (array_agg(o.id order by o.id))[1] as id,
           o.isim::text,
           (array_agg(o.foto_url order by o.id))[1] as foto_url
    from public.oyuncular o, arama a
    where length(a.metin) >= 2
      and public.isim_sadelestir(o.isim) like '%' || a.metin || '%'
    group by o.isim
    order by bool_or(public.isim_sadelestir(o.isim) like a.metin || '%') desc, o.isim
    limit 8;
$$;

revoke execute on function public.oyuncu_ara(text) from public, anon;
grant execute on function public.oyuncu_ara(text) to authenticated;

commit;
