-- 033: Uygulama içinden hesap silme (Google Play zorunluluğu)
-- Supabase SQL Editor'da tek seferde çalıştırılır. Hata olursa hiçbir değişiklik uygulanmaz.
-- 031_top10_can.sql'den sonra çalıştırılmalıdır.
--
-- hesabimi_sil(): giriş yapmış kullanıcının bütün verisini ve en son auth.users kaydını siler.
--   - Sadece kendi hesabını silebilir: kullanıcı parametre olarak alınmaz, auth.uid() kullanılır.
--   - Kullanıcı verisi "kullanici_id" kolonu olan bütün public tablolardadır (kullanici_oyun_gecmisi, izgara_tahminleri,
--     izgara_sureleri, bingo_hamleleri, top10_tahminleri). Tablolar elle sayılmaz: kolonu olan her tablo bulunup temizlenir,
--     ileride eklenecek kullanıcı tabloları da kendiliğinden silinir.
--   - Bu tabloların auth.users'a yabancı anahtarı yoktur; kullanıcıyı silmek satırlarını silmez, bu yüzden önce onlar silinir.
--   - auth.users silinince Supabase oturumları ve kimlik kayıtları (auth.sessions, auth.identities ...) da silinir.
--   - Dönüş: silinen kullanıcı verisi satır sayısı.

begin;

create or replace function public.hesabimi_sil()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_kullanici uuid := (select auth.uid());
    v_tablo record;
    v_sayi integer;
    v_toplam integer := 0;
begin
    if v_kullanici is null then
        raise exception 'Giriş yapılmamış';
    end if;

    for v_tablo in
        select c.table_name
        from information_schema.columns c
        join information_schema.tables t
          on t.table_schema = c.table_schema and t.table_name = c.table_name and t.table_type = 'BASE TABLE'
        where c.table_schema = 'public' and c.column_name = 'kullanici_id'
        order by c.table_name
    loop
        execute format('delete from public.%I where kullanici_id = $1', v_tablo.table_name) using v_kullanici;
        get diagnostics v_sayi = row_count;
        v_toplam := v_toplam + v_sayi;
    end loop;

    delete from auth.users where id = v_kullanici;

    return v_toplam;
end;
$$;

revoke execute on function public.hesabimi_sil() from public, anon;
grant execute on function public.hesabimi_sil() to authenticated;

commit;
