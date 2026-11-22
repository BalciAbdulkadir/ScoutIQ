# Güncellemelerde Dikkat Edilecekler

Bu liste, şimdiye kadar yaşanan sorunlardan ve verilen kararlardan çıkarıldı. Kuralların kendisi `CLAUDE.md`'de. Burada güncelleme yaparken kolayca atlanabilecek noktalar var.

---

## 1. `oyuncular` ya da `kulupler` tablosuna yeni kolon eklerken

040'tan beri bu iki tabloda uygulama sadece gereken kolonları okuyabilir: `oyuncular`'da `id`, `isim`, `uyruk`, `foto_url`; `kulupler`'de `id`, `isim`, `logo_url`. Piyasa değeri, bilinirlik, kademe gibi soru üretimine ait kolonlar kapalı.

- Yeni eklenen kolon **kimseye açık değildir.** Uygulama okumayacaksa hiçbir şey yazılmaz.
- Uygulama yeni kolonu okuyacaksa (doğrudan ya da kullanıcının yetkisiyle çalışan bir fonksiyon içinden), kolonu ekleyen SQL dosyasına izin satırı yazılır ve nedeni dosyanın yorumuna eklenir:
  ```sql
  grant select (yeni_kolon) on public.oyuncular to authenticated;
  ```
- Kolon cevabı ele veriyorsa (bedel, kademe, kulüp sayısı gibi) bu izin **verilmez.** Kolonu sadece sunucu fonksiyonları okur.
- `oyuncu_ara` 040'tan beri `security definer`'dır, kolon izinlerinden etkilenmez.
- Kontrol:
  ```sql
  select has_column_privilege('authenticated', 'public.oyuncular', 'yeni_kolon', 'select');
  ```

## 2. SQL dosyaları

Kurallar `CLAUDE.md` madde 23–28'de. Kısaca:

- Yeni dosyanın numarası, `main`'deki son numaranın bir fazlasıdır. Numara mesajla sorulmaz. İki kişi aynı anda SQL yazıyorsa numaraların çakışmadığına PR'da bakılır.
- Dosyanın ilk satırındaki numara dosya adıyla aynıdır (`037_...sql` → `-- 037: ...`). Başka bir dosyaya atıf yapılıyorsa dosya adı tam yazılır ve gerçekten var olduğuna bakılır.
- Supabase'de çalıştırılmış dosya değiştirilmez. Düzeltme yeni bir dosyayla yapılır.
- SQL dosyası PR'ın içindedir. PR açıklamasında hangi dosyaların hangi sırayla çalıştırılacağı yazılır.
- SQL, PR `main`'e birleştikten **sonra** çalıştırılır.
- Dosya `begin; ... commit;` arasında yazılır. Hata olursa hiçbir değişiklik uygulanmaz.
- Mümkünse dosya tekrar çalıştırılabilir yazılır (`create or replace`, `if not exists`, `drop ... if exists`).
- Supabase ile repo arasında fark olup olmadığı `kurallar/supabase_repo_karsilastirma.sql` ile görülebilir. Sorgu sadece okur. Yeni bir dosya eklenince sorguya o dosyanın satırı da eklenir.

## 3. Eski uygulama sürümünü bozan SQL

Bazı SQL dosyaları, telefonlardaki eski sürümün yaptığı bir şeyi yasaklar. Örnek: 034'ten sonra eski sürüm skoru yazamaz.

- Böyle bir dosyada sıra dosyanın başına yazılır: önce yeni uygulama sürümü Play'de yayınlanır, sonra SQL çalıştırılır.
- Sıra (041'den beri, zorunlu güncelleme):
  1. Yeni sürüm Play'de yayınlanır.
  2. `public.uygulama_surumu.en_dusuk_surum_kodu` yeni sürümün sürüm koduna (`pubspec.yaml`'da `+`'dan sonraki sayı) çekilir. Bu da yeni bir SQL dosyasıyla yapılır, SQL Editor'dan elle değiştirilmez:
     ```sql
     update public.uygulama_surumu set en_dusuk_surum_kodu = 2 where id = 1;
     ```
     Eski sürümü açan kullanıcı kapatılamayan "Güncelleme gerekli" sayfasını görür. İnterneti olmayan telefon engellenmez.
  3. Eski sürümü bozan SQL çalıştırılır.
  Sınırı yükselten dosya ile bozan dosya aynı dosya olabilir; o zaman sınırı yükselten satır dosyanın başındadır.
- Fonksiyonun adı, parametreleri ya da dönüş alanları değişirse eski sürüm hata alır. Mümkünse yeni bir fonksiyon eklenir, eski fonksiyon bir süre yerinde bırakılır.

## 4. Yeni oyun ya da yeni oyun fonksiyonu yazarken

**Cevap telefona gitmez:**
- `gunluk_oyunlar.soru_verisi` oyunu açan kullanıcıya `oyun_ac`'tan gelir. Cevap ya da cevabı ele veren bilgi (sağdaki oyuncunun bedeli, Kesişim'in hedef oyuncusu, sorunun kademesi) soru verisine yazılmaz.
- Böyle bilgiler RLS'i açık ama politikası olmayan ayrı bir tabloda tutulur (`bonservis_cevaplari`, `kesisim_hedefleri`, `top10_cevaplari` gibi).
- Soru verisinde bir **id** varsa, o id ile okunabilen tablolarda cevabı ele veren bir kolon olup olmadığına bakılır. Bonservis'te açık buradan doğdu: oyuncunun id'si soruda vardı, `oyuncular.toplam_bonservis` de herkese açıktı.

**Cevap ve skor sunucuda kontrol edilir:**
- Cevap ve skor `security definer` fonksiyonlarla yazılır. İstemci `kullanici_oyun_gecmisi`'ne yazamaz, kayıt da açamaz (`CLAUDE.md` madde 16).
- Oyun sadece `oyun_ac` ile açılır (040): soru, kayıt ve süre aynı anda oluşur. `gunluk_oyunlar.soru_verisi`'ni uygulama doğrudan okuyamaz. Yeni oyun tipi `oyun_ac`'taki tip ve süre listelerine eklenir.
- Açık oyunda henüz sırası gelmemiş soru gönderilmez. Kesişim ve Bonservis'te sıradaki soru cevap fonksiyonunun dönüşündedir, Bingo'da sıradaki oyuncu `bingo_hamle`'nin dönüşündedir. Sorular tek tek gelen yeni bir oyun yazılırsa aynı düzen kullanılır.
- Cevabı kontrol eden ya da cevap döndüren her fonksiyon:
  - `auth.uid()` boşsa hata verir.
  - Kullanıcının o oyun için açık (`basladi`) kaydı yoksa cevap vermez.
  - Süreli oyunda süre dolduysa (3 saniye toleransla) cevabı kabul etmez, oyunu o anki skorla bitirir.
  - Soru sırasını kontrol eder: aynı soru iki kez cevaplanamaz, soru atlanamaz.
- Örnek ya da bütün cevapları döndüren fonksiyonlar (`..._ornek_cevaplar`, `top10_cevaplar`) sadece oyun `tamamlandi` olduktan sonra cevap verir.
- Sadece başka fonksiyonların içinden çağrılan yardımcı fonksiyonların izni herkesten alınır:
  ```sql
  revoke execute on function public.yardimci(...) from public, anon, authenticated;
  ```
  `kesisim_cevap_kontrol` bunu unuttuğumuz için açık kaldı (036'da kapatıldı).
- Uygulamanın çağırdığı fonksiyonlar:
  ```sql
  revoke execute on function public.fonksiyon(...) from public, anon;
  grant execute on function public.fonksiyon(...) to authenticated;
  ```
- Her fonksiyonda `set search_path = ''` bulunur. Tablolar `public.` önekiyle yazılır.
- `oyun_id` alan her fonksiyon oyunun tarihinin bugünden sonra olmadığını kontrol eder (`tarih <= public.bugunun_tarihi()`). Yarının oyunları akşamdan veritabanında durur (bkz. 6. bölüm), 00.00'dan önce hiçbir fonksiyondan oynanamamalı ve cevabı dönmemeli (037).

**Fonksiyon değiştirirken:**
- `create or replace function` var olan izinleri korur.
- Fonksiyon silinip yeniden oluşturulursa (dönüş tipi değişince bu zorunludur, 012'deki gibi) izinler sıfırlanır. `revoke` ve `grant` satırları tekrar yazılır.
- Fonksiyonun eski hâli başka bir dosyadan kopyalanıyorsa en son dosyadaki hâli alınır. Örnek: `oyuncu_ara`'nın son hâli 030'da, `top10_tahmin`'in son hâli 031'de.

**Yeni oyun tipi eklerken:**
- `gunluk_oyunlar_oyun_tipi_check` ve `kullanici_oyun_gecmisi_oyun_tipi_check` kısıtlarının ikisi de güncellenir. Listeye eski tiplerin hepsi tekrar yazılır (son liste 029'da).
- Günde tek mod kuralı (`oyun_gunde_bir`), tipin alt çizgiden önceki kısmına bakar (`kesisim_kolay` → `kesisim`). Yeni tipin adı bu düzene uygun seçilir.
- Tarihler Türkiye saatiyledir: `public.bugunun_tarihi()` ya da `(now() at time zone 'Europe/Istanbul')::date`.

## 5. Soru verisinin biçimi değişirken

- Eski günlerin oyunları veritabanında eski biçimle durur. Örnekler:
  - Eski Bonservis sorularında sağdaki oyuncunun bedeli soru verisinde var.
  - Eski Kesişim sorularında `kademe` ve `zorluk` alanları var.
- Uygulama ve SQL fonksiyonları her iki biçimi de okuyabilmelidir. Bir alan kaldırılınca uygulamanın o alana bağlı olmadığı kontrol edilir.

## 6. Backend (Cloud Run işi)

Kurulum ve dağıtım: `backend/CLOUD_RUN.md`.

- Backend yarının oyunlarını bugün üretir (18.00, eksikler 20.00). Üretimle ilgili tarih hesaplarında "bugün" (`DateTime.Now`, `DateTime.UtcNow`) değil, işe verilen **hedef tarih** kullanılır. Tekrar kuralları (Kesişim'in 21 günü, Top 10'un 180 günü ve eksen sırası) hedef tarihe göre sayılır.
- "Bugün" ve "yarın" her zaman `Europe/Istanbul`'a göre hesaplanır, makinenin saatine göre değil. Cloud Run makineleri UTC'dedir.
- Yeni bir oyun tipi eklenirse `UretimCalismasi.BeklenenOyunTipleri`'ne de eklenir. Eklenmezse eksik kalması fark edilmez.
- Backend değişikliği `main`'e birleşince imaj yeniden derlenip yüklenir (`CLOUD_RUN.md` 9. adım). Yüklenmezse iş eski kodla çalışmaya devam eder.
- Supabase secret anahtarı sadece Secret Manager'da (Cloud Run) ve user-secrets'ta (yerel) durur. `appsettings.json`'a yazılmaz.

## 7. Android ve Google Play

- **Paket adı:** `com.footylore.app`. İlk yüklemeden sonra değiştirilemez.
- **İmza dosyaları:** `mobile/android/key.properties` ve `.jks` repoya girmez. Kaybedilirlerse uygulama güncellenemez, yedekleri güvenli bir yerde tutulur.
  - `key.properties` yoksa (ya da içindeki `storeFile` bulunamazsa) release paketi (`bundleRelease`, `assembleRelease`) derlenmez: derleme hangi dosyanın eksik olduğunu ve nereye konacağını yazıp durur. Debug derleme ve testler dosyasız çalışır.
  - `storeFile` yolu tırnaksız ve `/` ile yazılır (`storeFile=D:/keystore/footylore-release.jks`). Java'nın dosya okuması Türkçe karakterleri bozduğu için `.jks` Türkçe karakterli bir klasörde durmaz.
- **Firebase:** `mobile/android/app/google-services.json` repoda yok. Dosya yoksa debug derleme sadece uyarı verir ve uygulama Firebase'siz çalışır: Crashlytics ve Analytics veri toplamaz. Release paketi dosya yoksa derlenmez.
- **Sürüm numarası:** Her Play yüklemesinde `mobile/pubspec.yaml`'daki sürümün `+` işaretinden sonraki sayısı (`1.0.0+1` → `1.0.0+2`) bir artırılır. Aynı sayıyla ikinci yükleme kabul edilmez.
- **Analitik:** Kişisel veri ve oyuncu ismi gönderilmez. Yeni olay eklemeden önce `CLAUDE.md` madde 18'e bakılır.
- **Gizlilik politikası ve hesap silme sayfası:** Repo kökündeki `web_sitesi/` klasöründedir (`https://footylore.web.app`, Firebase Hosting, `footylore` sitesi). Uygulama yeni bir veri toplamaya başlarsa (yeni tablo, yeni analitik olayı, yeni hizmet sağlayıcı) ya da hesap silme adımları değişirse `web_sitesi/gizlilik.html` ve `web_sitesi/hesap-silme.html` aynı PR'da güncellenir, sayfalardaki "Son güncelleme" tarihi değişir. Sitede JavaScript, çerez ve dış kaynak olmaz (`mobile/test/web_sitesi_test.dart`).
- **Reklam kimliği:** Uygulamada reklam yok. `AD_ID` ve `ACCESS_ADSERVICES_*` izinleri `AndroidManifest.xml`'de `tools:node="remove"` ile çıkarılır, Analytics reklam kimliği toplamaz (`google_analytics_adid_collection_enabled = false`). Play Console'daki reklam kimliği beyanı "kullanılmıyor"dur. Yeni bir eklenti bu izinleri tekrar eklerse birleştirilmiş manifest'e bakılır (`gradlew :app:processDebugMainManifest`).

## 8. Git

- Her özellik ayrı bir branch'te yapılır, `main`'e doğrudan push yapılmaz.
- `kurallar/` klasörü repoya girmez (`.git/info/exclude`).
- `mobile/linux/flutter/generated_plugins.cmake` ve `mobile/windows/flutter/generated_plugins.cmake` dosyalarındaki değişiklikler Flutter'ın kendi ürettiği değişikliklerdir, commit'e katılmaz.
- Anahtar, şifre, `.env` gibi gizli bilgiler repoya girmez.
