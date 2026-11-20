-- 016: oyuncu_basarilari tablosunda sadece oyunlarda anlamı olan başlıklar kalır
-- Kalanlar: Avrupa kupaları, veritabanındaki 6 ligin şampiyonluk, kupa ve süper kupaları,
-- büyük milli turnuvalar ve bireysel ödüller. Diğerleri (ör. Meksika kupası, katılım ve alt lig başlıkları) silinir.
-- Aynı liste data_miner/onem_verileri.py içindeki KALAN_BASLIKLAR'dadır; biri değişirse diğeri de değişmelidir.
-- 015_onem_verileri.sql'den sonra çalıştırılmalıdır.

begin;

delete from public.oyuncu_basarilari
where baslik not in (
    -- Avrupa kupaları (eski adlarıyla birlikte)
    'UEFA Champions League winner', 'European Champion Clubs'' Cup winner',
    'Europa League winner', 'Uefa Cup winner',
    'Uefa Supercup winner',
    -- 6 ligin şampiyonlukları
    'Turkish champion', 'English Champion', 'Spanish champion', 'Italian champion', 'German Champion', 'French champion',
    -- 6 ligin kupaları
    'Turkish cup winner', 'English FA Cup winner', 'Spanish cup winner', 'Italian cup winner', 'German cup winner',
    'French cup winner',
    -- 6 ligin süper kupaları
    'Turkish Super Cup winner', 'English Super Cup winner', 'Spanish Super Cup winner', 'Italian Super Cup winner',
    'German Super Cup winner', 'French Super Cup winner',
    -- Milli turnuvalar
    'World Cup winner', 'European champion', 'Copa América winner', 'Winner UEFA Nations League',
    -- Bireysel ödüller
    'Winner Ballon d''Or', 'The Best FIFA Men''s Player', 'UEFA Best Player in Europe', 'Golden Boot winner (Europe)'
);

commit;
