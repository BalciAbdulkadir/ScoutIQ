-- 002: Row Level Security politikaları
-- Uygulama (publishable key) sadece burada izin verilenleri yapabilir.
-- Secret key (data_miner, backend) RLS'e takılmaz.
--
-- DİKKAT: Bundan sonra backend'in de secret key kullanması gerekir. Publishable key ile
-- get_ortak_oyuncular boş döner (kariyer_gecmisi kapalı) ve gunluk_oyunlar'a yazamaz.

begin;

alter table kulupler               enable row level security;
alter table oyuncular              enable row level security;
alter table kariyer_gecmisi        enable row level security;
alter table gunluk_oyunlar         enable row level security;
alter table kullanici_oyun_gecmisi enable row level security;
alter table skorlar                enable row level security;

-- Sabit veri: giriş yapmış kullanıcı okuyabilir, kimse yazamaz.
-- Anonim (giriş yapmamış) kullanıcı hiçbir şey göremez.
create policy "kulupler_okuma" on kulupler
    for select to authenticated using (true);

create policy "oyuncular_okuma" on oyuncular
    for select to authenticated using (true);

-- kariyer_gecmisi için politika yok: cevaplar bu tablodan hesaplandığı için uygulamaya kapalı.
-- Cevap kontrolü ileride sunucu tarafında bir fonksiyonla yapılacak.

-- Günlük oyunlar: sadece bugünün ve geçmiş günlerin oyunları okunabilir (Türkiye saatine göre).
-- Yarının önceden üretilmiş sorularına erişilemez.
create policy "gunluk_oyunlar_okuma" on gunluk_oyunlar
    for select to authenticated
    using (tarih <= (now() at time zone 'Europe/Istanbul')::date);

-- Kullanıcı oyun geçmişi: herkes sadece kendi kayıtlarını görür ve sadece bugün için kayıt ekler.
-- UPDATE ve DELETE politikası yok: kayıt bir kez atıldıktan sonra değiştirilemez ve silinemez,
-- böylece günde tek atış hakkı silinip sıfırlanamaz.
create policy "kullanici_oyun_gecmisi_okuma" on kullanici_oyun_gecmisi
    for select to authenticated
    using (kullanici_id = (select auth.uid()));

create policy "kullanici_oyun_gecmisi_ekleme" on kullanici_oyun_gecmisi
    for insert to authenticated
    with check (
        kullanici_id = (select auth.uid())
        and tarih = (now() at time zone 'Europe/Istanbul')::date
    );

-- skorlar şu an kullanılmıyor: politika yok, uygulamaya kapalı.

commit;
