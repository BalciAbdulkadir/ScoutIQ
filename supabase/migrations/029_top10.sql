-- 029: Top 10 oyunu (Mod 5)
-- Supabase SQL Editor'da tek seferde çalıştırılır. Hata olursa hiçbir değişiklik uygulanmaz.
-- 028_ballon_dor.sql'den sonra çalıştırılmalıdır (Ballon d'Or soruları ballon_dor_siralamalari'ndan üretilir).
--
-- Kurallar (kurallar/scoutiq-top10-kurallar.md, ürün sahibinin kararlarıyla):
--   - Günde tek soru vardır (oyun_tipi 'top10'); zorluk modu ve süre yoktur. Kullanıcı günde bir kez oynar.
--   - Ekranda bir başlık (ör. "Galatasaray'ın en pahalı 10 transferi") ve 1'den 10'a sıralı 10 satır vardır.
--     Her satırda ipucu olarak oyuncunun uyruğunun bayrağı açıktır.
--   - Kullanıcı oyuncuyu öneri listesinden seçer. Oyuncu listedeyse kendi sırasındaki satıra yerleşir.
--   - Can yoktur: yanlış tahminin cezası yoktur. Aynı oyuncu ikinci kez seçilirse tahmin sayılmaz.
--   - Her bulunan oyuncu 1 puandır (en fazla 10). Oyun 10 oyuncu bulununca ya da pes edilince biter.
--   - Liste, sıraları ve değerleriyle soru üretilirken sabitlenir (top10_cevaplari). Kaynak veri sonradan değişse de
--     o günün sorusu değişmez. Cevaplar oyun bitmeden uygulamaya gönderilmez; doğruluk sunucuda kontrol edilir.
--   - Listede aynı isimli oyuncular tek satır olduğu için (oyuncu_ara), Izgara'daki gibi isim eşleşmesi yeterli sayılır.
--
-- gunluk_oyunlar.soru_verisi biçimi (backend DailyQuestionJob üretir; cevaplar yoktur):
--   { "sablon": "T1", "baslik": "...", "alt_baslik": "...", "satirlar": [ { "sira": 1, "ulke": "Spain", "bayrak": "<url>" } x10 ] }

begin;

-- 1) Yeni oyun tipi
alter table public.gunluk_oyunlar drop constraint gunluk_oyunlar_oyun_tipi_check;
alter table public.gunluk_oyunlar add constraint gunluk_oyunlar_oyun_tipi_check
    check (oyun_tipi in ('kesisim', 'bonservis',
                         'kesisim_kolay', 'kesisim_orta', 'kesisim_zor',
                         'bonservis_kolay', 'bonservis_orta', 'bonservis_zor',
                         'izgara_kolay', 'izgara_orta', 'izgara_zor',
                         'bingo', 'bingo_kolay', 'bingo_orta', 'bingo_zor',
                         'top10'));

alter table public.kullanici_oyun_gecmisi drop constraint kullanici_oyun_gecmisi_oyun_tipi_check;
alter table public.kullanici_oyun_gecmisi add constraint kullanici_oyun_gecmisi_oyun_tipi_check
    check (oyun_tipi in ('kesisim', 'bonservis',
                         'kesisim_kolay', 'kesisim_orta', 'kesisim_zor',
                         'bonservis_kolay', 'bonservis_orta', 'bonservis_zor',
                         'izgara_kolay', 'izgara_orta', 'izgara_zor',
                         'bingo', 'bingo_kolay', 'bingo_orta', 'bingo_zor',
                         'top10'));

-- 2) Günün sorusunun şablonu ve değişkeni. Tekrar ve çeşitlilik kuralları buradan kontrol edilir (backend).
--    Uygulamaya kapalıdır (politika yok).
create table public.top10_sorulari (
    oyun_id uuid primary key references public.gunluk_oyunlar (id) on delete cascade,
    tarih date not null,
    sablon varchar not null,                   -- T1, T2 ... B1
    anahtar varchar not null,                  -- Şablonun değişkeni: kulüp ID'si, sezon, yıl ...
    eksen varchar not null                     -- transfer, ballon_dor
);

create index top10_sorulari_tarih_idx on public.top10_sorulari (tarih);
alter table public.top10_sorulari enable row level security;

-- 3) Günün cevap listesi, sıraları ve değerleriyle. Uygulamaya kapalıdır: fonksiyonlar okur.
create table public.top10_cevaplari (
    oyun_id uuid not null references public.gunluk_oyunlar (id) on delete cascade,
    sira smallint not null check (sira between 1 and 10),
    oyuncu_id uuid not null references public.oyuncular (id) on delete cascade,
    oyuncu_isim text not null,
    deger text not null,                       -- Ekranda gösterilen değer: "€222 mn", "1055 puan" ...
    primary key (oyun_id, sira)
);

alter table public.top10_cevaplari enable row level security;

-- 4) Kullanıcının tahminleri. sira null: yanlış tahmin. Satırlar sadece top10_tahmin ile eklenir.
create table public.top10_tahminleri (
    id uuid primary key default gen_random_uuid(),
    kullanici_id uuid not null,
    oyun_id uuid not null references public.gunluk_oyunlar (id) on delete cascade,
    oyuncu_id uuid not null references public.oyuncular (id) on delete cascade,
    oyuncu_isim text not null,
    sira smallint check (sira between 1 and 10),
    olusturma_zamani timestamptz not null default now(),
    unique (kullanici_id, oyun_id, oyuncu_isim),
    unique (kullanici_id, oyun_id, sira)
);

alter table public.top10_tahminleri enable row level security;

create policy "top10_tahminleri_okuma" on public.top10_tahminleri
    for select to authenticated
    using (kullanici_id = (select auth.uid()));

-- 5) Tahmin. Listeden seçilen oyuncunun id'sini alır; oyuncu listedeyse kendi sırasına yerleşir.
--    Oyun kaydı (kullanici_oyun_gecmisi) uygulama tarafından 'basladi' olarak açılmış olmalıdır.
--    Dönüş: { dogru, sira, deger, tekrar, oyuncu_isim, foto_url, skor, bitti }
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

    -- Listede bu isimde ve henüz bulunmamış bir oyuncu varsa onun sırası
    select c.sira, c.deger into v_sira, v_deger
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
        'foto_url', v_foto, 'skor', v_skor, 'bitti', v_bitti);
end;
$$;

revoke execute on function public.top10_tahmin(uuid, uuid) from public, anon;
grant execute on function public.top10_tahmin(uuid, uuid) to authenticated;

-- 6) Pes etme: oyun o anki skorla (bulunan oyuncu sayısı) biter
create or replace function public.top10_pes_et(p_oyun_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_kullanici uuid := (select auth.uid());
    v_skor integer;
begin
    if v_kullanici is null then
        raise exception 'Giriş yapılmamış';
    end if;

    select count(sira) into v_skor
    from public.top10_tahminleri
    where kullanici_id = v_kullanici and oyun_id = p_oyun_id;

    update public.kullanici_oyun_gecmisi
    set skor = v_skor, durum = 'tamamlandi'
    where kullanici_id = v_kullanici
      and oyun_id = p_oyun_id
      and oyun_tipi = 'top10'
      and durum = 'basladi';

    return v_skor;
end;
$$;

revoke execute on function public.top10_pes_et(uuid) from public, anon;
grant execute on function public.top10_pes_et(uuid) to authenticated;

-- 7) Bulunan oyuncuların değerleri her zaman; bütün liste sadece oyun bittikten sonra döner
create or replace function public.top10_cevaplar(p_oyun_id uuid)
returns table (sira integer, oyuncu_isim text, foto_url text, deger text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_kullanici uuid := (select auth.uid());
    v_bitti boolean;
begin
    if v_kullanici is null then
        raise exception 'Giriş yapılmamış';
    end if;

    select exists (
        select 1 from public.kullanici_oyun_gecmisi g
        where g.kullanici_id = v_kullanici and g.oyun_id = p_oyun_id and g.durum = 'tamamlandi'
    ) into v_bitti;

    return query
    select c.sira::integer, c.oyuncu_isim, o.foto_url, c.deger
    from public.top10_cevaplari c
    join public.oyuncular o on o.id = c.oyuncu_id
    where c.oyun_id = p_oyun_id
      and (v_bitti or exists (
          select 1 from public.top10_tahminleri t
          where t.kullanici_id = v_kullanici and t.oyun_id = p_oyun_id and t.sira = c.sira
      ))
    order by c.sira;
end;
$$;

revoke execute on function public.top10_cevaplar(uuid) from public, anon;
grant execute on function public.top10_cevaplar(uuid) to authenticated;

-- 8) En çok kulüp değiştiren oyuncular (T7 şablonu için): soru havuzundaki oyuncuların transfer kayıtlarındaki
--    farklı kulüp sayısı. Kulüpsüz, emekli, ara verdi ve bilinmeyen kayıtlar (Transfermarkt'ın sahte kulüpleri) sayılmaz.
--    Sadece backend çağırır.
create or replace function public.top10_kulup_sayilari(p_adet integer default 30)
returns table (oyuncu_id uuid, kulup_sayisi integer)
language sql
stable
set search_path = ''
as $$
    select t.oyuncu_id, count(distinct k.kulup)::integer as kulup_sayisi
    from public.transferler t
    join public.oyuncular o on o.id = t.oyuncu_id
    cross join lateral (values (t.eski_kulup_tm_id), (t.yeni_kulup_tm_id)) as k (kulup)
    where coalesce(o.kademe_override, o.kademe) in ('unlu', 'bilinen', 'diger')
      and k.kulup is not null
      and k.kulup not in ('515', '123', '2113', '75')
    group by t.oyuncu_id
    order by kulup_sayisi desc, t.oyuncu_id
    limit p_adet;
$$;

revoke execute on function public.top10_kulup_sayilari(integer) from public, anon, authenticated;

commit;
