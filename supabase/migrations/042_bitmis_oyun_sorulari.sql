-- 042: Bitmiş oyunun soruları oyun id'siyle, hiçbir şey açmadan okunur (gece yarısı hatası)
-- Supabase SQL Editor'da tek seferde çalıştırılır. Hata olursa hiçbir değişiklik uygulanmaz.
-- 041_yayin_oncesi.sql'den sonra çalıştırılmalıdır. Tekrar çalıştırılabilir.
-- Eski uygulama sürümünü bozmaz: sadece yeni bir fonksiyon ekler, oyun_ac'a dokunmaz.
--
-- Sorun:
--   Kesişim ve Bonservis'te süre dolunca cevaplanmamış sorular telefona hiç gelmemiştir (040: açık oyunda sorular
--   tek tek gelir). Uygulama bitiş özetini tamamlamak için oyun_ac(oyun_tipi)'yi tekrar çağırıyordu. oyun_ac oyunu
--   id'siyle değil "bugünün oyunu" diye kendisi bulur ve kayıt yoksa açar. Oyun 00.00'dan önce başlayıp süre
--   00.00'dan sonra dolunca:
--     - Yeni günün aynı zorluktaki oyununa süresiz bir kayıt açılıyordu. Kullanıcı yeni günde o oyunda o zorluğa
--       kilitleniyor (günde tek mod, 019) ve oyun süresiz başladığı için puansız kalıyordu.
--     - Dönen yeni gün oyunu açık olduğu için özet dünün sorularını da alamıyordu.
--
-- Düzeltme: bitmis_oyun_sorulari(p_oyun_id)
--   - Hiçbir kayıt açmaz, süre başlatmaz, hiçbir şey yazmaz.
--   - Soru verisinin tamamını sadece kullanıcının o oyundaki kaydı 'tamamlandi' ise döndürür. Oyun bitmediyse,
--     kullanıcı o oyunu hiç açmadıysa ya da oyun yoksa null döner: açık oyunda sırası gelmemiş soru yine gönderilmez.
--   - Oyunun tarihi bugünden sonra olamaz (037 kuralı, tarih <= bugunun_tarihi()).
--   - Bitmiş oyunda oyun_ac da soru verisinin tamamını döndürür (040); bu fonksiyon cevap ele veren yeni bir şey
--     açmaz. Eski Bonservis sorularındaki sağdaki bedel de, oyun_ac'taki gibi, oyun bitince görünür.
--   Uygulama (mobile/lib/services/gunluk_oyun.dart, bitmisOyununSorulari) bitiş özeti için artık bunu çağırır,
--   oyun_ac'ı çağırmaz.
--
-- Kontrol (çalıştırdıktan sonra):
--   select has_function_privilege('authenticated', 'public.bitmis_oyun_sorulari(uuid)', 'execute');  -> true
--   select has_function_privilege('anon', 'public.bitmis_oyun_sorulari(uuid)', 'execute');           -> false
--   select provolatile from pg_proc where proname = 'bitmis_oyun_sorulari';                          -> s (stable)

begin;

create or replace function public.bitmis_oyun_sorulari(p_oyun_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_kullanici uuid := (select auth.uid());
    v_soru jsonb;
begin
    if v_kullanici is null then
        raise exception 'Giriş yapılmamış';
    end if;

    select g.soru_verisi into v_soru
    from public.gunluk_oyunlar g
    join public.kullanici_oyun_gecmisi k
      on k.oyun_id = g.id and k.kullanici_id = v_kullanici and k.durum = 'tamamlandi'
    where g.id = p_oyun_id and g.tarih <= public.bugunun_tarihi()
    limit 1;

    return v_soru;
end;
$$;

revoke execute on function public.bitmis_oyun_sorulari(uuid) from public, anon;
grant execute on function public.bitmis_oyun_sorulari(uuid) to authenticated;

commit;
