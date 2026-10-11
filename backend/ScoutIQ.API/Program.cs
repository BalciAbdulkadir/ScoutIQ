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

// 3. Zamanlayıcıyı yapılandıralım
app.Services.UseScheduler(scheduler =>
{
    // Türkiye saatine göre her gece 00:00'da çalışacak şekilde ayarlıyoruz.
    // Şimdilik test edebilmen için "EveryMinute()" da yapabilirsin ama orijinali DailyAtHour'dur.
    scheduler.Schedule<DailyQuestionJob>()
             .DailyAtHour(0)
             .Zoned(TimeZoneInfo.Local); 
});

app.MapControllers();

app.Run();
