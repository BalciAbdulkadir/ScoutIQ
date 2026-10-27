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
7. İlk faz oyun modları:
   - **Mod 1 – Kesişim Bulmacası:** Rastgele seçilen iki takımın ortak oyuncusunu bulma. (Mevcut geliştirme aşamasındaki oyun.)
   - **Mod 2 – Bonservis Kıyaslaması:** İki oyuncunun geçmiş transfer bedellerini Daha Az / Daha Fazla mantığıyla karşılaştırma.
   - **Mod 3 – Izgara (3x3):** Satır ve sütun başlıklarının ikisine de uyan oyuncuları bulma. Kolay (sadece kulüpler), Orta (kulüpler + bilinen 20 milli takım) ve Zor (kulüpler + diğer milli takımlar) ayrı oyunlardır, her biri günde bir kez oynanır. Bir tahtada en fazla 2 milli takım olur. Toplam 9 tahmin hakkı vardır; kullanıcı hücre seçmez, doğru oyuncu uygun hücreye yerleşir. Aynı oyuncu iki kez kullanılamaz, pes edilebilir.
8. Bingo tarzı modlar **ileride** eklenecektir; ilk fazın parçası değildir.
9. Aşağıdakiler **Faz 2** kapsamındadır, ilk fazda yapılmaz:
   - **Zamanlayıcı:** Belirli oyunlarda geri sayım sayacı.
   - **Zorluk Seviyeleri:** "Kolay" (ör. son 5 yıldaki oyuncular) / "Zor" (ör. tüm zamanlar). (Izgara'nın kendi zorlukları istisnadır, Mod 3'e bakınız.)
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
