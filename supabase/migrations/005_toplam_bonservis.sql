-- 005: Oyuncuların toplam bonservis bedeli (Bonservis oyunu)
-- Supabase SQL Editor'da tek seferde çalıştırılır. Hata olursa hiçbir değişiklik uygulanmaz.

begin;

-- Oyuncunun kariyerindeki tüm satın alma bedellerinin toplamı, Euro.
-- Sadece 'transfer' tipi sayılır: kiralama bedelleri (loan), kiralık dönüşleri (endOfLoan)
-- ve kulüp içi geçişler (internal) dahil değildir.
alter table public.oyuncular add column toplam_bonservis bigint not null default 0;

-- Toplamları transferler tablosundan yeniden hesaplar.
-- Yeni transfer verisi çekildikten sonra tekrar çalıştırılır: select toplam_bonservis_hesapla();
create or replace function public.toplam_bonservis_hesapla()
returns void
language sql
set search_path = ''
as $$
    update public.oyuncular o
    set toplam_bonservis = coalesce(t.toplam, 0)
    from (
        select p.id, sum(tr.bedel) as toplam
        from public.oyuncular p
        left join public.transferler tr
            on tr.oyuncu_id = p.id
           and tr.tip = 'transfer'
           and tr.bedel > 0
        group by p.id
    ) t
    where t.id = o.id
      and o.toplam_bonservis is distinct from coalesce(t.toplam, 0);
$$;

revoke execute on function public.toplam_bonservis_hesapla() from public, anon, authenticated;

select public.toplam_bonservis_hesapla();

-- Bonservis sorusu için oyuncu seçerken (toplam_bonservis > 5 milyon) kullanılır
create index oyuncular_toplam_bonservis_idx on public.oyuncular (toplam_bonservis);

commit;
