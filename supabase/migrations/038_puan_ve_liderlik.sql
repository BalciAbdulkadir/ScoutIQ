-- 038: Puan sistemi ve liderlik tablosu
-- Supabase SQL Editor'da tek seferde çalıştırılır. Hata olursa hiçbir değişiklik uygulanmaz.
-- 037_gelecek_oyunlar_kapali.sql'den sonra çalıştırılmalıdır.
-- Eski uygulama sürümünü bozmaz: eski sürüm puanı görmez ama oyunlar aynı çalışır. Yeni sürümden önce de çalıştırılabilir.
--
-- ÖNCE: Supabase Dashboard > Database > Extensions'tan pg_cron açık olmalıdır (aşağıdaki create extension da açar).
--
-- Kurallar (ürün sahibinin 20-21 Kasım 2026 kararı):
--   - Skor (doğru/kutu/oyuncu sayısı) aynen kalır. Puan ayrı bir alandır: kullanici_oyun_gecmisi.puan.
--   - PUANI SADECE OYUNU BİTİREN ALIR. Kısmi puan yoktur (dolu kutuya, doğru soruya ayrı puan verilmez).
--       Bitirmek: Kesişim ve Bonservis 5/5 doğru | Izgara 9/9 kutu | Bingo 12/12 kutu | Top 10 10/10 oyuncu.
--       Pes edilen, süresi dolan, canı biten ya da eksik biten oyunun puanı null'dır, tabloya girmez.
--   - Süresiz oynanan oyunlara puan verilmez (puan null). Top 10 istisnadır: süresi yoktur ama canı vardır, hep puanlanır.
--   - Puan oyun bitince ('basladi' -> 'tamamlandi') sunucuda tetikleyiciyle yazılır. İstemci puanı yazamaz.
--   - Puan = yuvarla(100 x zorluk çarpanı x süre çarpanı) + hız bonusu
--       zorluk çarpanı:        kolay 1.0 | orta 1.5 | zor 2.0 | Bingo ve Top 10 (tek mod) 1.5
--       süre çarpanı:          90 sn 1.0 | 60 sn 1.25 | 30 sn 1.5 | Top 10 1.0
--       hız bonusu:            yuvarla(ana puan x 0.2 x kalan saniye / toplam saniye). En fazla ana puanın %20'si.
--       Top 10'un puanı tektir: 150.
--   - Süre ilk hamleden önce seçilmelidir: süresiz başlayıp sonradan süre eklemek (puan kazanmak için) engellenir.
--   - Süresi dolup kullanıcı geri dönmediği için açık kalan oyunlar her dakika kapatılır (pg_cron).
--   - Liderlik tablosunda Google adı ya da fotoğrafı gösterilmez; takma ad gösterilir (profiller). Takma adı olmayan
--     kullanıcı "Oyuncu 3FA9" gibi görünür.
--   - Bu dosyadan önce bitmiş oyunlara puan verilmez (034'ten önceki skorlar istemciden yazılıyordu, güvenilmez).
--
-- Kontrol (çalıştırdıktan sonra):
--   select puan_hesapla('kesisim_zor', null, null, 10, 30, now() - interval '22 seconds', now());
--     -> {"puan": 316, "bitti": true, "hiz_bonusu": 16, ...}
--   select puan_hesapla('kesisim_zor', null, null, 8, 30, now() - interval '22 seconds', now());
--     -> {"puan": null, "sebep": "bitirilemedi", ...}
--   select jobname, schedule from cron.job where jobname = 'suresi-dolan-oyunlar';  -> 1 satır, '* * * * *'

begin;

create extension if not exists pg_cron;

-- 1) Puan alanları
alter table public.kullanici_oyun_gecmisi
    add column if not exists puan integer,
    add column if not exists puan_detay jsonb,
    add column if not exists bitis_zamani timestamptz;

create index if not exists kullanici_oyun_gecmisi_puan_idx
    on public.kullanici_oyun_gecmisi (tarih) where puan is not null;
create index if not exists kullanici_oyun_gecmisi_acik_sureli_idx
    on public.kullanici_oyun_gecmisi (sure_baslangic) where durum = 'basladi' and sure_saniye is not null;

-- 2) Puan hesabı. Saf fonksiyon: kayıt yazmaz. Uygulamaya kapalıdır, tetikleyici çağırır.
--    Dönüş: { puan, bitti, zorluk_carpani, sure_carpani, sure, kalan_saniye, hiz_bonusu }
--    puan null: puansız oyun ('sebep': 'suresiz' ya da 'bitirilemedi').
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
    c_taban constant numeric := 100;
    v_oyun text := split_part(p_oyun_tipi, '_', 1);
    v_zorluk text := split_part(p_oyun_tipi, '_', 2);
    v_skor integer := greatest(coalesce(p_skor, 0), 0);
    v_bitti boolean;
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

    -- Oyunu bitirmek: en yüksek skor (Kesişim/Bonservis'te skor doğru x 2'dir)
    v_bitti := case v_oyun
        when 'kesisim' then v_skor >= 10
        when 'bonservis' then v_skor >= 10
        when 'izgara' then v_skor >= 9
        when 'bingo' then v_skor >= 12
        when 'top10' then v_skor >= 10
    end;
    if v_bitti is null then
        return jsonb_build_object('puan', null, 'sebep', 'bilinmeyen_oyun');
    end if;
    if not v_bitti then
        return jsonb_build_object('puan', null, 'sebep', 'bitirilemedi', 'bitti', false);
    end if;

    v_zorluk_c := case
        when v_oyun in ('bingo', 'top10') then 1.5
        when v_zorluk = 'kolay' then 1.0
        when v_zorluk = 'orta' then 1.5
        when v_zorluk = 'zor' then 2.0
        else 1.0                                       -- eski, zorluksuz kesisim/bonservis kayıtları
    end;

    v_sure_c := case p_sure_saniye when 30 then 1.5 when 60 then 1.25 else 1.0 end;

    v_ana := round(c_taban * v_zorluk_c * v_sure_c)::integer;

    if p_sure_saniye is not null and p_sure_baslangic is not null and p_bitis is not null then
        v_kalan := least(p_sure_saniye,
                         greatest(0, p_sure_saniye - extract(epoch from (p_bitis - p_sure_baslangic))));
        v_hiz := round(v_ana * 0.2 * v_kalan / p_sure_saniye)::integer;
    end if;

    return jsonb_build_object(
        'puan', v_ana + v_hiz,
        'bitti', true,
        'zorluk_carpani', v_zorluk_c,
        'sure_carpani', v_sure_c,
        'sure', p_sure_saniye,
        'kalan_saniye', floor(v_kalan),
        'hiz_bonusu', v_hiz);
end;
$$;

revoke execute on function public.puan_hesapla(text, uuid, uuid, integer, integer, timestamptz, timestamptz)
    from public, anon, authenticated;

-- 3) Puanı yazan tetikleyici. 'basladi' -> 'tamamlandi' geçişinde bir kez çalışır; diğer güncellemelerde puan
--    alanları eski hâlinde kalır. Tetikleyiciler isim sırasıyla çalışır: oyun_suresi_kontrol (süre dolduysa skoru
--    kilitleyip kaydı kapatır) bundan önce çalışır, puan kilitli skordan hesaplanır.
create or replace function public.puan_yaz()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_sure integer := new.sure_saniye;
    v_baslangic timestamptz := new.sure_baslangic;
begin
    if old.durum = 'basladi' and new.durum = 'tamamlandi' then
        -- Izgara'nın süresi ayrı tablodadır (013)
        if new.oyun_tipi like 'izgara\_%' then
            select s.sure_saniye, s.baslangic into v_sure, v_baslangic
            from public.izgara_sureleri s
            where s.kullanici_id = new.kullanici_id and s.oyun_id = new.oyun_id;
        end if;

        new.bitis_zamani := now();
        new.puan_detay := public.puan_hesapla(new.oyun_tipi, new.kullanici_id, new.oyun_id, new.skor,
                                              v_sure, v_baslangic, new.bitis_zamani);
        new.puan := (new.puan_detay ->> 'puan')::integer;
    else
        new.puan := old.puan;
        new.puan_detay := old.puan_detay;
        new.bitis_zamani := old.bitis_zamani;
    end if;
    return new;
end;
$$;

revoke execute on function public.puan_yaz() from public, anon, authenticated;

drop trigger if exists puan_yaz on public.kullanici_oyun_gecmisi;
create trigger puan_yaz
    before update on public.kullanici_oyun_gecmisi
    for each row execute function public.puan_yaz();

-- İstemci kayıt açarken puan alanlarını dolduramaz (açma politikası 037'de, ona dokunulmaz)
create or replace function public.puan_alanlarini_bosalt()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    new.puan := null;
    new.puan_detay := null;
    new.bitis_zamani := null;
    return new;
end;
$$;

revoke execute on function public.puan_alanlarini_bosalt() from public, anon, authenticated;

drop trigger if exists puan_alanlarini_bosalt on public.kullanici_oyun_gecmisi;
create trigger puan_alanlarini_bosalt
    before insert on public.kullanici_oyun_gecmisi
    for each row execute function public.puan_alanlarini_bosalt();

-- 4) Süre ilk hamleden önce seçilmelidir
--    Kesişim, Bonservis, Bingo: süre kullanici_oyun_gecmisi'nde (oyun_sureyi_baslat yazar)
create or replace function public.sure_ilk_hamleden_once()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if old.sure_saniye is null and new.sure_saniye is not null then
        if jsonb_array_length(old.ilerleme) > 0
           or exists (select 1 from public.bingo_hamleleri h
                      where h.kullanici_id = old.kullanici_id and h.oyun_id = old.oyun_id) then
            raise exception 'Süre oyun başlamadan seçilmelidir' using hint = 'sure_gec';
        end if;
    end if;
    return new;
end;
$$;

revoke execute on function public.sure_ilk_hamleden_once() from public, anon, authenticated;

drop trigger if exists sure_ilk_hamleden_once on public.kullanici_oyun_gecmisi;
create trigger sure_ilk_hamleden_once
    before update of sure_saniye on public.kullanici_oyun_gecmisi
    for each row execute function public.sure_ilk_hamleden_once();

--    Izgara: süre izgara_sureleri'nde (izgara_sureyi_baslat yazar)
create or replace function public.izgara_sure_ilk_tahminden_once()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if exists (select 1 from public.izgara_tahminleri t
               where t.kullanici_id = new.kullanici_id and t.oyun_id = new.oyun_id) then
        raise exception 'Süre oyun başlamadan seçilmelidir' using hint = 'sure_gec';
    end if;
    return new;
end;
$$;

revoke execute on function public.izgara_sure_ilk_tahminden_once() from public, anon, authenticated;

drop trigger if exists izgara_sure_ilk_tahminden_once on public.izgara_sureleri;
create trigger izgara_sure_ilk_tahminden_once
    before insert on public.izgara_sureleri
    for each row execute function public.izgara_sure_ilk_tahminden_once();

-- 5) Süresi dolmuş açık oyunları kapatır (kullanıcı geri dönmese de puanı yazılsın, tabloya girsin).
--    Kapatma tetikleyicileri çalıştırır: skor kilitlenir, puan yazılır. 3 saniye tolerans 018 ile aynıdır.
create or replace function public.suresi_dolan_oyunlari_kapat()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_sayi integer;
    v_toplam integer := 0;
begin
    update public.kullanici_oyun_gecmisi g
    set durum = 'tamamlandi'
    where g.durum = 'basladi'
      and g.sure_saniye is not null
      and now() > g.sure_baslangic + make_interval(secs => g.sure_saniye + 3);
    get diagnostics v_sayi = row_count;
    v_toplam := v_toplam + v_sayi;

    update public.kullanici_oyun_gecmisi g
    set durum = 'tamamlandi'
    from public.izgara_sureleri s
    where s.kullanici_id = g.kullanici_id
      and s.oyun_id = g.oyun_id
      and g.durum = 'basladi'
      and now() > s.baslangic + make_interval(secs => s.sure_saniye + 3);
    get diagnostics v_sayi = row_count;
    return v_toplam + v_sayi;
end;
$$;

revoke execute on function public.suresi_dolan_oyunlari_kapat() from public, anon, authenticated;

select cron.schedule('suresi-dolan-oyunlar', '* * * * *', 'select public.suresi_dolan_oyunlari_kapat()');

-- 6) Profil: liderlik tablosunda görünen takma ad. Hesap silinince satır gider (033 kullanici_id kolonlu her
--    tabloyu siler; ayrıca auth.users'a cascade).
create table if not exists public.profiller (
    kullanici_id uuid primary key references auth.users (id) on delete cascade,
    takma_ad text not null check (char_length(takma_ad) between 3 and 16),
    gizli boolean not null default false,           -- true: liderlik tablosunda görünmez (hile, uygunsuz ad)
    takma_ad_degisim timestamptz not null default now(),
    created_at timestamptz not null default now()
);

-- Benzersizlik büyük/küçük harf ve ı/i farkı gözetmez ("BEŞİKTAŞLI" ile "beşiktaşlı" aynı sayılır)
create unique index if not exists profiller_takma_ad_idx
    on public.profiller (translate(lower(takma_ad), U&'\0131\0307', 'i'));

alter table public.profiller enable row level security;

drop policy if exists "profiller_okuma" on public.profiller;
create policy "profiller_okuma" on public.profiller
    for select to authenticated
    using (kullanici_id = (select auth.uid()));

-- Takma adlarda geçemeyecek kelimeler (küçük harf). Liste Table Editor'dan da büyütülebilir.
create table if not exists public.yasakli_kelimeler (
    kelime text primary key
);

alter table public.yasakli_kelimeler enable row level security;

insert into public.yasakli_kelimeler (kelime) values
    ('amk'), ('aq'), ('sik'), ('siktir'), ('orospu'), ('pic'), ('piç'), ('yarak'), ('yarrak'), ('got'), ('göt'),
    ('amcik'), ('amcık'), ('kahpe'), ('ibne'), ('pezevenk'), ('gavat'), ('fuck'), ('shit'), ('bitch'),
    ('admin'), ('footylore'), ('moderator'), ('destek')
on conflict do nothing;

-- Varsayılan görünen ad: "Oyuncu 3FA9" (boşluk içerdiği için kimse seçemez, çakışmaz)
create or replace function public.varsayilan_ad(p_kullanici uuid)
returns text
language sql
immutable
set search_path = ''
as $$
    select 'Oyuncu ' || upper(left(replace(p_kullanici::text, '-', ''), 4));
$$;

-- Kendi profilin: { takma_ad, varsayilan, degistirilebilir_tarih }
create or replace function public.profil_getir()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_kullanici uuid := (select auth.uid());
    v_profil record;
begin
    if v_kullanici is null then
        raise exception 'Giriş yapılmamış';
    end if;

    select p.takma_ad, p.takma_ad_degisim into v_profil
    from public.profiller p where p.kullanici_id = v_kullanici;

    if not found then
        return jsonb_build_object('takma_ad', public.varsayilan_ad(v_kullanici), 'varsayilan', true,
                                  'degistirilebilir_tarih', null);
    end if;
    return jsonb_build_object('takma_ad', v_profil.takma_ad, 'varsayilan', false,
                              'degistirilebilir_tarih', v_profil.takma_ad_degisim + interval '7 days');
end;
$$;

revoke execute on function public.profil_getir() from public, anon;
grant execute on function public.profil_getir() to authenticated;

-- Takma adı kaydeder. Kurallar: 3-16 karakter; harf (Türkçe dahil), rakam, _ ve . ; büyük/küçük harf farkı
-- gözetmeden benzersiz; yasaklı kelime içeremez; ilk seçimden sonra 7 günde bir değiştirilebilir.
-- Hatalar hint ile döner: takma_ad_gecersiz, takma_ad_yasakli, takma_ad_alinmis, takma_ad_erken
create or replace function public.takma_ad_kaydet(p_ad text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_kullanici uuid := (select auth.uid());
    v_ad text := btrim(coalesce(p_ad, ''));
    v_sade text;
    v_degisim timestamptz;
begin
    if v_kullanici is null then
        raise exception 'Giriş yapılmamış';
    end if;

    if v_ad !~ '^[A-Za-z0-9_.ÇĞİÖŞÜçğıöşü]{3,16}$' then
        raise exception 'Takma ad 3-16 karakter olmalı; harf, rakam, _ ve . kullanılabilir'
            using hint = 'takma_ad_gecersiz';
    end if;

    -- Yasaklı kelime kontrolü: küçük harf, Türkçe harfler sadeleştirilmiş, rakamlar harfe çevrilmiş (0->o, 1->i,
    -- 3->e, 4->a). 5 harf ve üstü kelimeler adın içinde aranır; kısa kelimeler (amk, sik, got ...) sadece _ ya da .
    -- ile ayrılmış parça olarak aranır, yoksa "Besiktas", "Gotze" gibi adlar takılırdı.
    v_sade := translate(lower(v_ad), 'çğıöşü0134' || chr(775), 'cgiosuoiea');
    if exists (
        select 1 from public.yasakli_kelimeler y
        cross join lateral (select translate(lower(y.kelime), 'çğıöşü', 'cgiosu') as k) x
        where (char_length(x.k) >= 5 and position(x.k in translate(v_sade, '_.', '')) > 0)
           or (char_length(x.k) < 5 and x.k = any (regexp_split_to_array(v_sade, '[_.]')))
    ) then
        raise exception 'Bu takma ad kullanılamaz' using hint = 'takma_ad_yasakli';
    end if;

    select p.takma_ad_degisim into v_degisim
    from public.profiller p where p.kullanici_id = v_kullanici
    for update;

    if found and now() < v_degisim + interval '7 days' then
        raise exception 'Takma ad 7 günde bir değiştirilebilir' using hint = 'takma_ad_erken';
    end if;

    begin
        insert into public.profiller (kullanici_id, takma_ad)
        values (v_kullanici, v_ad)
        on conflict (kullanici_id) do update
            set takma_ad = excluded.takma_ad, takma_ad_degisim = now();
    exception when unique_violation then
        raise exception 'Bu takma ad alınmış' using hint = 'takma_ad_alinmis';
    end;

    return v_ad;
end;
$$;

revoke execute on function public.takma_ad_kaydet(text) from public, anon;
grant execute on function public.takma_ad_kaydet(text) to authenticated;

-- 7) Liderlik tablosu
--    p_donem: 'gun' (bugün), 'hafta' (Pazartesi'den bugüne), 'tum' (tüm zamanlar). Günler Türkiye saatiyle,
--    oyunun günüdür (kullanici_oyun_gecmisi.tarih).
--    p_oyun: null (bütün oyunlar) ya da 'kesisim', 'bonservis', 'izgara', 'bingo', 'top10'.
--    Eşit puanda sıra numarası aynıdır; listede önce bitiren üstte görünür.
--    Dönüş: { liste: [ { sira, ad, puan, oyun, ben } ], ben: { sira, ad, puan, oyun } | null, katilimci }
create or replace function public.liderlik_tablosu(p_donem text, p_oyun text default null, p_adet integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_kullanici uuid := (select auth.uid());
    v_bugun date := public.bugunun_tarihi();
    v_bas date;
    v_adet integer := least(greatest(coalesce(p_adet, 50), 1), 100);
    v_sonuc jsonb;
begin
    if v_kullanici is null then
        raise exception 'Giriş yapılmamış';
    end if;

    v_bas := case p_donem
        when 'gun' then v_bugun
        when 'hafta' then date_trunc('week', v_bugun)::date
        when 'tum' then date '2000-01-01'
    end;
    if v_bas is null then
        raise exception 'Geçersiz dönem';
    end if;
    if p_oyun is not null and p_oyun not in ('kesisim', 'bonservis', 'izgara', 'bingo', 'top10') then
        raise exception 'Geçersiz oyun';
    end if;

    with toplam as (
        select g.kullanici_id,
               sum(g.puan)::integer as puan,
               count(*)::integer as oyun,
               max(g.bitis_zamani) as son
        from public.kullanici_oyun_gecmisi g
        where g.puan is not null
          and g.tarih between v_bas and v_bugun
          and (p_oyun is null or split_part(g.oyun_tipi, '_', 1) = p_oyun)
        group by g.kullanici_id
    ),
    sirali as (
        select t.kullanici_id, t.puan, t.oyun,
               coalesce(p.takma_ad, public.varsayilan_ad(t.kullanici_id)) as ad,
               rank() over (order by t.puan desc)::integer as sira,
               row_number() over (order by t.puan desc, t.son asc) as n
        from toplam t
        left join public.profiller p on p.kullanici_id = t.kullanici_id
        where not coalesce(p.gizli, false)
    )
    select jsonb_build_object(
        'liste', coalesce((
            select jsonb_agg(jsonb_build_object('sira', s.sira, 'ad', s.ad, 'puan', s.puan, 'oyun', s.oyun,
                                                'ben', s.kullanici_id = v_kullanici) order by s.n)
            from sirali s where s.n <= v_adet), '[]'::jsonb),
        'ben', (
            select jsonb_build_object('sira', s.sira, 'ad', s.ad, 'puan', s.puan, 'oyun', s.oyun)
            from sirali s where s.kullanici_id = v_kullanici),
        'katilimci', (select count(*) from sirali))
    into v_sonuc;

    return v_sonuc;
end;
$$;

revoke execute on function public.liderlik_tablosu(text, text, integer) from public, anon;
grant execute on function public.liderlik_tablosu(text, text, integer) to authenticated;

commit;
