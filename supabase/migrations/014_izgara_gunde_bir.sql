-- 014: Günde tek Izgara
-- Supabase SQL Editor'da tek seferde çalıştırılır. Hata olursa hiçbir değişiklik uygulanmaz.
-- 013_izgara_sure.sql'den sonra çalıştırılmalıdır.
--
-- Kural: Kolay, orta ve zor ayrı tahtalardır ama kullanıcı günde bunlardan yalnızca birini oynar.
-- Bir zorluğa başlayan kullanıcı o gün başka bir zorlukta Izgara kaydı açamaz. Uygulama bunu zaten
-- engelliyor; bu tetikleyici aynı kuralı veritabanında da uygular. Daha önce açılmış kayıtlara dokunmaz.

begin;

create or replace function public.izgara_gunde_bir()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if new.oyun_tipi like 'izgara\_%' then
        -- Aynı anda gelen iki kayıt isteği sırayla işlenir, ikisi birden geçemez
        perform pg_advisory_xact_lock(hashtext('izgara:' || new.kullanici_id::text || ':' || new.tarih::text));

        if exists (
            select 1
            from public.kullanici_oyun_gecmisi
            where kullanici_id = new.kullanici_id
              and tarih = new.tarih
              and oyun_tipi like 'izgara\_%'
              and oyun_tipi <> new.oyun_tipi
        ) then
            raise exception 'Bugün başka bir Izgara oynandı' using hint = 'izgara_gunde_bir';
        end if;
    end if;
    return new;
end;
$$;

revoke execute on function public.izgara_gunde_bir() from public, anon, authenticated;

drop trigger if exists izgara_gunde_bir on public.kullanici_oyun_gecmisi;
create trigger izgara_gunde_bir
    before insert on public.kullanici_oyun_gecmisi
    for each row execute function public.izgara_gunde_bir();

commit;
