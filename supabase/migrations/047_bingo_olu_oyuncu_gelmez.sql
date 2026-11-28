-- 047: Bingo'da artık hiçbir boş kutuya uymayan oyuncu gelmez, tuzak oyuncu bir kez gelir
-- Supabase SQL Editor'da tek seferde çalıştırılır. Hata olursa hiçbir değişiklik uygulanmaz.
-- 046_izgara_kutu_secimi.sql'den sonra çalıştırılmalıdır. Tekrar çalıştırılabilir.
-- Uygulamada değişiklik gerekmez: sıradaki oyuncuyu her zaman sunucu söyler (bingo_hamle ve oyun_ac dönüşü).
-- DİKKAT: Çalıştığı anda yarıda kalan oyunlarda sıradaki oyuncu değişebilir (ekrandaki oyuncu, uyduğu kutular dolmuş
-- bir oyuncuysa sonraki hamlede atlanır). Kimse oynamıyorken, gece geç saatte çalıştırın.
--
-- Neden (27 Kasım 2026 test geri bildirimi: "kutulara uymayan oyuncu çok geliyor"):
--   Pas sınırsız ve deste döndüğü için (023), uyduğu kutuların hepsi dolmuş oyuncular ve hiçbir kutuya uymayan
--   4 tuzak oyuncu her turda tekrar geliyordu. Kart doldukça gelenlerin çoğu işe yaramıyordu.
--
-- Yeni kural: sıradaki oyuncu, son gelen oyuncudan sonraki ilk UYGUN yerleşmemiş oyuncudur (destenin sonundan başa
-- dönme aynı kalır). Uygun:
--   - en az bir BOŞ kutuya uyuyor (kullanıcının doğru hamlesiyle dolmamış bir kutu), ya da
--   - hiçbir kutuya uymuyor (tuzak, cardinality(hucreler) = 0) ve bu oyuncu için daha önce hiç hamle yok:
--     tuzak bir kez gelir, pas geçilince bir daha dönmez.
--   Uyduğu kutuların hepsi dolmuş oyuncu atlanır.
-- Bitiş kuralı değişmez (bingo_hamle, 043): kart dolunca ya da kalan oyuncuların hiçbiri boş kutulara uymayınca biter.
-- Oyun bitmediyse en az bir yerleşmemiş oyuncu boş bir kutuya uyar, bu yüzden sıradaki hiçbir zaman boş kalmaz.
--
-- Değişen: sadece public.bingo_siradaki (023'teki gövde). bingo_hamle ve oyun_ac onu çağırır, onlara dokunulmaz.
--
-- Kontrol (çalıştırdıktan sonra):
--   select prosrc like '%cardinality%' from pg_proc where proname = 'bingo_siradaki';                  -> true
--   select has_function_privilege('authenticated', 'public.bingo_siradaki(uuid, uuid)', 'execute');  -> false

begin;

create or replace function public.bingo_siradaki(p_oyun_id uuid, p_kullanici uuid)
returns smallint
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_son integer;
    v_deste integer;
    v_siradaki smallint;
begin
    select oyuncu into v_son
    from public.bingo_hamleleri
    where kullanici_id = p_kullanici and oyun_id = p_oyun_id
    order by sira desc
    limit 1;
    v_son := coalesce(v_son, 0);

    select count(*) into v_deste from public.bingo_eslesmeleri where oyun_id = p_oyun_id;

    -- Son oyuncudan sonraki ilk uygun yerleşmemiş oyuncu; destenin sonundan başa dönülür
    select be.sira into v_siradaki
    from public.bingo_eslesmeleri be
    where be.oyun_id = p_oyun_id
      and not exists (
          select 1 from public.bingo_hamleleri bh
          where bh.kullanici_id = p_kullanici and bh.oyun_id = p_oyun_id and bh.dogru and bh.oyuncu = be.sira
      )
      and (
          -- En az bir boş kutuya uyuyor
          exists (
              select 1 from unnest(be.hucreler) as u(hucre)
              where not exists (
                  select 1 from public.bingo_hamleleri bh
                  where bh.kullanici_id = p_kullanici and bh.oyun_id = p_oyun_id and bh.dogru and bh.hucre = u.hucre
              )
          )
          -- Tuzak: hiçbir kutuya uymuyor ve daha önce hiç gelmedi (gelip pas geçilen tuzak dönmez)
          or (
              cardinality(be.hucreler) = 0
              and not exists (
                  select 1 from public.bingo_hamleleri bh
                  where bh.kullanici_id = p_kullanici and bh.oyun_id = p_oyun_id and bh.oyuncu = be.sira
              )
          )
      )
    order by (be.sira - v_son - 1 + v_deste) % v_deste
    limit 1;

    return v_siradaki;
end;
$$;

revoke execute on function public.bingo_siradaki(uuid, uuid) from public, anon, authenticated;

commit;
