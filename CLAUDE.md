# ScoutIQ – Proje Kuralları

Kaynak: *ScoutIQ Günlük Futbol Zekası MVP Raporu v2.0*. Bu belgede olmayan bir karar gerekirse önce sorulmalıdır.

## A. Çalışma Düzeni
1. Proje 2 kişi tarafından geliştirilmektedir.
2. Her yeni özellik için ayrı bir branch açılır ve o branch'e pushlanır. `main`'e doğrudan push yapılmaz.

## B. Oyun Mekaniği (Altın Kurallar)
3. **One-Shot (Günde Tek Atış):** Her mini oyun kullanıcı başına günde yalnızca bir kez oynanır. Cevap doğru ya da yanlış olsun, oyun o gün için kilitlenir. "Tekrar Oyna" butonu bulunmaz.
4. **Gece Yarısı Yenilenmesi:** Tüm oyunların yeni bulmacaları her gece Türkiye saatiyle 00.00'da C# (Coravel) cron job'u tarafından otomatik olarak Supabase veritabanına eklenir.
5. **Zorunlu Oturum:** Google Sign-In ile giriş zorunludur. Anonim oynamaya izin verilmez.

## C. Kapsam ve Fazlar
6. Uygulama, futbol11.com benzeri ızgara (grid) yapısında birden fazla oyunu barındıran merkezi bir **Oyun Hub'ı**dır.
7. İlk faz oyun modları. Her oyunun Kolay, Orta ve Zor modu ayrı günlük oyundur; kullanıcı her oyunda günde bunlardan yalnızca birini seçip oynar. Oyuncu önce zorluğu, ardından süreyi seçer (süre yok, 30, 60 ya da 90 saniye); süre bütün oyun içindir, sunucuda tutulur ve dolunca oyun o anki skorla biter. Oyundan çıkınca oyun bitmez: süre arkada işler, süre bitmediyse (ya da oyun süresizse) oyuncu kaldığı yerden devam eder. Zorluk, soruların oyuncu kademesinden gelir (kademeler: `unlu`, `bilinen`, `diger`; `data_miner/kademeler.py`):
   - **Kolay:** sorular sadece ünlü oyunculardan. **Orta:** %50 ünlü, %50 bilinen. **Zor:** %40 ünlü, %30 bilinen, %30 diğer.
   - Birden fazla doğru cevabı olan soru (Kesişim sorusu, Izgara hücresi) en bilinen cevabının kademesinden sayılır.
   - Tam bölünmeyen yüzdeler kolaya yuvarlanır: 5 soruda orta 3+2, zor 2+2+1; 9 hücrede orta 5+4, zor 4+3+2; 10 oyuncuda orta 5+5, zor 4+3+3.
   - **Mod 1 – Kesişim Bulmacası:** Gösterilen iki takımın ortak oyuncusunu bulma. 5 soru vardır; bir oyunda aynı kulüp iki kez çıkmaz. İki kulüpte de oynamış her oyuncu doğru cevaptır. Orta ve Zor modda kulüp çiftleri rastgele seçilir. Kolay mod oyuncudan başlanarak kurulur: önce ünlü bir hedef oyuncu seçilir, gösterilen iki kulüp onun kariyerindeki büyük kulüplerden rastgele seçilir (hedef olmak için en az iki büyük kulüpte en az 20'şer maça çıkmış olmak gerekir). Hedef oyuncu sadece çiftin en az bir ünlü cevabı olduğunu garanti eder, cevap kontrolü ona bakmaz. Hedef olmuş oyuncu, kullanılmamış uygun hedef kaldıkça tekrar hedef olmaz; kalmayınca en uzun süredir hedef olmamış oyuncudan başlanarak tekrar edilir. Aynı kulüp çifti (sırasız) 21 gün geçmeden tekrar sorulmaz; bu kuralla 5 soru kurulamazsa kural o gün için esnetilir, soru üretilmeyen gün olmaz.
   - **Mod 2 – Bonservis Kıyaslaması:** İki oyuncunun geçmiş transfer bedellerini Daha Az / Daha Fazla mantığıyla karşılaştırma. 5 soru (10 oyuncu) vardır; yanlış cevapta oyun bitmez, her doğru tahmin 2 puandır (en fazla 10).
   - **Mod 3 – Izgara (3x3):** Satır ve sütun başlıklarının ikisine de uyan oyuncuları bulma. Kolay sadece büyük kulüplerden, Orta büyük ve baş altı kulüpler + bilinen 20 milli takımdan, Zor büyük ve baş altı kulüpler + diğer milli takımlardan kurulur (kulüp kademeleri `kulupler.kademe`: `buyuk`, `bas_alti`, `diger`; `diger` ve kademesiz kulüpler başlık olmaz). Bir tahtada en fazla 2 milli takım olur. Hücrenin kademesi hesaplanırken oyuncu, kulüpte en az 20 maça çıkmışsa sayılır; cevap olarak bütün oyuncular kabul edilir. Tahmin hakkı sınırı yoktur; oyun dokuz kutu dolunca, pes edilince ya da süre dolunca biter. Kullanıcı hücre seçmez, doğru oyuncu uygun hücreye yerleşir. Aynı oyuncu iki kez kullanılamaz, pes edilebilir.
   - **Mod 4 – Bingo:** Diğer oyunlardan farklı olarak zorluk modu yoktur, günde tek kart vardır (oyun tipi `bingo`). Kart 4 satır, 3 sütundur; 12 kategori vardır: 4 kulüp (büyük kulüpler; en fazla 1 tanesi baş altı kulüp olabilir), 3 milli takım (bilinen 20 milli takımdan), 2 lig ve 3 başarı (ör. Şampiyonlar Ligi, Dünya Kupası, lig şampiyonluğu). Deste ünlü ağırlıklıdır ve 32 oyuncudur: kartı dolduran 12 ünlü oyuncu, en az bir kutuya uyan 16 oyuncu (11 ünlü, 5 bilinen) ve hiçbir kutuya uymayan 4 oyuncu (3 ünlü, 1 bilinen); toplam 26 ünlü, 6 bilinen. Desteye giren bilinen oyuncular bilinirlik sırasında ilk 800'dendir. Kulüp ve lig kategorilerinde oyuncu, kulüpte en az 20 maça çıkmışsa desteye girer; cevap olarak bütün oyuncular kabul edilir. Oyuncular karışık sırayla gelir. Kullanıcı gelen oyuncuyu uyduğu kutuya koyar ya da pas geçer. Pas sınırsızdır: destede sıra döner, pas geçilen oyuncu sırası gelince tekrar gelir; kutuya yerleşen oyuncu bir daha gelmez. Yanlış kutuya konan oyuncu gitmez, ceza da yoktur; başka kutu denenebilir. Oyuncu sadece doğru kutuya konunca ya da pas geçilince gider. Dolu kutuya oyuncu konamaz. Ekranda kalan oyuncu sayısı gösterilmez. Oyun 12 kutu dolunca, pes edilince ya da süre dolunca biter; kalan oyuncuların hiçbiri boş kutulara uymuyorsa da biter. Skor dolu kutu sayısıdır (en fazla 12). Süre seçenekleri süre yok, 60 ve 90 saniyedir (30 saniye yoktur). Kart desteden her zaman tamamen doldurulabilir.
8. Bingo 8 Kasım 2026'da ilk faza alındı (Mod 4). Başka yeni modlar ilk fazın parçası değildir.
9. Aşağıdakiler **Faz 2** kapsamındadır, ilk fazda yapılmaz:
   - **Zamanlayıcı:** Belirli oyunlarda geri sayım sayacı. (Kesişim, Bonservis ve Izgara'nın süre seçimi istisnadır, madde 7'ye bakınız.)
   - **Zorluk Seviyeleri:** "Kolay" (ör. son 5 yıldaki oyuncular) / "Zor" (ör. tüm zamanlar). (Oyunların kademeye dayalı Kolay / Orta / Zor modları istisnadır, madde 7'ye bakınız.)
   - **Can Hakkı Sistemi:** Bazı oyunlarda 3 veya 5 yanlış cevap hakkı (kalp/can).

## D. Teknik Mimari
10. **Frontend (Mobil) – `mobile/`:** Flutter + Riverpod. Siyah/yeşil karanlık tema ve grid liste yapısı.
11. **Backend (API ve Cron) – `backend/`:** C# ASP.NET Core + Coravel. Her gece tüm oyun modları için yeni sorular üreten otonom motor.
12. **Veri Kaynağı – `data_miner/`:** Python script'i + Dockerize edilmiş Transfermarkt API. 2025/2026 sezonu baz alınarak güncellenmiş oyuncu ve kariyer verileri.
13. **Veritabanı:** Supabase.

## E. Veritabanı Şeması (Supabase)
| Tablo | Açıklama |
|---|---|
| `kulupler` | Sabit veri tablosu. |
| `oyuncular` | Sabit veri tablosu. |
| `kariyer_gecmisi` | Oyuncuların kariyer ve transfer geçmişi için sabit veri tablosu. |
| `gunluk_oyunlar` | Eski `gunun_sorusu` tablosunun genişletilmiş hâli; hangi oyun moduna ait olduğu bilgisini içerir. |
| `kullanici_oyun_gecmisi` (YENİ) | Kullanıcı_ID, Oyun_Modu_ID, Tarih, Skor ve Sonuc alanlarını tutar. Kullanıcının ilgili oyunu oynayıp oynamadığını ve can haklarını takip etmek için gereklidir. |
