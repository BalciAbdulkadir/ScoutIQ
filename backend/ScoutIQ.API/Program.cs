using Coravel;
using ScoutIQ.API.Jobs;
using Supabase;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();

// 1. Supabase İstemcisini Singleton olarak enjekte edelim
var supabaseUrl = builder.Configuration["Supabase:Url"];
var supabaseKey = builder.Configuration["Supabase:Key"];
var supabaseOptions = new SupabaseOptions { AutoConnectRealtime = true };

builder.Services.AddSingleton(provider => 
    new Client(supabaseUrl, supabaseKey, supabaseOptions));

// 2. Coravel Zamanlayıcısını ve Job'ımızı servislere ekleyelim
builder.Services.AddScheduler();
builder.Services.AddTransient<DailyQuestionJob>();

var app = builder.Build();

// Zorluk ayarı için: "dotnet run -- --kesisim-onizleme" bir soru seti seçip ekrana basar, veritabanına yazmaz
if (args.Contains("--kesisim-onizleme"))
{
    await app.Services.GetRequiredService<DailyQuestionJob>().KesisimOnizleme();
    return;
}

// "dotnet run -- --bonservis-onizleme" bir Bonservis soru seti seçip ekrana basar, veritabanına yazmaz
if (args.Contains("--bonservis-onizleme"))
{
    await app.Services.GetRequiredService<DailyQuestionJob>().BonservisOnizleme();
    return;
}

// "dotnet run -- --izgara-onizleme" her zorluktan bir Izgara tahtası seçip ekrana basar, veritabanına yazmaz
if (args.Contains("--izgara-onizleme"))
{
    await app.Services.GetRequiredService<DailyQuestionJob>().IzgaraOnizleme();
    return;
}

// 3. Zamanlayıcıyı yapılandıralım

app.Services.UseScheduler(scheduler =>
{
    // Her gece Türkiye saatiyle 00:00'da o günün oyunlarını üretir.
    // RunOnceAtStart: uygulama açılınca da bir kez çalışır, bugünün oyunu eksikse tamamlanır.
    // Job o gün için oyun zaten varsa yenisini üretmez.
    scheduler.Schedule<DailyQuestionJob>()
             .DailyAt(0, 0)
             .Zoned(DailyQuestionJob.TurkiyeSaatDilimi)
             .RunOnceAtStart()
             .PreventOverlapping(nameof(DailyQuestionJob));
});

app.MapControllers();

app.Run();
