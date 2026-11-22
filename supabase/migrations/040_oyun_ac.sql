-- 040: Soruyu görmek oyunu başlatmaktır; oyuncular ve kulupler tablolarında sadece gereken kolonlar açık
-- Supabase SQL Editor'da tek seferde çalıştırılır. Hata olursa hiçbir değişiklik uygulanmaz.
-- 039_puan_her_dogruya.sql'den sonra çalıştırılmalıdır. Tekrar çalıştırılabilir.
--
-- ÖNEMLİ: Bu dosya eski uygulama sürümünü bozar. Eski sürüm soruyu gunluk_oyunlar'dan okur, kaydı kendisi açar ve
-- süreyi ayrı bir fonksiyonla başlatır; üçü de kapanır. Uygulama henüz yayında olmadığı için (22 Kasım 2026) iki
-- aşamaya bölünmedi. Sıra: önce bu dosyanın PR'ı main'e birleşir, sonra dosya çalıştırılır, aynı gün yeni sürüm kurulur.
--
-- Dayanak: kurallar/guvenlik_uygulama_plani.md, madde 2 ve 4 (madde 3, Top 10'a süre, uygulanmadı: Top 10 süresiz kalır).
--
-- Genel ilke: kullanıcı bir soruyu ancak o soru için saati başlamışken görebilir.
--
-- Sorun:
--   - gunluk_oyunlar.soru_verisi 00.00'dan itibaren giriş yapmış herkese açıktı. Uygulama soruyu okur, kaydı açar,
--     süreyi başlatırdı: üç ayrı istek. Doğrudan istek atan biri soruları okuyup araştırabilir, sonra kaydı açıp süreli
--     oynayabilirdi. 038'deki "süre ilk hamleden önce seçilir" kuralı da süresiz açılmış kayda sonradan 30 sn eklemeye
--     izin veriyordu: soruları süresiz okuyup hamle yapmadan 30 sn seçen tam çarpanla oynardı.
--   - Kesişim ve Bonservis'te bütün sorular, Bingo'da bütün deste (sırasıyla, hiçbir kutuya uymayan 4 oyuncu dahil)
--     oyun başında telefona iniyordu.
--   - oyuncular tablosunda piyasa değeri, bilinirlik, kademe gibi soru üretimine ait kolonlar okunabiliyordu.
--
-- Düzeltme:
--   1) oyun_ac: soru, kayıt ve süre tek adımda ve sunucuda oluşur. Bugünün oyununu sunucu bulur, istemci oyun id'si
--      göndermez. Kayıt yoksa açılır ve süreliyse saat aynı anda başlar. Kayıt varsa yeni süre yok sayılır, saat
--      sıfırlanmaz; süresi dolmuşsa kayıt kapatılır. Bitmiş oyunda soru verisinin tamamı döner.
--      Süre seçenekleri: Kesişim, Bonservis, Izgara 30/60/90; Bingo 60/90; Top 10 süresizdir.
--   2) Açık oyunda Kesişim ve Bonservis soruları tek tek gelir: cevaplanmış sorular + sıradaki soru. Toplam soru sayısı
--      ayrı alandır. kesisim_cevap ve bonservis_tahmin dönüşüne sıradaki soru eklendi (034'teki gövdeler, değişen tek
--      şey dönüş alanı).
--      Bingo'da açık oyunda deste sadece yerleşmiş, pas geçilmiş ve sıradaki oyuncuları taşır; görülmemiş oyuncunun
--      yeri null'dır, sıra numaraları değişmez. bingo_hamle dönüşüne sıradaki oyuncu eklendi (023'teki gövde, değişen
--      tek şey dönüş alanı). Pas sınırsız olduğu için oyuncu pas geçerek desteyi oyun içinde yine görebilir; süreli
--      oyunda bu süre yer, süresiz Bingo puansızdır. Kabul edildi.
--      Izgara ve Top 10 bütün olarak açılır: tahta görüldüğü an saat işler.
--   3) gunluk_oyunlar'da authenticated rolü sadece id, oyun_tipi ve tarih kolonlarını okuyabilir. Satır politikası
--      (002, bugün ve öncesi) aynen kalır. Soru verisi sadece oyun_ac'tan gelir.
--   4) İstemci kayıt açamaz: kullanici_oyun_gecmisi ekleme politikası (037) kaldırıldı, insert yetkisi alındı. 037'deki
--      "oyun_id günün oyunu mu" kontrolü oyun_ac'ın içindedir (oyunu sunucu bulur).
--   5) Süre sadece açılışta seçilir: oyun_sureyi_baslat (021) ve izgara_sureyi_baslat (037) kaldırıldı. 038'deki
--      sure_ilk_hamleden_once ve izgara_sure_ilk_tahminden_once tetikleyicileri gereksizleşti, zararları olmadığı için
--      kaldı.
--   6) oyuncu_ara security definer oldu (davranışı, dönüşü, en az 2 harf kuralı aynı). oyuncular'da authenticated rolü
--      sadece id, isim, uyruk ve foto_url'yi okuyabilir. kulupler'de sadece id, isim ve logo_url.
--      Bu kolonları okuyan yerler: Izgara tahminlerindeki oyuncular(foto_url) ilişkisi, kulupLogolari
--      (mobile/lib/services/oyun_deposu.dart) ve get_ortak_oyuncular (000; kariyer_gecmisi kapalı olduğu için
--      uygulamada zaten boş döner).
--      toplam_bonservis_hesapla (005), kariyer_mac_sayisi_hesapla (017) ve top10_kulup_sayilari (029) uygulamaya zaten
--      kapalıdır, sadece data_miner ve backend secret anahtarla çağırır. Değişiklik yok.
--      KURAL (036'daki uyarının yerini alır): oyuncular'a ya da kulupler'e eklenen yeni kolon kimseye açık değildir.
--      Uygulama okumayacaksa hiçbir şey yazılmaz; okuyacaksa "grant select (kolon) on public.<tablo> to authenticated;"
--      yazılır ve nedeni dosyanın yorumuna eklenir.
--
-- Backend (Cloud Run işi) ve data_miner secret anahtarla çalışır, etkilenmez.
--
-- Kontrol (çalıştırdıktan sonra, SQL Editor'da):
--   select has_column_privilege('authenticated', 'public.gunluk_oyunlar', 'soru_verisi', 'select');   -> false
--   select has_column_privilege('authenticated', 'public.gunluk_oyunlar', 'tarih', 'select');         -> true
--   select has_table_privilege('authenticated', 'public.kullanici_oyun_gecmisi', 'insert');           -> false
--   select count(*) from pg_policies
--   where tablename = 'kullanici_oyun_gecmisi' and policyname = 'kullanici_oyun_gecmisi_ekleme';      -> 0
--   select has_column_privilege('authenticated', 'public.oyuncular', 'bilinirlik', 'select');         -> false
--   select has_column_privilege('authenticated', 'public.oyuncular', 'foto_url', 'select');           -> true
--   select has_column_privilege('authenticated', 'public.kulupler', 'kademe', 'select');              -> false
--   select has_column_privilege('authenticated', 'public.kulupler', 'logo_url', 'select');            -> true
--   select prosecdef from pg_proc where proname = 'oyuncu_ara';                                      -> true
--   select count(*) from pg_proc where proname in ('oyun_sureyi_baslat', 'izgara_sureyi_baslat');      -> 0
--   select has_function_privilege('authenticated', 'public.oyun_ac(text, integer)', 'execute');       -> true

begin;

-- 1) Oyunu açar.
--    p_oyun_tipi: kesisim_kolay/orta/zor, bonservis_kolay/orta/zor, izgara_kolay/orta/zor, bingo, top10
--    p_sure: saniye, süresiz için null. Sadece kayıt bu çağrıda açılıyorsa kullanılır.
--    Dönüş:
--      { durum: 'yok' } bugün bu tipte oyun yoksa
--      { durum: 'basladi' | 'tamamlandi', yeni, oyun_id, tarih, skor, ilerleme, sure, kalan, sure_doldu,
--        soru_sayisi, siradaki, soru_verisi }
--        yeni: kayıt bu çağrıda açıldı | sure, kalan: saniye, süresiz oyunda null
--        sure_doldu: süre dolmuştu, kayıt bu çağrıda kapatıldı | soru_sayisi: Kesişim ve Bonservis'in toplam soru sayısı
--        siradaki: Bingo'da sıradaki oyuncunun destedeki sırası (1'den)
--    Kullanıcı bu oyunun bugün başka bir modunu açtıysa 019'daki tetikleyici 'oyun_gunde_bir' ipucuyla hata verir.
create or replace function public.oyun_ac(p_oyun_tipi text, p_sure integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_kullanici uuid := (select auth.uid());
    v_bugun date := public.bugunun_tarihi();
    v_oyun text := split_part(p_oyun_tipi, '_', 1);
    v_oyun_id uuid;
    v_soru jsonb;
    v_kayit record;
    v_durum text;
    v_yeni boolean := false;
    v_sure integer;
    v_baslangic timestamptz;
    v_kalan integer;
    v_sure_doldu boolean := false;
    v_soru_sayisi integer;
    v_siradaki smallint;
    v_gorulen smallint[];
begin
    if v_kullanici is null then
        raise exception 'Giriş yapılmamış';
    end if;

    if p_oyun_tipi is null or p_oyun_tipi not in ('kesisim_kolay', 'kesisim_orta', 'kesisim_zor',
                                                  'bonservis_kolay', 'bonservis_orta', 'bonservis_zor',
                                                  'izgara_kolay', 'izgara_orta', 'izgara_zor',
                                                  'bingo', 'top10') then
        raise exception 'Geçersiz oyun';
    end if;

    -- Süre seçenekleri: Bingo'da 30 sn yoktur, Top 10 süresizdir
    if p_sure is not null and (v_oyun = 'top10' or p_sure not in (30, 60, 90) or (v_oyun = 'bingo' and p_sure = 30)) then
        raise exception 'Geçersiz süre';
    end if;

    select g.id, g.soru_verisi into v_oyun_id, v_soru
    from public.gunluk_oyunlar g
    where g.oyun_tipi = p_oyun_tipi and g.tarih = v_bugun;
    if v_oyun_id is null then
        return jsonb_build_object('durum', 'yok', 'tarih', v_bugun);
    end if;

    -- Kayıt yoksa açılır, süreli oyunda saat aynı anda başlar. Aynı anda gelen iki istekten biri açar, diğeri o kaydı
    -- okur. Izgara'nın süresi ayrı tablodadır (013).
    if not exists (
        select 1 from public.kullanici_oyun_gecmisi
        where kullanici_id = v_kullanici and oyun_tipi = p_oyun_tipi and tarih = v_bugun
    ) then
        insert into public.kullanici_oyun_gecmisi (kullanici_id, oyun_id, oyun_tipi, tarih, skor, durum, sure_saniye, sure_baslangic)
        values (v_kullanici, v_oyun_id, p_oyun_tipi, v_bugun, 0, 'basladi',
                case when v_oyun <> 'izgara' then p_sure end,
                case when v_oyun <> 'izgara' and p_sure is not null then now() end)
        on conflict (kullanici_id, oyun_tipi, tarih) do nothing;
        v_yeni := found;

        if v_yeni and v_oyun = 'izgara' and p_sure is not null then
            insert into public.izgara_sureleri (kullanici_id, oyun_id, sure_saniye)
            values (v_kullanici, v_oyun_id, p_sure)
            on conflict (kullanici_id, oyun_id) do nothing;
        end if;
    end if;

    select g.skor, g.durum, g.ilerleme, g.sure_saniye, g.sure_baslangic into v_kayit
    from public.kullanici_oyun_gecmisi g
    where g.kullanici_id = v_kullanici and g.oyun_tipi = p_oyun_tipi and g.tarih = v_bugun
    for update;
    v_durum := v_kayit.durum;

    if v_oyun = 'izgara' then
        select s.sure_saniye, s.baslangic into v_sure, v_baslangic
        from public.izgara_sureleri s
        where s.kullanici_id = v_kullanici and s.oyun_id = v_oyun_id;
    else
        v_sure := v_kayit.sure_saniye;
        v_baslangic := v_kayit.sure_baslangic;
    end if;
    if v_sure is not null then
        v_kalan := greatest(0, ceil(extract(epoch from (v_baslangic + make_interval(secs => v_sure) - now())))::integer);
    end if;

    -- Oyun kapalıyken süre dolmuş: kayıt o anki skorla kapatılır (skoru hamle fonksiyonları yazar, değişmez)
    if v_durum = 'basladi' and v_kalan = 0 then
        update public.kullanici_oyun_gecmisi
        set durum = 'tamamlandi'
        where kullanici_id = v_kullanici and oyun_tipi = p_oyun_tipi and tarih = v_bugun and durum = 'basladi';
        v_durum := 'tamamlandi';
        v_sure_doldu := true;
    end if;

    if v_oyun in ('kesisim', 'bonservis') then
        v_soru_sayisi := jsonb_array_length(v_soru);
    end if;

    -- Açık oyunda henüz sırası gelmemiş soru ve oyuncu gönderilmez
    if v_durum = 'basladi' then
        if v_oyun in ('kesisim', 'bonservis') then
            -- Cevaplanmış sorular + sıradaki soru. Eski Bonservis sorularındaki sağdaki oyuncunun bedeli çıkarılır.
            select coalesce(jsonb_agg(t.e - 'oyuncu_b_bonservis' order by t.i), '[]'::jsonb) into v_soru
            from jsonb_array_elements(v_soru) with ordinality as t(e, i)
            where t.i <= jsonb_array_length(v_kayit.ilerleme) + 1;
        elsif v_oyun = 'bingo' then
            v_siradaki := public.bingo_siradaki(v_oyun_id, v_kullanici);
            select coalesce(array_agg(h.oyuncu), '{}') into v_gorulen
            from public.bingo_hamleleri h
            where h.kullanici_id = v_kullanici and h.oyun_id = v_oyun_id;

            v_soru := jsonb_set(v_soru, '{oyuncular}', (
                select coalesce(jsonb_agg(case when t.i = v_siradaki or t.i::smallint = any(v_gorulen) then t.e
                                               else 'null'::jsonb end order by t.i), '[]'::jsonb)
                from jsonb_array_elements(v_soru -> 'oyuncular') with ordinality as t(e, i)));
        end if;
    end if;

    return jsonb_build_object(
        'durum', v_durum,
        'yeni', v_yeni,
        'oyun_id', v_oyun_id,
        'tarih', v_bugun,
        'skor', v_kayit.skor,
        'ilerleme', v_kayit.ilerleme,
        'sure', v_sure,
        'kalan', v_kalan,
        'sure_doldu', v_sure_doldu,
        'soru_sayisi', v_soru_sayisi,
        'siradaki', v_siradaki,
        'soru_verisi', v_soru);
end;
$$;

revoke execute on function public.oyun_ac(text, integer) from public, anon;
grant execute on function public.oyun_ac(text, integer) to authenticated;

-- 2) Kesişim cevabı: 034'teki fonksiyonun aynısı, dönüşe sıradaki soru eklendi.
--    Dönüş: { dogru, skor, bitti, sure_doldu, siradaki_soru } (siradaki_soru: oyun bitmediyse sıradaki soru)
create or replace function public.kesisim_cevap(p_oyun_id uuid, p_soru_index integer, p_oyuncu_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    c_puan constant integer := 2;
    v_kullanici uuid := (select auth.uid());
    v_sorular jsonb;
    v_soru_sayisi integer;
    v_isim text;
    v_kayit jsonb;
    v_ilerleme jsonb;
    v_skor integer;
    v_dogru boolean;
    v_bitti boolean;
begin
    if v_kullanici is null then
        raise exception 'Giriş yapılmamış';
    end if;

    select soru_verisi, jsonb_array_length(soru_verisi) into v_sorular, v_soru_sayisi
    from public.gunluk_oyunlar
    where id = p_oyun_id and oyun_tipi like 'kesisim%' and tarih <= public.bugunun_tarihi();
    if v_soru_sayisi is null then
        raise exception 'Oyun bulunamadı';
    end if;

    select isim into v_isim from public.oyuncular where id = p_oyuncu_id;
    if v_isim is null then
        raise exception 'Oyuncu bulunamadı';
    end if;

    v_kayit := public.acik_kaydi_al(v_kullanici, p_oyun_id);
    if v_kayit is null then
        raise exception 'Oyun açık değil';
    end if;
    v_skor := (v_kayit ->> 'skor')::integer;
    v_ilerleme := v_kayit -> 'ilerleme';

    if (v_kayit ->> 'sure_doldu')::boolean then
        return jsonb_build_object('dogru', false, 'skor', v_skor, 'bitti', true, 'sure_doldu', true, 'siradaki_soru', null);
    end if;

    if p_soru_index <> jsonb_array_length(v_ilerleme) or p_soru_index >= v_soru_sayisi then
        raise exception 'Sıra hatalı' using hint = 'soru_sira';
    end if;

    v_dogru := public.kesisim_cevap_kontrol(p_oyun_id, p_soru_index, p_oyuncu_id);
    v_skor := v_skor + case when v_dogru then c_puan else 0 end;
    v_ilerleme := v_ilerleme || jsonb_build_array(jsonb_build_object('dogru', v_dogru, 'cevap', v_isim));
    v_bitti := jsonb_array_length(v_ilerleme) >= v_soru_sayisi;

    update public.kullanici_oyun_gecmisi
    set skor = v_skor,
        ilerleme = v_ilerleme,
        durum = case when v_bitti then 'tamamlandi' else durum end
    where kullanici_id = v_kullanici and oyun_id = p_oyun_id and durum = 'basladi';

    return jsonb_build_object('dogru', v_dogru, 'skor', v_skor, 'bitti', v_bitti, 'sure_doldu', false,
                              'siradaki_soru', case when v_bitti then null else v_sorular -> (p_soru_index + 1) end);
end;
$$;

revoke execute on function public.kesisim_cevap(uuid, integer, uuid) from public, anon;
grant execute on function public.kesisim_cevap(uuid, integer, uuid) to authenticated;

-- 3) Bonservis tahmini: 034'teki fonksiyonun aynısı, dönüşe sıradaki soru eklendi (sağdaki oyuncunun bedeli olmadan).
--    Dönüş: { dogru, rakip_bonservis, skor, bitti, sure_doldu, siradaki_soru }. Süre dolduysa bedel dönmez.
create or replace function public.bonservis_tahmin(p_oyun_id uuid, p_soru_index integer, p_daha_fazla boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    c_puan constant integer := 2;
    v_kullanici uuid := (select auth.uid());
    v_sorular jsonb;
    v_soru jsonb;
    v_soru_sayisi integer;
    v_referans bigint;
    v_rakip bigint;
    v_kayit jsonb;
    v_ilerleme jsonb;
    v_skor integer;
    v_dogru boolean;
    v_bitti boolean;
begin
    if v_kullanici is null then
        raise exception 'Giriş yapılmamış';
    end if;
    if p_daha_fazla is null then
        raise exception 'Tahmin eksik';
    end if;

    select soru_verisi, soru_verisi -> p_soru_index, jsonb_array_length(soru_verisi)
    into v_sorular, v_soru, v_soru_sayisi
    from public.gunluk_oyunlar
    where id = p_oyun_id and oyun_tipi like 'bonservis%' and tarih <= public.bugunun_tarihi();
    if v_soru_sayisi is null then
        raise exception 'Oyun bulunamadı';
    end if;

    v_kayit := public.acik_kaydi_al(v_kullanici, p_oyun_id);
    if v_kayit is null then
        raise exception 'Oyun açık değil';
    end if;
    v_skor := (v_kayit ->> 'skor')::integer;
    v_ilerleme := v_kayit -> 'ilerleme';

    if (v_kayit ->> 'sure_doldu')::boolean then
        return jsonb_build_object('dogru', false, 'rakip_bonservis', null, 'skor', v_skor, 'bitti', true, 'sure_doldu', true,
                                  'siradaki_soru', null);
    end if;

    if v_soru is null or p_soru_index <> jsonb_array_length(v_ilerleme) then
        raise exception 'Sıra hatalı' using hint = 'soru_sira';
    end if;

    v_referans := (v_soru ->> 'oyuncu_a_bonservis')::bigint;
    v_rakip := public.bonservis_bedeli(p_oyun_id, p_soru_index);
    if v_referans is null or v_rakip is null then
        raise exception 'Bedel bulunamadı';
    end if;

    -- Eşit bedelde "daha az" doğru sayılır (uygulamanın eski davranışı)
    v_dogru := p_daha_fazla = (v_rakip > v_referans);
    v_skor := v_skor + case when v_dogru then c_puan else 0 end;
    v_ilerleme := v_ilerleme || jsonb_build_array(jsonb_build_object('dogru', v_dogru));
    v_bitti := jsonb_array_length(v_ilerleme) >= v_soru_sayisi;

    update public.kullanici_oyun_gecmisi
    set skor = v_skor,
        ilerleme = v_ilerleme,
        durum = case when v_bitti then 'tamamlandi' else durum end
    where kullanici_id = v_kullanici and oyun_id = p_oyun_id and durum = 'basladi';

    return jsonb_build_object('dogru', v_dogru, 'rakip_bonservis', v_rakip, 'skor', v_skor, 'bitti', v_bitti,
                              'sure_doldu', false,
                              'siradaki_soru', case when v_bitti then null
                                                    else (v_sorular -> (p_soru_index + 1)) - 'oyuncu_b_bonservis' end);
end;
$$;

revoke execute on function public.bonservis_tahmin(uuid, integer, boolean) from public, anon;
grant execute on function public.bonservis_tahmin(uuid, integer, boolean) to authenticated;

-- 4) Bingo hamlesi: 023'teki fonksiyonun aynısı, dönüşe sıradaki oyuncunun kendisi eklendi.
--    Dönüş: { dogru, hucre, skor, bitti, sure_doldu, siradaki, siradaki_oyuncu }
--      siradaki: sıradaki oyuncunun destedeki sırası | siradaki_oyuncu: { id, isim, foto }
create or replace function public.bingo_hamle(p_oyun_id uuid, p_sira integer, p_hucre integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_kullanici uuid := (select auth.uid());
    v_kutu integer;
    v_deste jsonb;
    v_bitis timestamptz;
    v_hamle_sayisi integer;
    v_skor integer;
    v_oyuncu smallint;
    v_eslesme smallint[];
    v_dogru boolean;
    v_bitti boolean;
    v_siradaki smallint;
begin
    if v_kullanici is null then
        raise exception 'Giriş yapılmamış';
    end if;

    select jsonb_array_length(soru_verisi -> 'hucreler'), soru_verisi -> 'oyuncular' into v_kutu, v_deste
    from public.gunluk_oyunlar
    where id = p_oyun_id
      and (oyun_tipi = 'bingo' or oyun_tipi like 'bingo\_%')
      and tarih <= public.bugunun_tarihi();
    if v_kutu is null then
        raise exception 'Oyun bulunamadı';
    end if;

    -- Kayıt kilitlenir: aynı anda gelen iki hamle sırayla işlenir
    select g.sure_baslangic + make_interval(secs => g.sure_saniye + 3) into v_bitis
    from public.kullanici_oyun_gecmisi g
    where g.kullanici_id = v_kullanici
      and g.oyun_id = p_oyun_id
      and g.durum = 'basladi'
    for update;
    if not found then
        raise exception 'Oyun açık değil';
    end if;

    select count(*), count(*) filter (where dogru) into v_hamle_sayisi, v_skor
    from public.bingo_hamleleri
    where kullanici_id = v_kullanici and oyun_id = p_oyun_id;

    -- Süre dolduysa (3 saniye toleransla) hamle kabul edilmez, oyun o anki skorla biter
    if v_bitis is not null and now() > v_bitis then
        update public.kullanici_oyun_gecmisi
        set skor = v_skor, durum = 'tamamlandi'
        where kullanici_id = v_kullanici and oyun_id = p_oyun_id and durum = 'basladi';

        return jsonb_build_object('dogru', false, 'hucre', null, 'skor', v_skor, 'bitti', true, 'sure_doldu', true,
                                  'siradaki', null, 'siradaki_oyuncu', null);
    end if;

    if p_sira <> v_hamle_sayisi + 1 then
        raise exception 'Sıra hatalı' using hint = 'bingo_sira';
    end if;

    v_oyuncu := public.bingo_siradaki(p_oyun_id, v_kullanici);
    select hucreler into v_eslesme from public.bingo_eslesmeleri where oyun_id = p_oyun_id and sira = v_oyuncu;
    if v_eslesme is null then
        raise exception 'Oyuncu bulunamadı';
    end if;

    if p_hucre is not null then
        if p_hucre < 0 or p_hucre >= v_kutu then
            raise exception 'Geçersiz kutu';
        end if;
        if exists (
            select 1 from public.bingo_hamleleri
            where kullanici_id = v_kullanici and oyun_id = p_oyun_id and hucre = p_hucre and dogru
        ) then
            raise exception 'Kutu dolu' using hint = 'bingo_kutu_dolu';
        end if;

        v_dogru := p_hucre::smallint = any(v_eslesme);
        if not v_dogru then
            -- Yanlış kutu: hamle sayılmaz, oyuncu sırada kalır
            return jsonb_build_object('dogru', false, 'hucre', p_hucre, 'skor', v_skor, 'bitti', false, 'sure_doldu', false,
                                      'siradaki', v_oyuncu, 'siradaki_oyuncu', v_deste -> (v_oyuncu - 1));
        end if;
    else
        v_dogru := false;
    end if;

    insert into public.bingo_hamleleri (kullanici_id, oyun_id, sira, oyuncu, hucre, dogru)
    values (v_kullanici, p_oyun_id, p_sira, v_oyuncu, p_hucre, v_dogru);

    v_skor := v_skor + v_dogru::integer;

    -- Kart doldu ya da kalan oyuncuların hiçbiri boş kutulara uymuyor
    v_bitti := v_skor = v_kutu or not exists (
        select 1
        from public.bingo_eslesmeleri be
        cross join lateral unnest(be.hucreler) as u(hucre)
        where be.oyun_id = p_oyun_id
          and not exists (
              select 1 from public.bingo_hamleleri bh
              where bh.kullanici_id = v_kullanici and bh.oyun_id = p_oyun_id and bh.dogru and bh.oyuncu = be.sira
          )
          and not exists (
              select 1 from public.bingo_hamleleri bh
              where bh.kullanici_id = v_kullanici and bh.oyun_id = p_oyun_id and bh.dogru and bh.hucre = u.hucre
          )
    );

    update public.kullanici_oyun_gecmisi
    set skor = v_skor,
        durum = case when v_bitti then 'tamamlandi' else durum end
    where kullanici_id = v_kullanici and oyun_id = p_oyun_id and durum = 'basladi';

    if not v_bitti then
        v_siradaki := public.bingo_siradaki(p_oyun_id, v_kullanici);
    end if;

    return jsonb_build_object('dogru', v_dogru, 'hucre', p_hucre, 'skor', v_skor, 'bitti', v_bitti, 'sure_doldu', false,
                              'siradaki', v_siradaki,
                              'siradaki_oyuncu', case when v_siradaki is null then null else v_deste -> (v_siradaki - 1) end);
end;
$$;

revoke execute on function public.bingo_hamle(uuid, integer, integer) from public, anon;
grant execute on function public.bingo_hamle(uuid, integer, integer) to authenticated;

-- 5) Soru verisi doğrudan okunamaz. Satır politikası (002) aynen kalır.
revoke select on public.gunluk_oyunlar from anon, authenticated;
grant select (id, oyun_tipi, tarih) on public.gunluk_oyunlar to authenticated;

-- 6) İstemci kayıt açamaz, kayıt sadece oyun_ac'tan açılır
drop policy if exists "kullanici_oyun_gecmisi_ekleme" on public.kullanici_oyun_gecmisi;
revoke insert on public.kullanici_oyun_gecmisi from anon, authenticated;

-- 7) Süre sadece açılışta seçilir
drop function if exists public.oyun_sureyi_baslat(text, date, integer);
drop function if exists public.izgara_sureyi_baslat(uuid, integer);

-- 8) oyuncular ve kulupler: sadece uygulamanın okuduğu kolonlar açık.
--    Tablo izni alınınca 036'daki kolon izinleri de gider; yine de her kolonun izni ayrıca alınır.
alter function public.oyuncu_ara(text) security definer;

do $$
declare
    v_tablo text;
    v_kolonlar text;
begin
    foreach v_tablo in array array['oyuncular', 'kulupler'] loop
        select string_agg(quote_ident(column_name), ', ') into v_kolonlar
        from information_schema.columns
        where table_schema = 'public' and table_name = v_tablo;

        execute format('revoke select on public.%I from anon, authenticated', v_tablo);
        execute format('revoke select (%s) on public.%I from anon, authenticated', v_kolonlar, v_tablo);
    end loop;
end;
$$;

grant select (id, isim, uyruk, foto_url) on public.oyuncular to authenticated;
grant select (id, isim, logo_url) on public.kulupler to authenticated;

commit;
