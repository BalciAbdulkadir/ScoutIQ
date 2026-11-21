# ScoutIQ – Proje Kuralları

Kaynak: *ScoutIQ Günlük Futbol Zekası MVP Raporu v2.0*. Bu belgede olmayan bir karar gerekirse önce sorulmalıdır.

## A. Çalışma Düzeni
1. Proje 2 kişi tarafından geliştirilmektedir.
2. Her yeni özellik için ayrı bir branch açılır ve o branch'e pushlanır. `main`'e doğrudan push yapılmaz.

## B. Oyun Mekaniği (Altın Kurallar)
3. **One-Shot (Günde Tek Atış):** Her mini oyun kullanıcı başına günde yalnızca bir kez oynanır. Cevap doğru ya da yanlış olsun, oyun o gün için kilitlenir. "Tekrar Oyna" butonu bulunmaz.
4. **Gece Yarısı Yenilenmesi (20 Kasım 2026 kararı):** Ertesi günün bütün oyunları her gün Türkiye saatiyle 18.00'de, Google Cloud Scheduler'ın başlattığı Cloud Run işiyle Supabase'e eklenir; 20.00'de aynı iş eksikleri tamamlar. Oyunlar kullanıcıya Türkiye saatiyle 00.00'da açılır. Eksik oyun kalırsa e-posta uyarısı gelir.
5. **Zorunlu Oturum:** Google Sign-In ile giriş zorunludur. Anonim oynamaya izin verilmez.

## C. Kapsam ve Fazlar
6. Uygulama, futbol11.com benzeri ızgara (grid) yapısında birden fazla oyunu barındıran merkezi bir **Oyun Hub'ı**dır.
7. İlk faz oyun modları. Her oyunun (Bingo ve Top 10 hariç) Kolay, Orta ve Zor modu ayrı günlük oyundur; kullanıcı her oyunda günde bunlardan yalnızca birini seçip oynar. Oyuncu önce zorluğu, ardından süreyi seçer (süre yok, 30, 60 ya da 90 saniye); süre bütün oyun içindir, sunucuda tutulur ve dolunca oyun o anki skorla biter. Oyundan çıkınca oyun bitmez: süre arkada işler, süre bitmediyse (ya da oyun süresizse) oyuncu kaldığı yerden devam eder. Zorluk, soruların oyuncu kademesinden gelir (kademeler: `unlu`, `bilinen`, `diger`; `data_miner/kademeler.py`):
   - **Kolay:** sorular sadece ünlü oyunculardan. **Orta:** %50 ünlü, %50 bilinen. **Zor:** %40 ünlü, %30 bilinen, %30 diğer.
   - Birden fazla doğru cevabı olan soru (Kesişim sorusu, Izgara hücresi) en bilinen cevabının kademesinden sayılır.
   - Tam bölünmeyen yüzdeler kolaya yuvarlanır: 5 soruda orta 3+2, zor 2+2+1; 9 hücrede orta 5+4, zor 4+3+2; 10 oyuncuda orta 5+5, zor 4+3+3.
   - **Mod 1 – Kesişim Bulmacası:** Gösterilen iki takımın ortak oyuncusunu bulma. 5 soru vardır; bir oyunda aynı kulüp iki kez çıkmaz. İki kulüpte de oynamış her oyuncu doğru cevaptır. Orta ve Zor modda kulüp çiftleri rastgele seçilir. Kolay mod oyuncudan başlanarak kurulur: önce ünlü bir hedef oyuncu seçilir, gösterilen iki kulüp onun kariyerindeki büyük kulüplerden rastgele seçilir (hedef olmak için en az iki büyük kulüpte en az 20'şer maça çıkmış olmak gerekir). Hedef oyuncu sadece çiftin en az bir ünlü cevabı olduğunu garanti eder, cevap kontrolü ona bakmaz. Hedef olmuş oyuncu, kullanılmamış uygun hedef kaldıkça tekrar hedef olmaz; kalmayınca en uzun süredir hedef olmamış oyuncudan başlanarak tekrar edilir. Aynı kulüp çifti (sırasız) 21 gün geçmeden tekrar sorulmaz (günler sorunun yayınlanacağı güne, yani hedef tarihe göre sayılır, işin çalıştığı güne göre değil); bu kuralla 5 soru kurulamazsa kural o gün için esnetilir, soru üretilmeyen gün olmaz.
   - **Mod 2 – Bonservis Kıyaslaması:** İki oyuncunun geçmiş transfer bedellerini Daha Az / Daha Fazla mantığıyla karşılaştırma. 5 soru (10 oyuncu) vardır; yanlış cevapta oyun bitmez, her doğru tahmin 2 puandır (en fazla 10).
   - **Mod 3 – Izgara (3x3):** Satır ve sütun başlıklarının ikisine de uyan oyuncuları bulma. Kolay sadece büyük kulüplerden, Orta büyük ve baş altı kulüpler + bilinen 20 milli takımdan, Zor büyük ve baş altı kulüpler + diğer milli takımlardan kurulur (kulüp kademeleri `kulupler.kademe`: `buyuk`, `bas_alti`, `diger`; `diger` ve kademesiz kulüpler başlık olmaz). Bir tahtada en fazla 2 milli takım olur. Hücrenin kademesi hesaplanırken oyuncu, kulüpte en az 20 maça çıkmışsa sayılır; cevap olarak bütün oyuncular kabul edilir. Tahmin hakkı sınırı yoktur; oyun dokuz kutu dolunca, pes edilince ya da süre dolunca biter. Kullanıcı hücre seçmez, doğru oyuncu uygun hücreye yerleşir. Aynı oyuncu iki kez kullanılamaz, pes edilebilir.
   - **Mod 4 – Bingo:** Diğer oyunlardan farklı olarak zorluk modu yoktur, günde tek kart vardır (oyun tipi `bingo`). Kart 4 satır, 3 sütundur; 12 kategori vardır: 4 kulüp (büyük kulüpler; en fazla 1 tanesi baş altı kulüp olabilir), 3 milli takım (bilinen 20 milli takımdan), 2 lig ve 3 başarı (ör. Şampiyonlar Ligi, Dünya Kupası, lig şampiyonluğu). Deste ünlü ağırlıklıdır ve 32 oyuncudur: kartı dolduran 12 ünlü oyuncu, en az bir kutuya uyan 16 oyuncu (11 ünlü, 5 bilinen) ve hiçbir kutuya uymayan 4 oyuncu (3 ünlü, 1 bilinen); toplam 26 ünlü, 6 bilinen. Desteye giren bilinen oyuncular bilinirlik sırasında ilk 800'dendir. Kulüp ve lig kategorilerinde oyuncu, kulüpte en az 20 maça çıkmışsa desteye girer; cevap olarak bütün oyuncular kabul edilir. Oyuncular karışık sırayla gelir. Kullanıcı gelen oyuncuyu uyduğu kutuya koyar ya da pas geçer. Pas sınırsızdır: destede sıra döner, pas geçilen oyuncu sırası gelince tekrar gelir; kutuya yerleşen oyuncu bir daha gelmez. Yanlış kutuya konan oyuncu gitmez, ceza da yoktur; başka kutu denenebilir. Oyuncu sadece doğru kutuya konunca ya da pas geçilince gider. Dolu kutuya oyuncu konamaz. Ekranda kalan oyuncu sayısı gösterilmez. Oyun 12 kutu dolunca, pes edilince ya da süre dolunca biter; kalan oyuncuların hiçbiri boş kutulara uymuyorsa da biter. Skor dolu kutu sayısıdır (en fazla 12). Süre seçenekleri süre yok, 60 ve 90 saniyedir (30 saniye yoktur). Kart desteden her zaman tamamen doldurulabilir.
   - **Mod 5 – Top 10:** Zorluk modu ve süre yoktur, günde tek soru vardır (oyun tipi `top10`). Ekranda bir başlık (ör. "Galatasaray'ın en pahalı 10 transferi") ve 1'den 10'a sıralı 10 satır vardır; her satırda ipucu olarak oyuncunun uyruğunun bayrağı açıktır. Kullanıcı oyuncuyu öneri listesinden seçer, sırayı bilmesi gerekmez: listedeki oyuncu kendi sırasına yerleşir. 3 can vardır (17 Kasım 2026 kararı): listede olmayan oyuncuyu tahmin etmek bir can götürür; daha önce denenmiş oyuncu tekrar sayılmaz, can da götürmez. Canlar oyun tablosuyla oyuncu yazma alanının arasında kırmızı kalplerle gösterilir. Her bulunan oyuncu 1 puandır (en fazla 10). Oyun 10 oyuncu bulununca, canlar bitince ya da onaylı pes edilince biter; bitince bulunamayan oyuncular gösterilir. Kapsam geneldir (Türkiye ile sınırlı değil). Şablonlar: transfer ekseninde kulübün en pahalı 10 transferi / satışı, ligin en pahalı 10 transferi, en pahalı 10 [ülke]li oyuncu, sezonun en pahalı 10 transferi, iki kulüp arasındaki en pahalı 10 transfer, en çok kulüp değiştiren 10 oyuncu; Ballon d'Or ekseninde bir yılın Ballon d'Or sıralamasında ilk 10 (1995'ten bugüne). Üretim kuralları: en az 10 farklı oyuncu (oyuncu bir kez, en yüksek kaydıyla), 10. ile 11. eşitse soru yok, en az 6 oyuncu ünlü ya da bilinen, transferlerde sadece bedelli transferler ve 2000'den sonrası (başlıkta yazar), kulüp şablonlarında sadece büyük ve baş altı kulüpler, aynı şablon + değişken 180 gün tekrar etmez, aynı eksenden art arda iki gün soru sorulmaz (diğer eksende soru yoksa uygulanmaz). Bu iki kural hedef tarihe göre sayılır: "önceki gün", sorunun yayınlanacağı günden bir önceki gündür. Liste soru üretilirken sabitlenir, cevaplar oyun bitmeden uygulamaya gönderilmez. Ayrıntılar: `kurallar/scoutiq-top10-kurallar.md` (repoda değildir).
8. Bingo 8 Kasım 2026'da (Mod 4), Top 10 15 Kasım 2026'da (Mod 5) ilk faza alındı. Başka yeni modlar ilk fazın parçası değildir.
9. Aşağıdakiler **Faz 2** kapsamındadır, ilk fazda yapılmaz:
   - **Zamanlayıcı:** Belirli oyunlarda geri sayım sayacı. (Kesişim, Bonservis ve Izgara'nın süre seçimi istisnadır, madde 7'ye bakınız.)
   - **Zorluk Seviyeleri:** "Kolay" (ör. son 5 yıldaki oyuncular) / "Zor" (ör. tüm zamanlar). (Oyunların kademeye dayalı Kolay / Orta / Zor modları istisnadır, madde 7'ye bakınız.)
   - **Can Hakkı Sistemi:** Bazı oyunlarda 3 veya 5 yanlış cevap hakkı (kalp/can). (Top 10'un 3 canı istisnadır, madde 7'ye bakınız.)

## D. Teknik Mimari
10. **Frontend (Mobil) – `mobile/`:** Flutter + Riverpod. Siyah/yeşil karanlık tema ve grid liste yapısı.
11. **Backend (Soru Üretim İşi) – `backend/`:** C# (.NET), Google Cloud Run Jobs üzerinde çalışıp kapanan soru üretim işi. Zamanlama Cloud Scheduler'dadır (Coravel kullanılmaz). Supabase secret anahtarı Secret Manager'dadır. Kurulum: `backend/CLOUD_RUN.md`.
12. **Veri Kaynağı – `data_miner/`:** Python script'i + Dockerize edilmiş Transfermarkt API. 2025/2026 sezonu baz alınarak güncellenmiş oyuncu ve kariyer verileri.
13. **Veritabanı:** Supabase. Şema ve fonksiyonlar `supabase/migrations/` altında numaralı SQL dosyaları olarak repoda tutulur (bkz. G).

## E. Veritabanı Şeması (Supabase)
| Tablo | Açıklama |
|---|---|
| `kulupler` | Sabit veri tablosu. |
| `oyuncular` | Sabit veri tablosu. |
| `kariyer_gecmisi` | Oyuncuların kariyer ve transfer geçmişi için sabit veri tablosu. |
| `gunluk_oyunlar` | Eski `gunun_sorusu` tablosunun genişletilmiş hâli; hangi oyun moduna ait olduğu bilgisini içerir. |
| `kullanici_oyun_gecmisi` (YENİ) | Kullanıcı_ID, Oyun_Modu_ID, Tarih, Skor ve Sonuc alanlarını tutar. Kullanıcının ilgili oyunu oynayıp oynamadığını ve can haklarını takip etmek için gereklidir. |
| `profiller` | Kullanıcının liderlik tablosundaki takma adı; `gizli` bayrağı (hile, uygunsuz ad) kullanıcıyı tablodan gizler. |
| `yasakli_kelimeler` | Takma adlarda kullanılamayan kelimeler. |

## F. Google Play Yayını (19 Kasım 2026 kararları)
14. **Platform:** Sadece Android. Paket adı `com.footylore.app` (ilk yüklemeden sonra değiştirilemez). Release imzası `mobile/android/key.properties` ve `.jks` dosyasından okunur; ikisi de repoya girmez.
15. **Puan ve liderlik tablosu (20-21 Kasım 2026 kararı):** Skor (doğru/kutu/oyuncu sayısı) aynen kalır; puan ayrı bir alandır (`kullanici_oyun_gecmisi.puan`) ve sunucuda, oyun bitince tetikleyiciyle yazılır. Puanı sadece oyunu bitiren alır, kısmi puan yoktur: Kesişim ve Bonservis 5/5 doğru, Izgara 9/9, Bingo 12/12, Top 10 10/10. Pes edilen, süresi dolan, canı biten ya da eksik kalan oyun puansızdır. Puan = yuvarla(100 × zorluk çarpanı × süre çarpanı) + hız bonusu. Zorluk: kolay 1, orta 1.5, zor 2, Bingo ve Top 10 1.5. Süre: 90 sn 1, 60 sn 1.25, 30 sn 1.5. Hız bonusu: ana puan × 0.2 × kalan/toplam süre. Süresiz oyunlar puansızdır; Top 10 süresizdir ama canı olduğu için 10/10 bitirene her zaman 150 puan verilir. Süre ilk hamleden önce seçilmelidir. Liderlik tablosu: Bugün / Bu Hafta / Tüm Zamanlar, oyun filtresiyle; takma adla gösterilir, Google adı ve fotoğrafı gösterilmez. Seri ("🔥 6 gün": art arda en az bir oyunun bitirildiği gün sayısı, Türkiye saatiyle; bugün oynanmadıysa dünden geriye sayılır) puana eklenmez, sadece ana menüde gösterilir.
16. **Skor sunucuda hesaplanır.** Bütün oyunlarda cevap ve skor sunucudaki fonksiyonlarla yazılır; istemci `kullanici_oyun_gecmisi`'ni güncelleyemez, sadece boş kayıt açar. Bonservis'te tahmin edilen bedel soruyla gönderilmez. Puan da sunucuda yazılır; istemci puan alanlarını dolduramaz.
17. **Hesap silme:** Uygulama içinden (profil fotoğrafı → Hesap → Hesabımı sil, iki adımlı onay). Kullanıcının bütün satırları ve `auth.users` kaydı silinir.
18. **Analitik ve çökme takibi:** Firebase Crashlytics ve Analytics. Kişisel veri ve oyuncu ismi gönderilmez; olaylar: `oyun_basladi`, `oyun_bitti` (bitiş sebebi: tamamlandi/pes/sure_doldu/can_bitti), `oyun_yarida_birakildi`, `sonuc_paylasildi`, `bildirim_acildi`, `liderlik_acildi` (dönem: gun/hafta/tum). `oyun_bitti` olayına `puan` (sayı, puansız oyunda gönderilmez) parametresi eklenir. Debug derlemede gönderilmez.
19. **Sonuç paylaşımı:** Her bitiş ekranında "Sonucu paylaş"; metin cevap ele vermez (renkli kareler, skor, seri ve Play linki).
20. **Akşam hatırlatması:** Yerel bildirim, sunucu yok. O gün hiç oyun bitirilmediyse 20.00'de (Europe/Istanbul). Bildirim izni ilk oyun bitince istenir; Hesap sayfasından kapatılabilir.
21. **Puanla isteği:** Play'in kendi penceresi; 3 farklı gün oyun bitirildikten sonra, iyi sonuçlu (en yüksek skorun en az %70'i) bir oyunun bitişinde bir kez.
22. **Oyun kuralları:** Her oyunda ilk dokunuşta örnekli kurallar; oyun ekranındaki "?" düğmesi kuralları tekrar açar.

## G. SQL Dosyaları (20 Kasım 2026 kararları)
23. Supabase'de yapılan her değişiklik `supabase/migrations/` altında numaralı bir dosya olarak repoya girer. SQL Editor'da dosyası olmayan değişiklik yapılmaz.
24. Yeni dosyanın numarası `main`'deki son numaranın bir fazlasıdır. Numara mesajla sorulmaz, repodan bakılır.
25. Dosyanın ilk satırı dosya adıyla aynı numarayı taşır (`036_...sql` → `-- 036: ...`).
26. Bir kez Supabase'de çalıştırılmış dosya değiştirilmez. Düzeltme gerekirse yeni bir dosya yazılır.
27. PR açıklamasında hangi SQL dosyalarının hangi sırayla çalıştırılacağı yazılır. Dosya PR'ın içindedir, mesajla gönderilmez.
28. SQL dosyası, PR `main`'e birleştikten sonra Supabase'de çalıştırılır. Uygulamanın eski sürümünü bozan dosyalarda (034 gibi) sıra dosyanın başında yazar.
