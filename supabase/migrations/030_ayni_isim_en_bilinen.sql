-- 030: Aynı isimli oyuncularda en bilinen oyuncunun fotoğrafı gösterilir
-- Supabase SQL Editor'da tek seferde çalıştırılır. Hata olursa hiçbir değişiklik uygulanmaz.
-- 029_top10.sql'den sonra çalıştırılmalıdır.
--
-- Sorun: oyuncu_ara aynı isimli oyuncuları tek satırda birleştiriyor, satırın id'sini ve fotoğrafını en küçük
-- uuid'li oyuncudan alıyordu. Bu rastgele bir seçim: "Luis Suárez" yazınca 1960'ların İspanyol Luis Suárez'inin
-- fotoğrafı geliyordu. Cevap kontrolü isimle yapıldığı için cevap doğru sayılıyor ama fotoğraf yanlış oyuncunun oluyordu.
--
-- Düzeltme:
--   1) oyuncu_ara: aynı isimli oyuncuların satırı, aralarındaki en bilinen oyuncunun id'sini ve fotoğrafını taşır
--      (kademe: ünlü, bilinen, diğer, havuz dışı; sonra bilinirlik skoru; fotoğrafı olan önce).
--      Arama, sıralama ve öneri sayısı değişmedi (022 ile aynı).
--   2) top10_tahmin: doğru tahminde listedeki oyuncunun fotoğrafı döner (top10_cevaplar zaten onu gösteriyordu;
--      tahmin anında ve sonradan açınca aynı fotoğraf görünür). Başka bir değişiklik yok.

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
    select (array_agg(o.id order by
                case coalesce(o.kademe_override, o.kademe)
                    when 'unlu' then 0 when 'bilinen' then 1 when 'diger' then 2 else 3 end,
                o.bilinirlik desc nulls last,
                o.foto_url is null,
                o.id))[1] as id,
           o.isim::text,
           (array_agg(o.foto_url order by
                case coalesce(o.kademe_override, o.kademe)
                    when 'unlu' then 0 when 'bilinen' then 1 when 'diger' then 2 else 3 end,
                o.bilinirlik desc nulls last,
                o.foto_url is null,
                o.id))[1] as foto_url
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

-- Tahmin: 029 ile aynı; sadece doğru tahminde listedeki oyuncunun fotoğrafı döner
create or replace function public.top10_tahmin(p_oyun_id uuid, p_oyuncu_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_kullanici uuid := (select auth.uid());
    v_isim text;
    v_foto text;
    v_cevap_foto text;
    v_sira smallint;
    v_deger text;
    v_skor integer;
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

    select count(sira) into v_skor
    from public.top10_tahminleri
    where kullanici_id = v_kullanici and oyun_id = p_oyun_id;

    -- Daha önce doğru bilinmiş ya da yanlış denenmiş oyuncu: tahmin sayılmaz
    if exists (
        select 1 from public.top10_tahminleri
        where kullanici_id = v_kullanici and oyun_id = p_oyun_id and oyuncu_isim = v_isim
    ) then
        return jsonb_build_object(
            'dogru', false, 'sira', null, 'deger', null, 'tekrar', true, 'oyuncu_isim', v_isim, 'foto_url', v_foto,
            'skor', v_skor, 'bitti', false);
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

    v_skor := v_skor + (v_sira is not null)::integer;
    v_bitti := v_skor = 10;

    update public.kullanici_oyun_gecmisi
    set skor = v_skor,
        durum = case when v_bitti then 'tamamlandi' else durum end
    where kullanici_id = v_kullanici
      and oyun_id = p_oyun_id
      and durum = 'basladi';

    return jsonb_build_object(
        'dogru', v_sira is not null, 'sira', v_sira, 'deger', v_deger, 'tekrar', false, 'oyuncu_isim', v_isim,
        'foto_url', case when v_sira is not null then coalesce(v_cevap_foto, v_foto) else v_foto end,
        'skor', v_skor, 'bitti', v_bitti);
end;
$$;

revoke execute on function public.top10_tahmin(uuid, uuid) from public, anon;
grant execute on function public.top10_tahmin(uuid, uuid) to authenticated;

commit;
