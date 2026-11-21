-- 039: Puan her doğruya ve her dolu kutuya verilir; oyun başına seri
-- Supabase SQL Editor'da tek seferde çalıştırılır. Hata olursa hiçbir değişiklik uygulanmaz.
-- 038_puan_ve_liderlik.sql'den sonra çalıştırılmalıdır. Tekrar çalıştırılabilir.
-- Eski uygulama sürümünü bozmaz: puan alanları ve fonksiyon imzaları aynı kalır.
--
-- Kurallar (ürün sahibinin 21 Kasım 2026 kararı, 038'deki "puanı sadece bitiren alır" kuralının yerini alır):
--   - Her doğru soru ve her dolu kutu puan getirir. Pes edilen, süresi dolan ya da canı biten oyun o ana kadarki
--     puanı alır. Oyunu kusursuz bitirene ek olarak tamamlama ve hız bonusu verilir.
--   - Puan = yuvarla(taban × zorluk çarpanı × süre çarpanı) + hız bonusu
--       taban:  Kesişim   doğru × 20                                  (en fazla 100)
--               Bonservis doğru × 12                                  (en fazla 60; Daha Az/Fazla'da %50 şans var)
--               Izgara    dolu kutu × 10, 9/9'da +10                  (en fazla 100)
--               Bingo     dolu kutu × 8, 12/12'de +4                  (en fazla 100)
--               Top 10    bulunan × 10, 10/10'da kalan can × 10       (en fazla 130)
--       zorluk: kolay 1 | orta 1.5 | zor 2 | Bingo ve Top 10 1.5
--       süre:   90 sn 1 | 60 sn 1.25 | 30 sn 1.5 | Top 10 1
--       hız bonusu: sadece kusursuz bitişte, yuvarla(ana puan × 0.2 × kalan saniye / toplam saniye)
--   - Süresiz oyunlar puansızdır (puan null); Top 10 süresizdir ama hep puanlanır.
--   - Kesişim ve Bonservis'te skor doğru başına 2'dir (034): doğru sayısı skor / 2.
--   - Top 10'da kalan can, yanlış tahminlerden hesaplanır (031: top10_tahminleri'nde sira null satırlar, 3 can).
--
-- Bu dosya ayrıca:
--   - 038 çalıştıktan sonra biten oyunların puanını yeni formülle yeniden hesaplar (puan_yaz tetikleyicisi bu
--     güncelleme süresince kapatılır, yoksa eski puanı geri yazar).
--   - seri_oyunlar(): oyun başına seri (ana menüde her oyunun kutucuğunda gösterilir). seri_getir (035) aynen kalır,
--     akşam hatırlatmaları onu kullanır.
--
-- Kontrol (çalıştırdıktan sonra):
--   select puan_hesapla('kesisim_zor', null, null, 10, 30, now() - interval '22 seconds', now());
--     -> "puan": 316, "taban": 100, "kusursuz": true, "hiz_bonusu": 16
--   select puan_hesapla('kesisim_kolay', null, null, 6, 90, now() - interval '90 seconds', now());
--     -> "puan": 60, "taban": 60, "kusursuz": false, "hiz_bonusu": 0
--   select puan_hesapla('izgara_orta', null, null, 7, 60, now() - interval '60 seconds', now());
--     -> "puan": 131
--   select puan_hesapla('bonservis_kolay', null, null, 10, null, null, now());
--     -> "puan": null, "sebep": "suresiz"

begin;

-- 1) Yeni formül. İmza 038'deki ile aynıdır; puan_yaz tetikleyicisi değişmez.
create or replace function public.puan_hesapla(
    p_oyun_tipi text,
    p_kullanici uuid,
    p_oyun_id uuid,
    p_skor integer,
    p_sure_saniye integer,
    p_sure_baslangic timestamptz,
    p_bitis timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    c_can constant integer := 3;
    v_oyun text := split_part(p_oyun_tipi, '_', 1);
    v_zorluk text := split_part(p_oyun_tipi, '_', 2);
    v_skor integer := greatest(coalesce(p_skor, 0), 0);
    v_taban integer;
    v_kusursuz boolean;
    v_kalan_can integer;
    v_zorluk_c numeric;
    v_sure_c numeric;
    v_kalan numeric;
    v_ana integer;
    v_hiz integer := 0;
begin
    -- Top 10 dışındaki oyunlar sadece süreliyse puanlanır
    if v_oyun <> 'top10' and p_sure_saniye is null then
        return jsonb_build_object('puan', null, 'sebep', 'suresiz');
    end if;

    case v_oyun
        when 'kesisim' then
            v_taban := least(v_skor / 2, 5) * 20;
            v_kusursuz := v_skor >= 10;
        when 'bonservis' then
            v_taban := least(v_skor / 2, 5) * 12;
            v_kusursuz := v_skor >= 10;
        when 'izgara' then
            v_kusursuz := v_skor >= 9;
            v_taban := least(v_skor, 9) * 10 + case when v_kusursuz then 10 else 0 end;
        when 'bingo' then
            v_kusursuz := v_skor >= 12;
            v_taban := least(v_skor, 12) * 8 + case when v_kusursuz then 4 else 0 end;
        when 'top10' then
            v_kusursuz := v_skor >= 10;
            select greatest(c_can - count(*), 0)::integer into v_kalan_can
            from public.top10_tahminleri t
            where t.kullanici_id = p_kullanici and t.oyun_id = p_oyun_id and t.sira is null;
            v_taban := least(v_skor, 10) * 10 + case when v_kusursuz then coalesce(v_kalan_can, 0) * 10 else 0 end;
        else
            return jsonb_build_object('puan', null, 'sebep', 'bilinmeyen_oyun');
    end case;

    v_zorluk_c := case
        when v_oyun in ('bingo', 'top10') then 1.5
        when v_zorluk = 'kolay' then 1.0
        when v_zorluk = 'orta' then 1.5
        when v_zorluk = 'zor' then 2.0
        else 1.0                                       -- eski, zorluksuz kesisim/bonservis kayıtları
    end;

    v_sure_c := case p_sure_saniye when 30 then 1.5 when 60 then 1.25 else 1.0 end;

    v_ana := round(v_taban * v_zorluk_c * v_sure_c)::integer;

    if p_sure_saniye is not null and p_sure_baslangic is not null and p_bitis is not null then
        v_kalan := least(p_sure_saniye,
                         greatest(0, p_sure_saniye - extract(epoch from (p_bitis - p_sure_baslangic))));
        -- Hız bonusu sadece kusursuz bitişte
        if v_kusursuz then
            v_hiz := round(v_ana * 0.2 * v_kalan / p_sure_saniye)::integer;
        end if;
    end if;

    return jsonb_build_object(
        'puan', v_ana + v_hiz,
        'taban', v_taban,
        'kusursuz', v_kusursuz,
        'zorluk_carpani', v_zorluk_c,
        'sure_carpani', v_sure_c,
        'sure', p_sure_saniye,
        'kalan_saniye', floor(v_kalan),
        'hiz_bonusu', v_hiz,
        'kalan_can', v_kalan_can);
end;
$$;

revoke execute on function public.puan_hesapla(text, uuid, uuid, integer, integer, timestamptz, timestamptz)
    from public, anon, authenticated;

-- 2) 038'den sonra biten oyunların puanı yeni formülle. bitis_zamani sadece 038'in tetikleyicisi yazdığı için
--    038'den önce biten oyunlara dokunulmaz. Izgara'nın süresi izgara_sureleri'ndedir (013).
alter table public.kullanici_oyun_gecmisi disable trigger puan_yaz;

update public.kullanici_oyun_gecmisi g
set puan_detay = d.detay,
    puan = (d.detay ->> 'puan')::integer
from (
    select k.id,
           public.puan_hesapla(k.oyun_tipi, k.kullanici_id, k.oyun_id, k.skor,
                               coalesce(s.sure_saniye, k.sure_saniye), coalesce(s.baslangic, k.sure_baslangic),
                               k.bitis_zamani) as detay
    from public.kullanici_oyun_gecmisi k
    left join public.izgara_sureleri s
        on k.oyun_tipi like 'izgara\_%' and s.kullanici_id = k.kullanici_id and s.oyun_id = k.oyun_id
    where k.bitis_zamani is not null
) d
where g.id = d.id;

alter table public.kullanici_oyun_gecmisi enable trigger puan_yaz;

-- 3) Oyun başına seri: { "kesisim": 3, "izgara": 1, ... }. Oyun, tipin alt çizgiden önceki kısmıdır
--    (kesisim_zor -> kesisim). Kurallar seri_getir (035) ile aynıdır: art arda o oyunun bitirildiği gün sayısı,
--    bugün bitirilmediyse dünden geriye sayılır. Serisi olmayan oyun listede yoktur. Sadece kendi serileri.
create or replace function public.seri_oyunlar()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
    with bugun as (
        select public.bugunun_tarihi() as gun
    ),
    gunler as (
        select distinct split_part(g.oyun_tipi, '_', 1) as oyun, g.tarih
        from public.kullanici_oyun_gecmisi g, bugun b
        where g.kullanici_id = (select auth.uid())
          and g.durum = 'tamamlandi'
          and g.tarih <= b.gun
    ),
    baslangic as (
        select o.oyun,
               case when exists (select 1 from gunler x where x.oyun = o.oyun and x.tarih = b.gun)
                    then b.gun else b.gun - 1 end as gun
        from (select distinct oyun from gunler) o, bugun b
    ),
    sirali as (
        select g.oyun, g.tarih, row_number() over (partition by g.oyun order by g.tarih desc) as n
        from gunler g
        join baslangic s on s.oyun = g.oyun
        where g.tarih <= s.gun
    ),
    -- Başlangıçtan geriye kesintisiz giden günler: ilk boşluktan sonraki hiçbir gün bu eşitliği sağlamaz
    sayilar as (
        select s.oyun, count(*)::integer as seri
        from sirali s
        join baslangic b on b.oyun = s.oyun
        where s.tarih = b.gun - (s.n - 1)::integer
        group by s.oyun
    )
    select coalesce(jsonb_object_agg(oyun, seri), '{}'::jsonb) from sayilar;
$$;

revoke execute on function public.seri_oyunlar() from public, anon;
grant execute on function public.seri_oyunlar() to authenticated;

commit;
