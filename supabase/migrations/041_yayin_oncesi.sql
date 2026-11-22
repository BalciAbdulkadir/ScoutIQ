-- 041: Yayın öncesi: zorunlu güncelleme
-- Supabase SQL Editor'da tek seferde çalıştırılır. Hata olursa hiçbir değişiklik uygulanmaz.
-- 040_oyun_ac.sql'den sonra çalıştırılmalıdır. Tekrar çalıştırılabilir.
-- Eski uygulama sürümünü bozmaz: sadece yeni tablo ekler.
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
-- Kontrol (çalıştırdıktan sonra):
--   select * from public.uygulama_surumu;                                            -> 1 satır, en_dusuk_surum_kodu = 1
--   select has_table_privilege('anon', 'public.uygulama_surumu', 'select');           -> true
--   select has_table_privilege('authenticated', 'public.uygulama_surumu', 'update');  -> false

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

commit;
