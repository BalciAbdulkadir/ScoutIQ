-- 041: Yayın öncesi: zorunlu güncelleme ve takma ad bildirme
-- Supabase SQL Editor'da tek seferde çalıştırılır. Hata olursa hiçbir değişiklik uygulanmaz.
-- 040_oyun_ac.sql'den sonra çalıştırılmalıdır. Tekrar çalıştırılabilir.
-- Eski uygulama sürümünü bozmaz: yeni tablolar ve fonksiyon ekler; liderlik_tablosu ve profil_getir'in dönüşüne
-- alan eklenir, profiller.takma_ad boş olabilir (eski sürüm adı profil_getir'den okur, boş ad görmez).
--
-- 1) Zorunlu güncelleme: public.uygulama_surumu
--    Tek satırlık tablo (id her zaman 1). Uygulama açılışta, girişten önce okur. Telefondaki sürüm kodu
--    (pubspec.yaml'daki "+"dan sonraki sayı, Android versionCode) en_dusuk_surum_kodu'ndan küçükse uygulama
--    kapatılamayan "Güncelleme gerekli" sayfasını gösterir. Okuma başarısız olursa (internet yok) uygulama engellenmez.
--    Okuma izni: anon ve authenticated sadece select yapabilir. Girişten önce okunduğu için anon da okur. Tabloda
--    cevabı ya da kullanıcıyı ele veren bir şey yoktur, sadece sürüm sınırı ve mesaj vardır.
--    Yazma izni kimsede yoktur. Değer SQL Editor'dan elle değiştirilmez: yeni bir SQL dosyasıyla değiştirilir
--    ("güncellemelerde dikkat edilecekler.md", 3. bölüm). Örnek:
--      update public.uygulama_surumu set en_dusuk_surum_kodu = 2 where id = 1;
--    guncelleme_mesaji boşsa uygulama kendi mesajını gösterir.
--
-- 2) Takma ad bildirme (Google Play kullanıcı içeriği politikası). Ürün sahibinin 22 Kasım 2026 kararları.
--    Amaç uygunsuz bir ADI tablodan kaldırmaktır, oyuncuyu değil: ceza ada verilir.
--    Liderlik tablosunda başkasının satırına uzun basan kullanıcı o takma adı bildirir (takma_ad_bildir).
--    - Kendini bildiremez. Sadece seçilmiş takma ad bildirilebilir; sistemin ürettiği "Oyuncu 3FA9" bildirilemez.
--    - Bildirmek için en az 3 farklı gün oyun bitirmiş olmak gerekir (sahte hesap açmanın maliyeti artar).
--    - Sayaç ad başına tutulur: bildirim, bildirilen adla birlikte yazılır. Sadece kullanıcının şu anki adına, o adı
--      aldıktan sonra yapılan bildirimler sayılır. Ad değişince sayaç sıfırlanır. Aynı kişi aynı adı bir kez sayılır.
--    - Farklı 3 kişi aynı adı bildirince kullanıcı GİZLENMEZ, sadece takma adı sıfırlanır: profiller.takma_ad boş olur,
--      tabloda varsayılan "Oyuncu XXXX" adıyla puanıyla kalır. Uygulama bir dahaki açılışta "Takma adın bildirildiği
--      için sıfırlandı, yeni bir ad seç" der (profil_getir'in sifirlandi alanı). Yeni ad 7 gün beklemeden seçilir.
--      Sıfırlanan ad aynı kullanıcı tarafından tekrar seçilemez. Yeni ad da bildirilirse tekrar sıfırlanır.
--    - Her sıfırlama public.takma_ad_sifirlamalari'na yazılır. Adı defalarca sıfırlanan kullanıcıya karar elle verilir;
--      örneğin ad değiştirmesi kilitlenir (profiller.takma_ad_kilitli = true, Table Editor'dan). Liste:
--        select s.kullanici_id, count(*) as sifirlama, max(s.olusturma) as son,
--               string_agg(s.eski_ad, ', ' order by s.olusturma) as adlar
--        from public.takma_ad_sifirlamalari s group by s.kullanici_id order by 2 desc, 3 desc;
--    - profiller.gizli hiçbir şeye otomatik bağlı değildir: sadece hile tespitinde elle verilen cezadır.
--    - Bildirim ve sıfırlama tablolarına istemci doğrudan yazamaz, okuyamaz: RLS açık, politika yok, izinler alındı.
--      Sadece security definer fonksiyonlar yazar.
--    - Hesap silmede iki taraf da gider: kullanici_id kolonu olan satırları hesabimi_sil (033_hesabimi_sil.sql) temizler
--      (bildirenin bildirimleri, kullanıcının sıfırlama kayıtları), bildirilenin satırları auth.users silinince cascade
--      ile gider.
--    - profil_getir ve takma_ad_kaydet: son hâlleri 038_puan_ve_liderlik.sql'de. Değişenler: boş takma ad (sıfırlanmış)
--      varsayılan ad sayılır, sifirlandi alanı döner; kilitli kullanıcı ad değiştiremez, sıfırlanmış kullanıcı 7 gün
--      beklemez, sıfırlanan adını tekrar alamaz.
--    liderlik_tablosu (son hâli 038_puan_ve_liderlik.sql) listedeki her satıra kullanici_id ve varsayilan alanlarını
--    ekler: uygulama bildirimi bu kimlikle gönderir, varsayılan adlı satırda bildirme penceresini açmaz. Kimlik
--    sadece giriş yapmış kullanıcılara ve sadece listedeki (en fazla 100) kişiler için döner; RLS yüzünden kimlikle
--    başka bir tablo okunamaz. Dönüş tipleri jsonb kaldığı için eski sürüm etkilenmez, fazla alanları okumaz.
--
-- Kontrol (çalıştırdıktan sonra):
--   select * from public.uygulama_surumu;                                            -> 1 satır, en_dusuk_surum_kodu = 1
--   select has_table_privilege('anon', 'public.uygulama_surumu', 'select');           -> true
--   select has_table_privilege('authenticated', 'public.uygulama_surumu', 'update');  -> false
--   select has_table_privilege('authenticated', 'public.takma_ad_bildirimleri', 'select');  -> false
--   select has_table_privilege('authenticated', 'public.takma_ad_bildirimleri', 'insert');  -> false
--   select has_function_privilege('authenticated', 'public.takma_ad_bildir(uuid)', 'execute');  -> true
--   select has_function_privilege('anon', 'public.takma_ad_bildir(uuid)', 'execute');           -> false
--   select has_table_privilege('authenticated', 'public.takma_ad_sifirlamalari', 'select'); -> false

begin;

-- 1) Zorunlu güncelleme
create table if not exists public.uygulama_surumu (
    id smallint primary key default 1 check (id = 1),
    en_dusuk_surum_kodu integer not null,
    guncelleme_mesaji text
);

alter table public.uygulama_surumu enable row level security;

revoke all on public.uygulama_surumu from public, anon, authenticated;
grant select on public.uygulama_surumu to anon, authenticated;

drop policy if exists "uygulama_surumu_okuma" on public.uygulama_surumu;
create policy "uygulama_surumu_okuma" on public.uygulama_surumu
    for select to anon, authenticated
    using (true);

-- Başlangıç: her sürüm açılır. Satır varsa dokunulmaz (sonradan yükseltilmiş değer tekrar çalıştırmada geri dönmez).
insert into public.uygulama_surumu (id, en_dusuk_surum_kodu) values (1, 1)
on conflict (id) do nothing;

-- 2) Takma ad bildirme
-- Boş takma ad: bildirimle sıfırlandı, varsayılan ad görünür. Benzersizlik indeksi (038) boş adları saymaz.
alter table public.profiller alter column takma_ad drop not null;
alter table public.profiller
    add column if not exists takma_ad_sifirlandi timestamptz,                -- doluysa: ad bildirimle sıfırlandı
    add column if not exists takma_ad_kilitli boolean not null default false; -- elle: true ise ad değiştirilemez

create table if not exists public.takma_ad_bildirimleri (
    kullanici_id uuid not null,                                                     -- bildiren
    bildirilen_id uuid not null references auth.users (id) on delete cascade,
    takma_ad text not null,                                                         -- bildirilen ad
    olusturma timestamptz not null default now(),
    primary key (kullanici_id, bildirilen_id, takma_ad)
);

create index if not exists takma_ad_bildirimleri_bildirilen_idx
    on public.takma_ad_bildirimleri (bildirilen_id, takma_ad);

alter table public.takma_ad_bildirimleri enable row level security;
revoke all on public.takma_ad_bildirimleri from public, anon, authenticated;

create table if not exists public.takma_ad_sifirlamalari (
    id bigint generated always as identity primary key,
    kullanici_id uuid not null references auth.users (id) on delete cascade,      -- adı sıfırlanan
    eski_ad text not null,
    bildirim_sayisi integer not null,
    olusturma timestamptz not null default now()
);

create index if not exists takma_ad_sifirlamalari_kullanici_idx on public.takma_ad_sifirlamalari (kullanici_id);

alter table public.takma_ad_sifirlamalari enable row level security;
revoke all on public.takma_ad_sifirlamalari from public, anon, authenticated;

-- Hatalar hint ile döner: kendini_bildiremez, varsayilan_ad (takma ad seçmemiş, adı sıfırlanmış ya da olmayan
-- kullanıcı), bildirim_icin_erken (bildiren en az 3 farklı gün oyun bitirmemiş)
create or replace function public.takma_ad_bildir(p_kullanici uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_kullanici uuid := (select auth.uid());
    c_sifirlama_esigi constant integer := 3;   -- bu kadar farklı kişi aynı adı bildirince ad sıfırlanır
    c_gerekli_gun constant integer := 3;       -- bildirmek için en az bu kadar farklı gün oyun bitirmiş olmak gerekir
    v_ad text;
    v_degisim timestamptz;
    v_sayi integer;
begin
    if v_kullanici is null then
        raise exception 'Giriş yapılmamış';
    end if;
    if p_kullanici is null then
        raise exception 'Bildirilecek kullanıcı yok';
    end if;
    if p_kullanici = v_kullanici then
        raise exception 'Kendi adını bildiremezsin' using hint = 'kendini_bildiremez';
    end if;

    if (select count(distinct g.tarih) from public.kullanici_oyun_gecmisi g
        where g.kullanici_id = v_kullanici and g.durum = 'tamamlandi') < c_gerekli_gun then
        raise exception 'Ad bildirmek için en az % farklı gün oyun bitirmiş olmalısın', c_gerekli_gun
            using hint = 'bildirim_icin_erken';
    end if;

    -- Sadece seçilmiş takma ad: profil yoksa ya da ad boşsa (sıfırlanmış) görünen ad sistemin ürettiği "Oyuncu 3FA9"dur
    select p.takma_ad, p.takma_ad_degisim into v_ad, v_degisim
    from public.profiller p where p.kullanici_id = p_kullanici
    for update;
    if v_ad is null then
        raise exception 'Bu ad bildirilemez' using hint = 'varsayilan_ad';
    end if;

    -- Aynı kişi aynı adı bir kez sayılır. Kullanıcı bu ada sonradan geri döndüyse eski bildirim tazelenir.
    insert into public.takma_ad_bildirimleri (kullanici_id, bildirilen_id, takma_ad)
    values (v_kullanici, p_kullanici, v_ad)
    on conflict (kullanici_id, bildirilen_id, takma_ad) do update set olusturma = now();

    -- Sayaç ad başına: şu anki ada, o ad alındıktan sonra yapılan bildirimler
    select count(*) into v_sayi
    from public.takma_ad_bildirimleri b
    where b.bildirilen_id = p_kullanici and b.takma_ad = v_ad and b.olusturma >= v_degisim;

    if v_sayi >= c_sifirlama_esigi then
        insert into public.takma_ad_sifirlamalari (kullanici_id, eski_ad, bildirim_sayisi)
        values (p_kullanici, v_ad, v_sayi);
        update public.profiller
        set takma_ad = null, takma_ad_sifirlandi = now()
        where kullanici_id = p_kullanici;
    end if;
end;
$$;

revoke execute on function public.takma_ad_bildir(uuid) from public, anon;
grant execute on function public.takma_ad_bildir(uuid) to authenticated;

-- Kendi profilin: { takma_ad, varsayilan, degistirilebilir_tarih, sifirlandi }
--   038'deki gövde. Değişen: boş takma ad (sıfırlanmış) varsayılan ad sayılır; sifirlandi: ad bildirimle sıfırlandı,
--   kullanıcı yeni ad seçene kadar true.
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

    select p.takma_ad, p.takma_ad_degisim, p.takma_ad_sifirlandi into v_profil
    from public.profiller p where p.kullanici_id = v_kullanici;

    if not found or v_profil.takma_ad is null then
        return jsonb_build_object('takma_ad', public.varsayilan_ad(v_kullanici), 'varsayilan', true,
                                  'degistirilebilir_tarih', null,
                                  'sifirlandi', found and v_profil.takma_ad_sifirlandi is not null);
    end if;
    return jsonb_build_object('takma_ad', v_profil.takma_ad, 'varsayilan', false,
                              'degistirilebilir_tarih', v_profil.takma_ad_degisim + interval '7 days',
                              'sifirlandi', false);
end;
$$;

revoke execute on function public.profil_getir() from public, anon;
grant execute on function public.profil_getir() to authenticated;

-- Takma adı kaydeder. 038'deki gövde ve kurallar; eklenenler:
--   - Kilitli kullanıcı (takma_ad_kilitli, elle verilir) adını değiştiremez.
--   - Adı sıfırlanmış kullanıcı yeni adı 7 gün beklemeden seçer.
--   - Kullanıcı bildirimle sıfırlanan bir adını tekrar seçemez (büyük/küçük harf ve ı/i farkı gözetilmez).
--   - Kaydedince sıfırlanma işareti kalkar.
-- Hatalar hint ile döner: takma_ad_gecersiz, takma_ad_yasakli, takma_ad_alinmis, takma_ad_erken, takma_ad_kilitli,
-- takma_ad_sifirlanmis
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
    v_profil record;
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

    select p.takma_ad, p.takma_ad_degisim, p.takma_ad_kilitli into v_profil
    from public.profiller p where p.kullanici_id = v_kullanici
    for update;

    if found and v_profil.takma_ad_kilitli then
        raise exception 'Takma adını değiştiremezsin' using hint = 'takma_ad_kilitli';
    end if;

    -- Ad bildirimle sıfırlandıysa (boş) beklemeden yeni ad seçilir
    if found and v_profil.takma_ad is not null and now() < v_profil.takma_ad_degisim + interval '7 days' then
        raise exception 'Takma ad 7 günde bir değiştirilebilir' using hint = 'takma_ad_erken';
    end if;

    if exists (
        select 1 from public.takma_ad_sifirlamalari s
        where s.kullanici_id = v_kullanici
          and translate(lower(s.eski_ad), U&'\0131\0307', 'i') = translate(lower(v_ad), U&'\0131\0307', 'i')
    ) then
        raise exception 'Bu ad bildirildiği için kullanılamaz' using hint = 'takma_ad_sifirlanmis';
    end if;

    begin
        insert into public.profiller (kullanici_id, takma_ad)
        values (v_kullanici, v_ad)
        on conflict (kullanici_id) do update
            set takma_ad = excluded.takma_ad, takma_ad_degisim = now(), takma_ad_sifirlandi = null;
    exception when unique_violation then
        raise exception 'Bu takma ad alınmış' using hint = 'takma_ad_alinmis';
    end;

    return v_ad;
end;
$$;

revoke execute on function public.takma_ad_kaydet(text) from public, anon;
grant execute on function public.takma_ad_kaydet(text) to authenticated;

-- Liderlik tablosu: 038'deki gövde; değişen tek şey liste satırlarına eklenen kullanici_id ve varsayilan alanları.
--    Dönüş: { liste: [ { sira, ad, puan, oyun, ben, kullanici_id, varsayilan } ], ben: { sira, ad, puan, oyun } | null,
--             katilimci }
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
               p.takma_ad is null as varsayilan,
               rank() over (order by t.puan desc)::integer as sira,
               row_number() over (order by t.puan desc, t.son asc) as n
        from toplam t
        left join public.profiller p on p.kullanici_id = t.kullanici_id
        where not coalesce(p.gizli, false)
    )
    select jsonb_build_object(
        'liste', coalesce((
            select jsonb_agg(jsonb_build_object('sira', s.sira, 'ad', s.ad, 'puan', s.puan, 'oyun', s.oyun,
                                                'ben', s.kullanici_id = v_kullanici,
                                                'kullanici_id', s.kullanici_id, 'varsayilan', s.varsayilan)
                             order by s.n)
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
