-- 027: Kolay Kesişim'in hedef oyuncuları
-- Supabase SQL Editor'da tek seferde çalıştırılır. Hata olursa hiçbir değişiklik uygulanmaz.
-- 024_kulup_kademeleri.sql'den sonra çalıştırılmalıdır (kolay Kesişim büyük kulüpleri kulupler.kademe'den okur).
--
-- Kolay Kesişim soruları oyuncudan başlanarak kurulur: önce ünlü bir "hedef oyuncu" seçilir, gösterilen iki büyük kulüp
-- onun kariyerinden çıkar (backend: Oyunlar/KolayKesisimSecici.cs). Bu tablo hangi sorunun hangi hedef oyuncudan ve
-- hangi kulüp çiftinden kurulduğunu tutar; iki tekrar kuralı buradan kontrol edilir:
--   - Hedef olmuş oyuncu, kullanılmamış uygun hedef kaldıkça tekrar hedef olmaz.
--   - Aynı kulüp çifti 21 gün geçmeden tekrar sorulmaz. Çift sırasızdır: kulup_a_id her zaman küçük olandır.
-- Cevap kontrolü değişmedi: iki kulüpte de oynamış her oyuncu doğru cevaptır, hedef oyuncuya bakılmaz.
-- Hedef oyuncu cevabı ele verdiği için soru verisinde (gunluk_oyunlar.soru_verisi) yer almaz, bu tablo da uygulamaya kapalıdır.

begin;

create table public.kesisim_hedefleri (
    id bigint generated always as identity primary key,
    oyun_id uuid not null references public.gunluk_oyunlar (id) on delete cascade,
    sira smallint not null,                    -- Sorunun oyundaki sırası, 1'den başlar
    tarih date not null,                       -- Oyunun tarihi
    oyuncu_id uuid not null references public.oyuncular (id) on delete cascade,
    kulup_a_id uuid not null references public.kulupler (id),
    kulup_b_id uuid not null references public.kulupler (id),
    unique (oyun_id, sira),
    check (kulup_a_id < kulup_b_id)
);

create index kesisim_hedefleri_oyuncu_idx on public.kesisim_hedefleri (oyuncu_id);
create index kesisim_hedefleri_cift_idx on public.kesisim_hedefleri (kulup_a_id, kulup_b_id, tarih);

-- Uygulamaya kapalı (politika yok): sadece backend kullanır
alter table public.kesisim_hedefleri enable row level security;

commit;
