# Backend'in Google Cloud Run'da kurulumu

Backend, her gün yarının bütün oyunlarını üreten bir **Cloud Run Job**'dır. Sürekli açık bir sunucu yoktur:

- **Cloud Scheduler** işi her gün iki kez başlatır (Türkiye saatiyle):
  - **18.00:** yarının oyunları üretilir.
  - **20.00:** eksik kalan varsa tamamlanır, hepsi varsa bir şey yapılmaz.
- İş çalışır, kapanır.
- Oyunlar kullanıcıya 00.00'da açılır.
- 20.00 çalışmasının sonunda yarının bir oyunu hâlâ eksikse iş **başarısız** biter ve uyarı e-postası gelir. Gece yarısına kadar düzeltmek için en az 4 saat kalır.

Bu rehberdeki adımlar Google Cloud konsolundan elle yapılır. Gizli bilgi (anahtar, şifre) bu dosyaya ve repoya yazılmaz.

**Proje:** Google girişinin ve Firebase'in bulunduğu proje kullanılır (proje numarası `127593072442`). Yeni proje açılmaz.

Aşağıda şu yer tutucular geçer:

| Yer tutucu | Ne yazılır |
|---|---|
| `PROJE_ID` | Projenin kimliği (numara değil, konsolun üst çubuğunda yazan ad, ör. `footylore-xxxx`) |
| `BOLGE` | 3. adımda seçilen bölge (ör. `europe-west3`) |

---

## Program nasıl çalışır

| Komut | Ne yapar |
|---|---|
| (parametresiz) | Türkiye saatine göre yarının eksik oyunlarını üretir |
| `--tarih 2026-11-21` | Verilen günün eksik oyunlarını üretir (acil durum) |
| `--kesisim-onizleme`, `--bonservis-onizleme`, `--izgara-onizleme`, `--bingo-onizleme`, `--top10-onizleme` | Seçimi ekrana basar, veritabanına **yazmaz** |

**Çıkış kodu:**
- Hedef günün 11 oyununun hepsi veritabanındaysa `0`: Kesişim, Bonservis ve Izgara'nın kolay/orta/zor modları, Bingo ve Top 10.
- Biri bile eksikse `1`. Cloud Run bunu başarısız çalışma sayar.

**Ayarlar:**
- `Supabase:Url` → `appsettings.json`'da.
- `Supabase:Key` → Supabase **secret** anahtarı. Hiçbir dosyada tutulmaz:
  - Cloud Run'da `Supabase__Key` ortam değişkeniyle Secret Manager'dan gelir.
  - Yerelde user-secrets'tadır: `dotnet user-secrets set "Supabase:Key" "..."`.

Aynı oyunu iki çalışma aynı anda üretmeye kalkarsa, ikincisi veritabanının (oyun_tipi, tarih) tekilliğine takılır. Program bunu "oyun zaten var" sayar, hata saymaz.

---

## 1. Faturalandırma ve bütçe uyarısı

**Neden:** Cloud Run ve Scheduler faturalandırma hesabı olmadan çalışmaz. Bu iş ücretsiz katmanda kalır, ama beklenmedik bir fatura erken fark edilmelidir.

1. **Billing** → projeye bir faturalandırma hesabı bağlanır (kredi kartı).
2. Hemen ardından **Billing → Budgets & alerts → Create budget**:
   - Kapsam: bu proje
   - Tutar: aylık 5 USD
   - Eşikler: %50, %90, %100
   - Bildirim: `nqxcraft@gmail.com` (faturalandırma yöneticisi değilse, 8. adımdaki e-posta kanalı bütçeye de bağlanır)

## 2. API'ler

**Neden:** Kullanılacak servisler projede varsayılan olarak kapalıdır.

**APIs & Services → Enable APIs** ile şunlar açılır:
- Cloud Run Admin API
- Cloud Scheduler API
- Artifact Registry API
- Secret Manager API

## 3. Bölge

**Neden:** İş bütün oyuncu verisini Supabase'den okur. Supabase'e yakın bölge hem hızlıdır hem de bölgeler arası trafik ücreti çıkarmaz.

Supabase'in bölgesine **Supabase → Project Settings → General**'dan bakılır. En yakın Google bölgesi seçilir:

| Supabase | Google Cloud |
|---|---|
| eu-central-1 (Frankfurt) | europe-west3 |
| eu-west-1 (İrlanda) | europe-west1 (Belçika) |
| eu-west-2 (Londra) | europe-west2 |
| eu-west-3 (Paris) | europe-west9 |
| eu-north-1 (Stockholm) | europe-north1 (Finlandiya) |

Artifact Registry, Cloud Run ve Scheduler'ın hepsi **aynı bölgede** kurulur.

## 4. Secret Manager: Supabase secret anahtarı

**Neden:** Anahtar imaja, `appsettings.json`'a ya da repoya girmez. Sadece işin servis hesabı okuyabilir.

1. **Security → Secret Manager → Create secret**:
   - Ad: `supabase-secret-key`
   - Değer: Supabase → Project Settings → API Keys → **secret** anahtar (publishable anahtar değil)
   - Replication: otomatik ya da sadece seçilen bölge
2. Anahtar değişirse yeni bir sürüm (version) eklenir. İş `latest` sürümü okur.

## 5. Artifact Registry: imaj deposu

**Neden:** Cloud Run, çalıştıracağı container imajını buradan çeker.

**Artifact Registry → Create repository**:
- Ad: `scoutiq`
- Biçim: Docker
- Bölge: `BOLGE`

## 6. Servis hesabı ve Cloud Run Job

**Neden:**
- İş, kendine ait ve sadece gerektiği kadar yetkisi olan bir hesapla çalışır.
- Varsayılan hesabın projede düzenleyici yetkisi vardır, kullanılmaz.

### 6.1 Servis hesabı

1. **IAM & Admin → Service Accounts → Create**. Ad: `scoutiq-uretim`. Projeye rol **verilmez**.
2. Secret Manager → `supabase-secret-key` → **Permissions → Grant access**: `scoutiq-uretim` hesabına **Secret Manager Secret Accessor**.
3. İş oluşturulduktan sonra (6.3), işin **Permissions** sekmesinden `scoutiq-uretim` hesabına **Cloud Run Invoker** verilir. Scheduler işi bu hesapla başlatır (7. adım).

Bu hesap sadece iki şeyi yapabilir: gizli anahtarı okumak ve bu işi çalıştırmak.

### 6.2 İlk imaj

İmaj ilk aşamada elle derlenip yüklenir (9. adım). İşi oluşturmadan önce bir kez yapılır.

### 6.3 İş

**Cloud Run → Jobs → Create job**:

| Ayar | Değer | Neden |
|---|---|---|
| Container image | `BOLGE-docker.pkg.dev/PROJE_ID/scoutiq/uretim:latest` | |
| Job name | `scoutiq-uretim` | |
| Region | `BOLGE` | |
| Number of tasks | 1 | Üretim tek parça çalışır |
| Memory | 2 GiB | İş bütün oyuncu verisini belleğe okur. Önizlemede ölçülüp 1 GiB'e indirilebilir. |
| CPU | 1 | |
| Task timeout | 30 dakika | Normal çalışma birkaç dakika sürer |
| Max retries per task | 1 | Geçici bir bağlantı hatası bir kez daha denenir |
| Service account | `scoutiq-uretim` | |
| Variables & Secrets → Secret exposed as environment variable | Ad: `Supabase__Key`, secret: `supabase-secret-key`, sürüm: `latest` | Program anahtarı bu ortam değişkeninden okur (iki alt çizgi `Supabase:Key` demektir) |

Komut ve argüman boş bırakılır. İmaj parametresiz çalışır, yani yarını üretir.

## 7. Cloud Scheduler: 18.00 ve 20.00

**Neden:** İşi her gün başlatır. Her faturalandırma hesabına ayda 3 tetikleyici ücretsizdir; bu ikisi ücretsiz katmanda kalır.

Kolay yol: Cloud Run → Jobs → `scoutiq-uretim` → **Triggers → Add scheduler trigger**. İki tetikleyici kurulur:

| Ad | Sıklık (cron) | Saat dilimi |
|---|---|---|
| `scoutiq-uretim-18` | `0 18 * * *` | Europe/Istanbul (GMT+3) |
| `scoutiq-uretim-20` | `0 20 * * *` | Europe/Istanbul (GMT+3) |

İkisinde de servis hesabı `scoutiq-uretim` seçilir.

Cloud Scheduler sayfasından elle kurulursa:
- Hedef: HTTP, `POST`
- URL: `https://run.googleapis.com/v2/projects/PROJE_ID/locations/BOLGE/jobs/scoutiq-uretim:run`
- Auth header: OAuth token, servis hesabı `scoutiq-uretim`, kapsam `https://www.googleapis.com/auth/cloud-platform`

## 8. Başarısız çalışma uyarısı

**Neden:** İş başarısız olursa ya da yarının bir oyunu eksik kalırsa (program 1 koduyla biter), gece yarısından önce haber gelir.

1. **Monitoring → Alerting → Edit notification channels → Email → Add new**: `nqxcraft@gmail.com`.
2. **Monitoring → Alerting → Create policy**:
   - Metrik: **Cloud Run Job → Job → Completed Execution Count** (`run.googleapis.com/job/completed_execution_count`)
   - Filtre: `job_name = scoutiq-uretim`, `result = failed`
   - Dönüştürme: rolling window 5 dakika, sum
   - Koşul: değer 0'ın üzerinde
   - Bildirim kanalı: 1. adımdaki e-posta
   - Ad: `ScoutIQ üretim işi başarısız`

## 9. Dağıtım (imajı derleyip yüklemek)

İlk aşamada elle yapılır. Komutlar repo kökünden çalıştırılır; Docker ve `gcloud` kurulu, `gcloud auth login` yapılmış olmalıdır.

```sh
# Bir kez: Docker'ın Artifact Registry'ye yükleyebilmesi için
gcloud auth configure-docker BOLGE-docker.pkg.dev

# Her güncellemede
docker build -t BOLGE-docker.pkg.dev/PROJE_ID/scoutiq/uretim:latest backend
docker push BOLGE-docker.pkg.dev/PROJE_ID/scoutiq/uretim:latest
gcloud run jobs update scoutiq-uretim --image BOLGE-docker.pkg.dev/PROJE_ID/scoutiq/uretim:latest --region BOLGE
```

- Backend'de değişiklik `main`'e birleştikten sonra imaj yeniden yüklenir. Yüklenmezse iş eski kodla çalışmaya devam eder.
- Apple Silicon (ARM) bir Mac'te derlenirse `docker build`'e `--platform linux/amd64` eklenir.
- GitHub Actions ile otomatik dağıtım istenirse ayrıca karar verilir.

---

## Geçiş planı

1. **Kurulum:** Branch birleşir, imaj yüklenir, iş kurulur (1–6. adımlar). Scheduler tetikleyicileri henüz **kurulmaz**.
2. **Önizleme:** İş bir önizleme bayrağıyla elle çalıştırılır. Veritabanına yazmaz.
   - Cloud Run → Jobs → `scoutiq-uretim` → **Execute with overrides** → Arguments: `--top10-onizleme`
   - Logda şunlar görülmelidir: "Türkiye'de bugün … hedef tarih …" satırında doğru günler (saat dilimi), oyuncu sayıları (bağlantı ve anahtar) ve bir Top 10 sorusu.
   - Bellek: Cloud Run → Jobs → Executions → Metrics'ten bakılır, gerekirse 6.3'teki ayar düşürülür.
3. **İlk gerçek çalışma:** İş parametresiz, elle bir kez çalıştırılır (**Execute**). Sonra iki şey kontrol edilir:
   - Supabase'de yarının 11 oyunu oluşmuştur: `select oyun_tipi from gunluk_oyunlar where tarih = (now() at time zone 'Europe/Istanbul')::date + 1;`
   - Uygulamada hâlâ bugünün oyunları görünür.
4. **Eski makine:** Scheduler tetikleyicileri kurulur (7. adım). Aynı gün `192.168.1.107`'deki eski backend **kapatılır**.
   - Eski backend gece yarısı çalışsa bile oyunlar zaten var olduğu için bir şey üretmez.
   - Yine de iki üreticinin aynı anda açık kalması istenmez.
5. **Kontrol:** İlk üç gün her akşam 20.00'den sonra **Logging → Logs Explorer**'da iki çalışmanın sonucuna bakılır.
   - Filtre: `resource.type="cloud_run_job" resource.labels.job_name="scoutiq-uretim"`
   - Son satır "Tamam: … 11 oyunun hepsi veritabanında" olmalıdır.
6. **Uyarı testi:** Bir kez bilerek başarısız bir çalışma yapılır ve uyarı e-postasının geldiği görülür.
   - **Execute with overrides** → Environment variables: `Supabase__Key` = `yanlis`. Bu çalışma yarının oyunlarını kontrol edemez ve 1 koduyla biter.
   - Override sadece o çalışma içindir, kalıcı ayar değişmez.

## Acil durum

20.00 çalışmasından sonra yarının bir oyunu hâlâ eksikse uyarı e-postası gelmiştir.

1. Logs Explorer'dan hata okunur. "HATA: … için N oyun eksik: …" satırı hangi oyunların eksik olduğunu söyler.
2. Sorun düzeltilir ve iş elle tekrar çalıştırılır (**Execute**).
   - Gece yarısı geçtiyse bugünün tarihi parametreyle verilir: **Execute with overrides** → Arguments: `--tarih 2026-11-21`.
