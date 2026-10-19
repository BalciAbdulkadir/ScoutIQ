-- 001: Temel veri tablolarının düzeltilmesi
-- Supabase SQL Editor'da tek seferde çalıştırılır. Hata olursa hiçbir değişiklik uygulanmaz.
-- Bu dosyadan sonra veri data_miner/main.py ile sezon sezon yeniden çekilmelidir.

begin;

-- 1) Mükerrer ve hatalı yıllı veriyi temizle (veri yeniden çekilecek)
truncate table kariyer_gecmisi, oyuncular, kulupler;

-- İsteğe bağlı: eski test oyunları silinen kulüplerin UUID'lerini içerir, uygulamada çalışmazlar.
-- Silinirse kullanici_oyun_gecmisi'ndeki ilgili kayıtlar da CASCADE ile silinir.
-- delete from gunluk_oyunlar;

-- 2) Transfermarkt ID'leri: eşleştirme isim yerine bunlarla yapılır
alter table kulupler add column transfermarkt_id varchar not null;
alter table kulupler add constraint kulupler_transfermarkt_id_key unique (transfermarkt_id);

alter table oyuncular add column transfermarkt_id varchar not null;
alter table oyuncular add constraint oyuncular_transfermarkt_id_key unique (transfermarkt_id);

-- 3) kariyer_gecmisi: oyuncu-kulüp çifti başına tek satır, yıllar gerçek sezon yılı
alter table kariyer_gecmisi
    alter column oyuncu_id set not null,
    alter column kulup_id set not null,
    alter column baslangic_yili set not null;

alter table kariyer_gecmisi add constraint kariyer_gecmisi_oyuncu_kulup_key unique (oyuncu_id, kulup_id);
alter table kariyer_gecmisi add constraint kariyer_gecmisi_yil_check
    check (baslangic_yili between 1900 and 2100 and (bitis_yili is null or bitis_yili >= baslangic_yili));

-- get_ortak_oyuncular kulüp üzerinden arar; oyuncu_id zaten unique kısıtın ilk kolonu
create index kariyer_gecmisi_kulup_id_idx on kariyer_gecmisi (kulup_id);

-- 4) kullanici_oyun_gecmisi: kullanıcısız kayıt olamaz
delete from kullanici_oyun_gecmisi where kullanici_id is null;
alter table kullanici_oyun_gecmisi alter column kullanici_id set not null;

-- 5) Oyun tipi serbest metin olarak kalır ama sadece bilinen değerler kabul edilir
alter table gunluk_oyunlar add constraint gunluk_oyunlar_oyun_tipi_check
    check (oyun_tipi in ('kesisim', 'bonservis'));
alter table kullanici_oyun_gecmisi add constraint kullanici_oyun_gecmisi_oyun_tipi_check
    check (oyun_tipi in ('kesisim', 'bonservis'));

-- 6) Bir kulübün bir sezondaki kadrosunu kariyer geçmişine işler.
--    Oyuncu-kulüp çifti zaten varsa yıl aralığını genişletir.
create or replace function kariyer_sezon_ekle(p_kulup_id uuid, p_sezon integer, p_oyuncu_ids uuid[])
returns void
language sql
as $$
    insert into kariyer_gecmisi (oyuncu_id, kulup_id, baslangic_yili, bitis_yili)
    select distinct oyuncu_id, p_kulup_id, p_sezon, p_sezon
    from unnest(p_oyuncu_ids) as oyuncu_id
    on conflict (oyuncu_id, kulup_id) do update
        set baslangic_yili = least(kariyer_gecmisi.baslangic_yili, excluded.baslangic_yili),
            bitis_yili     = greatest(kariyer_gecmisi.bitis_yili, excluded.bitis_yili);
$$;

commit;
