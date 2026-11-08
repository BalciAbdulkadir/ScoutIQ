-- 017: Oyuncu havuzu: maç sayıları, Wikipedia bilinirliği ve kademeler
-- Supabase SQL Editor'da tek seferde çalıştırılır. Hata olursa hiçbir değişiklik uygulanmaz.
-- 015_onem_verileri.sql'den sonra çalıştırılmalıdır (oyuncu_kulup_istatistikleri kullanılır).
--
-- Kademeler data_miner/kademeler.py ile hesaplanır:
--   unlu    : bilinirlik skoruna göre ilk 500 (kolay sorular)
--   bilinen : sonraki 1.500 (orta sorular)
--   diger   : soru havuzunun kalanı (zor sorular)
--   cevap   : en az 1 kulüp ya da A milli maçı olan ama soru havuzuna girmeyen; sadece cevap olarak kabul edilir
--   null    : veritabanındaki kulüplerde ve A milli takımda maçı olmayan

begin;

-- Oyuncunun bu kulüpte çıktığı resmi maç sayısı (lig, kupa, Avrupa). null = oyuncunun istatistiği henüz çekilmedi
alter table public.kariyer_gecmisi add column mac_sayisi integer;

alter table public.oyuncular
    add column ust_lig_mac integer,             -- 6 ligde toplam lig maçı
    add column istatistik_cekim_tarihi timestamptz,
    add column wikidata_id varchar,
    add column wiki_dil_sayisi integer,         -- kaç dilde Wikipedia sayfası var (Wikidata'da yoksa 0)
    add column trwiki_baslik text,
    add column trwiki_goruntulenme integer,     -- son 60 gün Türkçe Wikipedia görüntülenmesi (sayfa yoksa 0)
    add column wiki_cekim_tarihi timestamptz,
    add column bilinirlik real,                 -- 0-1 arası skor, sadece soru havuzundakiler için
    add column kademe text,
    add column kademe_override text;            -- elle düzeltme, doluysa kademe yerine bu kullanılır

alter table public.oyuncular add constraint oyuncular_kademe_check
    check (kademe in ('unlu', 'bilinen', 'diger', 'cevap')
       and (kademe_override is null or kademe_override in ('unlu', 'bilinen', 'diger', 'cevap')));

create index oyuncular_kademe_idx on public.oyuncular (kademe);

-- kariyer_gecmisi.mac_sayisi'ni oyuncu_kulup_istatistikleri'nden yeniden hesaplar.
-- İstatistiği çekilmiş bir oyuncunun istatistikte görünmeyen kulübü 0 maç sayılır.
-- onem_verileri.py yeni oyuncular için çalıştıktan sonra tekrar çalıştırılır (kademeler.py bunu kendisi çağırır).
create or replace function public.kariyer_mac_sayisi_hesapla()
returns void
language sql
set search_path = ''
as $$
    update public.kariyer_gecmisi k
    set mac_sayisi = m.mac
    from (
        select kg.oyuncu_id, kg.kulup_id, coalesce(i.mac, 0) as mac
        from public.kariyer_gecmisi kg
        join public.oyuncular o on o.id = kg.oyuncu_id and o.onem_verisi_cekim_tarihi is not null
        join public.kulupler ku on ku.id = kg.kulup_id
        left join public.oyuncu_kulup_istatistikleri i
            on i.oyuncu_id = kg.oyuncu_id
           and i.kulup_tm_id = ku.transfermarkt_id
    ) m
    where k.oyuncu_id = m.oyuncu_id
      and k.kulup_id = m.kulup_id
      and k.mac_sayisi is distinct from m.mac;
$$;

revoke execute on function public.kariyer_mac_sayisi_hesapla() from public, anon, authenticated;

select public.kariyer_mac_sayisi_hesapla();

commit;
