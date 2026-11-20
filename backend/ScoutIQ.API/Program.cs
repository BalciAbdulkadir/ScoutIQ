using Microsoft.Extensions.Configuration;
using ScoutIQ.API.Jobs;
using Supabase;

// ScoutIQ soru üretim işi. Bir kez çalışır, hedef günün eksik oyunlarını üretir ve kapanır; web sunucusu ya da
// zamanlayıcı yoktur. Google Cloud Run Jobs'ta çalışır, Cloud Scheduler her gün Türkiye saatiyle 18.00 ve 20.00'de
// başlatır (backend/CLOUD_RUN.md).
//
//   dotnet run                                  Türkiye saatine göre yarının eksik oyunlarını üretir
//   dotnet run -- --tarih 2026-11-21            Verilen günün eksik oyunlarını üretir (acil durum: bugünün eksiğini
//                                               tamamlamak ya da belirli bir günü üretmek için)
//   dotnet run -- --kesisim-onizleme            Her moddan bir soru seti seçip ekrana basar, veritabanına yazmaz
//   dotnet run -- --bonservis-onizleme          Her moddan bir Bonservis soru seti seçip ekrana basar, veritabanına yazmaz
//   dotnet run -- --izgara-onizleme             Her moddan bir Izgara tahtası seçip ekrana basar, veritabanına yazmaz
//   dotnet run -- --bingo-onizleme              Bir Bingo kartı seçip ekrana basar, veritabanına yazmaz
//   dotnet run -- --top10-onizleme              Top 10 sorusunu seçip ekrana basar, veritabanına yazmaz
// Kesişim ve Top 10 önizlemeleri de hedef tarihe göre seçer (varsayılan yarın, --tarih ile başka bir gün).
//
// Çıkış kodu: hedef günün beklenen bütün oyunları veritabanındaysa 0, biri bile eksikse 1.
//
// Ayarlar: Supabase:Url appsettings.json'dadır. Supabase:Key (secret anahtar) hiçbir dosyada tutulmaz:
// Cloud Run'da Secret Manager'dan Supabase__Key ortam değişkeni olarak verilir, yerelde user-secrets'tadır
// (dotnet user-secrets set "Supabase:Key" "...").

var ayarlar = new ConfigurationBuilder()
    .SetBasePath(AppContext.BaseDirectory)
    .AddJsonFile("appsettings.json", optional: true)
    .AddUserSecrets<Program>(optional: true)
    .AddEnvironmentVariables()
    .Build();

var supabaseUrl = ayarlar["Supabase:Url"];
var supabaseKey = ayarlar["Supabase:Key"];
if (string.IsNullOrWhiteSpace(supabaseUrl) || string.IsNullOrWhiteSpace(supabaseKey))
{
    Console.WriteLine("HATA: Supabase:Url ya da Supabase:Key ayarı yok (Cloud Run'da Supabase__Key ortam değişkeni, yerelde user-secrets).");
    return UretimCalismasi.BasarisizCikis;
}

var uretici = new DailyQuestionJob(new Client(supabaseUrl, supabaseKey, new SupabaseOptions { AutoConnectRealtime = false }));

var onizlemeler = new Dictionary<string, Func<DateTime, Task>>
{
    ["--kesisim-onizleme"] = uretici.KesisimOnizleme,
    ["--bonservis-onizleme"] = _ => uretici.BonservisOnizleme(),
    ["--izgara-onizleme"] = _ => uretici.IzgaraOnizleme(),
    ["--bingo-onizleme"] = _ => uretici.BingoOnizleme(),
    ["--top10-onizleme"] = uretici.Top10Onizleme,
};

var onizleme = onizlemeler.Keys.FirstOrDefault(args.Contains);
if (onizleme != null)
{
    var utcSimdi = DateTime.UtcNow;
    var hedef = UretimCalismasi.HedefTarih(args, utcSimdi);
    Console.WriteLine($"[{utcSimdi:yyyy-MM-dd HH:mm:ss} UTC] Önizleme. Türkiye'de bugün {UretimCalismasi.TurkiyeBugun(utcSimdi):yyyy-MM-dd}, " +
                      $"hedef tarih {hedef:yyyy-MM-dd}.");
    await onizlemeler[onizleme](hedef);
    return UretimCalismasi.BasariliCikis;
}

return await UretimCalismasi.Calistir(args, DateTime.UtcNow, uretici);
