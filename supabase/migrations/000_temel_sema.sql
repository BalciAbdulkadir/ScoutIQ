-- 000: Temel şema (dosyalardan önce elle kurulan 6 tablo ve get_ortak_oyuncular)
-- Bu tablolar SQL dosyaları tutulmaya başlanmadan önce Supabase panelinden kuruldu. Bu dosya onların 001'den önceki
-- hâlidir. Bugünkü tanımlar 20 Kasım 2026'da Supabase'den okundu; sonraki dosyaların eklediği her şey çıkarıldı.
--
-- BUGÜNKÜ SUPABASE'DE ÇALIŞTIRILMAZ: tablolar zaten var. Yanlışlıkla çalıştırılırsa bir şey değişmez
-- (if not exists), sadece get_ortak_oyuncular aynı tanımla yeniden yazılır.
-- Boş bir veritabanı kurulurken ilk dosya olarak çalıştırılır, sonra 001'den başlanarak sırayla devam edilir.
--
-- Sonraki dosyaların bu tablolara eklediği başlıca şeyler (burada yoktur):
--   001: transfermarkt_id kolonları, kariyer_gecmisi'nde not null + unique + yıl kontrolü, oyun tipi kısıtları
--   002: RLS ve okuma/ekleme politikaları
--   003: kullanici_oyun_gecmisi_gunluk_tek_idx (aynı kolonlarda zaten unique kısıt var, ikisi birden duruyor)
--   004, 005, 007, 009, 015, 017, 025, 032: oyuncular'a yeni kolonlar
--   008: kulupler.logo_url. Not: bugünkü Supabase'de bu kolon tablonun 4. kolonu, yani 008'den önce de vardı ve
--        008 orada büyük ihtimalle "kolon zaten var" hatası verdi. Boş veritabanında 008 çalışabilsin diye burada yoktur.
--   010: kulupler.lig boş olabilir
--   017: kariyer_gecmisi.mac_sayisi
--   018: kullanici_oyun_gecmisi'ne ilerleme, sure_saniye, sure_baslangic
--   024: kulupler.kademe
--
-- Gerekli eklenti: uuid-ossp (Supabase'de hazır gelir). unaccent 003'te kurulur.

begin;

create extension if not exists "uuid-ossp" with schema extensions;

-- Kulüpler (sabit veri)
create table if not exists public.kulupler (
    id uuid not null default uuid_generate_v4() primary key,
    isim varchar(255) not null,
    lig varchar(100) not null,
    created_at timestamptz default timezone('utc'::text, now())
);

-- Oyuncular (sabit veri)
create table if not exists public.oyuncular (
    id uuid not null default uuid_generate_v4() primary key,
    isim varchar(255) not null,
    uyruk varchar(100),
    aktif_durum boolean default true,
    created_at timestamptz default timezone('utc'::text, now())
);

-- Kariyer geçmişi (sabit veri)
create table if not exists public.kariyer_gecmisi (
    id uuid not null default uuid_generate_v4() primary key,
    oyuncu_id uuid references public.oyuncular (id) on delete cascade,
    kulup_id uuid references public.kulupler (id) on delete cascade,
    baslangic_yili integer,
    bitis_yili integer,
    bonservis_bedeli numeric(15, 2),
    created_at timestamptz default timezone('utc'::text, now())
);

create index if not exists idx_kariyer_kulup_id on public.kariyer_gecmisi (kulup_id);
create index if not exists idx_kariyer_oyuncu_id on public.kariyer_gecmisi (oyuncu_id);

-- Günlük oyunlar: her oyun tipi için günde bir oyun
create table if not exists public.gunluk_oyunlar (
    id uuid not null default uuid_generate_v4() primary key,
    oyun_tipi varchar(50) not null,
    tarih date not null,
    soru_verisi jsonb not null,
    created_at timestamptz default now(),
    unique (oyun_tipi, tarih)
);

-- Kullanıcının oyun geçmişi: kullanıcı başına her oyun tipi için günde bir kayıt
create table if not exists public.kullanici_oyun_gecmisi (
    id uuid not null default uuid_generate_v4() primary key,
    kullanici_id uuid references auth.users (id) on delete cascade,
    oyun_id uuid references public.gunluk_oyunlar (id) on delete cascade,
    oyun_tipi varchar(50) not null,
    tarih date not null,
    skor integer default 0,
    durum varchar(20) not null,
    created_at timestamptz default now(),
    unique (kullanici_id, oyun_tipi, tarih)
);

-- Skorlar: kullanılmıyor (002'de uygulamaya kapatıldı)
create table if not exists public.skorlar (
    id uuid not null default uuid_generate_v4() primary key,
    kullanici_id uuid not null,
    oyun_tarihi date default current_date,
    cozum_suresi integer,
    deneme_sayisi integer,
    puan integer,
    created_at timestamptz default timezone('utc'::text, now())
);

-- İki kulübün ortak oyuncuları. Eski backend kullanıyordu, bugün hiçbir kod çağırmıyor. Kullanıcının yetkisiyle
-- çalışır: uygulamadan çağrılınca kariyer_gecmisi kapalı olduğu için boş döner (002). Supabase'deki tanımın aynısıdır.
create or replace function public.get_ortak_oyuncular(kulup_a_id uuid, kulup_b_id uuid)
 returns table(oyuncu_id uuid, oyuncu_isim character varying, uyruk character varying)
 language plpgsql
as $function$
BEGIN
    RETURN QUERY
    SELECT DISTINCT o.id, o.isim, o.uyruk
    FROM oyuncular o
    INNER JOIN kariyer_gecmisi kg1 ON o.id = kg1.oyuncu_id
    INNER JOIN kariyer_gecmisi kg2 ON o.id = kg2.oyuncu_id
    WHERE kg1.kulup_id = kulup_a_id
      AND kg2.kulup_id = kulup_b_id;
END;
$function$;

commit;
