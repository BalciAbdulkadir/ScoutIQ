-- 024: Kulüp kademeleri
-- Supabase SQL Editor'da tek seferde çalıştırılır. Hata olursa hiçbir değişiklik uygulanmaz.
--
-- kulupler tablosuna kademe kolonu ekler ve takım listesindeki 42 kulübü doldurur:
--   buyuk    : 18 kulüp
--   bas_alti : 22 kulüp
--   diger    : 2 kulüp (Villarreal, Real Sociedad)
-- Listede olmayan kulüplerin kademesi boştur.
-- Bu dosya sadece veriyi ekler: oyunlar kulüp listesini hâlâ koddan okur (KesisimSoruSecici.BuyukKulupler / BasAltiKulupler).
-- Kulüpler Transfermarkt ID'si ile eşleştirilir.

begin;

alter table public.kulupler add column kademe text;
alter table public.kulupler add constraint kulupler_kademe_check
    check (kademe is null or kademe in ('buyuk', 'bas_alti', 'diger'));

-- Büyük: Galatasaray, Fenerbahçe, Beşiktaş, Manchester City, Manchester United, Liverpool, Arsenal, Chelsea, Tottenham,
-- Real Madrid, Barcelona, Atlético Madrid, Juventus, Inter, Milan, Bayern Münih, Borussia Dortmund, PSG
update public.kulupler set kademe = 'buyuk'
where transfermarkt_id in ('141', '36', '114', '281', '985', '31', '11', '631', '148',
                           '418', '131', '13', '506', '46', '5', '27', '16', '583');

-- Baş altı: Trabzonspor, Başakşehir, Newcastle, Aston Villa, West Ham, Sevilla, Athletic Bilbao, Real Betis, Valencia,
-- Napoli, Roma, Lazio, Atalanta, Fiorentina, Leverkusen, RB Leipzig, Eintracht Frankfurt, Stuttgart,
-- Marsilya, Monaco, Lyon, Lille
update public.kulupler set kademe = 'bas_alti'
where transfermarkt_id in ('449', '6890', '762', '405', '379', '368', '621', '150', '1049',
                           '6195', '12', '398', '800', '430', '15', '23826', '24', '79',
                           '244', '162', '1041', '1082');

-- Diğer: Villarreal, Real Sociedad
update public.kulupler set kademe = 'diger'
where transfermarkt_id in ('1050', '681');

-- Kontrol: sayılar listeyle aynı değilse hiçbir şey yazılmaz
do $$
declare
    v_buyuk integer;
    v_bas_alti integer;
    v_diger integer;
begin
    select count(*) filter (where kademe = 'buyuk'),
           count(*) filter (where kademe = 'bas_alti'),
           count(*) filter (where kademe = 'diger')
    into v_buyuk, v_bas_alti, v_diger
    from public.kulupler;

    if v_buyuk <> 18 or v_bas_alti <> 22 or v_diger <> 2 then
        raise exception 'Kulüp sayıları beklenenden farklı: % büyük, % baş altı, % diğer (beklenen 18, 22, 2)',
            v_buyuk, v_bas_alti, v_diger;
    end if;
end;
$$;

commit;
