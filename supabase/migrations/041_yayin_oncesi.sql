-- 041: Yayın öncesi: zorunlu güncelleme ve takma ad bildirme
-- Supabase SQL Editor'da tek seferde çalıştırılır. Hata olursa hiçbir değişiklik uygulanmaz.
-- 040_oyun_ac.sql'den sonra çalıştırılmalıdır. Tekrar çalıştırılabilir.
-- Eski uygulama sürümünü bozmaz: yeni tablolar ve fonksiyon ekler; liderlik_tablosu'nun dönüşüne alan eklenir.
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
-- 2) Takma ad bildirme (Google Play kullanıcı içeriği politikası): public.takma_ad_bildirimleri
--    Liderlik tablosunda başkasının satırına uzun basan kullanıcı o takma adı bildirir (takma_ad_bildir).
--    - Kendini bildiremez. Aynı kişiyi ikinci kez bildirmek sayılmaz (birincil anahtar: bildiren + bildirilen).
--    - Farklı 3 kişi bildirince profiller.gizli = true olur: kullanıcı liderlik tablosundan gizlenir (038). Gizliliği
--      kaldırmak elle yapılır. Kullanıcı adını değiştirse de bildirimler ve gizlilik kalır.
--    - Sadece seçilmiş takma ad bildirilebilir. Takma ad seçmemiş kullanıcının adını ("Oyuncu 3FA9") sistem üretir,
--      bildirilemez (ürün sahibinin 22 Kasım 2026 kararı).
--    - Tabloya istemci doğrudan yazamaz, okuyamaz: RLS açık, politika yok, izinler alındı. Sadece takma_ad_bildir
--      (security definer) yazar.
--    - Hesap silmede iki taraf da gider: bildirenin satırlarını hesabimi_sil (033_hesabimi_sil.sql, "kullanici_id"
--      kolonlu bütün tabloları siler) temizler, bildirilenin satırları auth.users silinince cascade ile gider.
--    liderlik_tablosu (son hâli 038_puan_ve_liderlik.sql) listedeki her satıra kullanici_id ve varsayilan alanlarını
--    ekler: uygulama bildirimi bu kimlikle gönderir, varsayılan adlı satırda bildirme penceresini açmaz. Kimlik
--    sadece giriş yapmış kullanıcılara ve sadece listedeki (en fazla 100) kişiler için döner; RLS yüzünden kimlikle
--    başka bir tablo okunamaz (ürün sahibinin 22 Kasım 2026 kararı). Dönüş tipi jsonb kaldığı için eski sürüm
--    etkilenmez, fazla alanları okumaz.
--
-- Kontrol (çalıştırdıktan sonra):
--   select * from public.uygulama_surumu;                                            -> 1 satır, en_dusuk_surum_kodu = 1
--   select has_table_privilege('anon', 'public.uygulama_surumu', 'select');           -> true
--   select has_table_privilege('authenticated', 'public.uygulama_surumu', 'update');  -> false
--   select has_table_privilege('authenticated', 'public.takma_ad_bildirimleri', 'select');  -> false
--   select has_table_privilege('authenticated', 'public.takma_ad_bildirimleri', 'insert');  -> false
--   select has_function_privilege('authenticated', 'public.takma_ad_bildir(uuid)', 'execute');  -> true
--   select has_function_privilege('anon', 'public.takma_ad_bildir(uuid)', 'execute');           -> false

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
create table if not exists public.takma_ad_bildirimleri (
    kullanici_id uuid not null,                                                     -- bildiren
    bildirilen_id uuid not null references auth.users (id) on delete cascade,
    olusturma timestamptz not null default now(),
    primary key (kullanici_id, bildirilen_id)
);

-- Bir kişinin kaç kez bildirildiği bu kolondan sayılır
create index if not exists takma_ad_bildirimleri_bildirilen_idx on public.takma_ad_bildirimleri (bildirilen_id);

alter table public.takma_ad_bildirimleri enable row level security;
revoke all on public.takma_ad_bildirimleri from public, anon, authenticated;

-- Hatalar hint ile döner: kendini_bildiremez, varsayilan_ad (takma ad seçmemiş ya da olmayan kullanıcı)
create or replace function public.takma_ad_bildir(p_kullanici uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_kullanici uuid := (select auth.uid());
    c_gizleme_esigi constant integer := 3;
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

    -- Sadece seçilmiş takma ad: profil satırı yoksa ad sistemin ürettiği "Oyuncu 3FA9"dur
    if not exists (select 1 from public.profiller p where p.kullanici_id = p_kullanici) then
        raise exception 'Bu ad bildirilemez' using hint = 'varsayilan_ad';
    end if;

    insert into public.takma_ad_bildirimleri (kullanici_id, bildirilen_id)
    values (v_kullanici, p_kullanici)
    on conflict (kullanici_id, bildirilen_id) do nothing;

    if (select count(*) from public.takma_ad_bildirimleri b where b.bildirilen_id = p_kullanici) >= c_gizleme_esigi then
        update public.profiller set gizli = true
        where kullanici_id = p_kullanici and not gizli;
    end if;
end;
$$;

revoke execute on function public.takma_ad_bildir(uuid) from public, anon;
grant execute on function public.takma_ad_bildir(uuid) to authenticated;

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
