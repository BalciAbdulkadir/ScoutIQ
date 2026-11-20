using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Threading.Tasks;
using ScoutIQ.API.Oyunlar;
using Supabase.Postgrest.Exceptions;

namespace ScoutIQ.API.Jobs
{
    // Hedef günün oyunlarını üreten ve veritabanında hangilerinin bulunduğunu söyleyen taraf (DailyQuestionJob).
    // Testlerde sahtesi verilir.
    public interface IOyunUretici
    {
        // Hedef günün eksik oyunlarını üretir. Bir oyunun hatası diğerlerini durdurmaz.
        Task Uret(DateTime hedefTarih);

        // Hedef gün için veritabanında bulunan oyun tipleri
        Task<HashSet<string>> MevcutOyunTipleri(DateTime hedefTarih);
    }

    // Programın bir kez çalışıp kapanan üretim akışı. Google Cloud Run Jobs'ta çalışır, Cloud Scheduler her gün
    // Türkiye saatiyle 18.00 ve 20.00'de başlatır (backend/CLOUD_RUN.md):
    //   1) Hedef tarih belirlenir: --tarih verildiyse o gün, verilmediyse Türkiye saatine göre yarın.
    //   2) Hedef günün eksik oyunları üretilir; hepsi zaten varsa hiçbir şey yapılmaz.
    //   3) Hedef gün için beklenen bütün oyunlar kontrol edilir. Biri bile eksikse program başarısız çıkış koduyla
    //      biter (Cloud Run bunu başarısız çalışma sayar ve uyarı e-postası gider), hepsi varsa başarılı biter.
    public static class UretimCalismasi
    {
        public const int BasariliCikis = 0;
        public const int BasarisizCikis = 1;

        // Elle hedef tarih vermek için: --tarih 2026-11-21 ya da --tarih=2026-11-21
        public const string TarihParametresi = "--tarih";

        // Oyun günleri Türkiye saatine göre başlar ve biter. Cloud Run makineleri UTC'de çalışır: "bugün" ve "yarın"
        // her zaman bu dilime göre hesaplanır, makinenin saat dilimine göre değil.
        public static readonly TimeZoneInfo TurkiyeSaatDilimi = TimeZoneInfo.FindSystemTimeZoneById("Europe/Istanbul");

        // Hedef gün için üretilmesi gereken bütün oyunlar: Kesişim, Bonservis ve Izgara'nın üç modu, Bingo ve Top 10
        public static IReadOnlyList<string> BeklenenOyunTipleri { get; } =
            new[] { "kesisim", "bonservis", "izgara" }
                .SelectMany(oyun => Enum.GetValues<Zorluk>().Select(zorluk => ZorlukDagilimi.OyunTipi(oyun, zorluk)))
                .Append(BingoSoruSecici.OyunTipi)
                .Append(DailyQuestionJob.Top10OyunTipi)
                .ToList();

        public static DateTime TurkiyeBugun(DateTime utcSimdi) =>
            TimeZoneInfo.ConvertTimeFromUtc(DateTime.SpecifyKind(utcSimdi, DateTimeKind.Utc), TurkiyeSaatDilimi).Date;

        public static DateTime VarsayilanHedefTarih(DateTime utcSimdi) => TurkiyeBugun(utcSimdi).AddDays(1);

        // --tarih parametresinin değeri; parametre yoksa null. Değer yoksa ya da yyyy-MM-dd biçiminde değilse
        // ArgumentException fırlatır.
        public static DateTime? ElleVerilenTarih(string[] args)
        {
            for (int i = 0; i < args.Length; i++)
            {
                string? deger = null;
                if (args[i] == TarihParametresi)
                {
                    if (i + 1 >= args.Length)
                        throw new ArgumentException($"{TarihParametresi} parametresinin değeri yok (örnek: {TarihParametresi} 2026-11-21).");
                    deger = args[i + 1];
                }
                else if (args[i].StartsWith(TarihParametresi + "=", StringComparison.Ordinal))
                {
                    deger = args[i][(TarihParametresi.Length + 1)..];
                }
                else
                {
                    continue;
                }

                if (!DateTime.TryParseExact(deger, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var tarih))
                    throw new ArgumentException($"{TarihParametresi} değeri yyyy-MM-dd biçiminde olmalı: '{deger}'.");
                return tarih.Date;
            }
            return null;
        }

        public static DateTime HedefTarih(string[] args, DateTime utcSimdi) => ElleVerilenTarih(args) ?? VarsayilanHedefTarih(utcSimdi);

        // Beklenen oyunlardan veritabanında olmayanlar, beklenen sırayla
        public static List<string> EksikOyunlar(IEnumerable<string> mevcutOyunTipleri)
        {
            var mevcut = mevcutOyunTipleri.ToHashSet();
            return BeklenenOyunTipleri.Where(t => !mevcut.Contains(t)).ToList();
        }

        // Aynı oyunu aynı anda iki çalışma üretirse ikinci kayıt gunluk_oyunlar'daki (oyun_tipi, tarih) tekilliğine
        // takılır (Postgres hata kodu 23505). Bu hata "oyun zaten var" demektir, hata sayılmaz.
        public static bool TekillikIhlali(Exception ex) =>
            ex is PostgrestException p && (p.Content ?? p.Message).Contains("23505", StringComparison.Ordinal);

        public static async Task<int> Calistir(string[] args, DateTime utcSimdi, IOyunUretici uretici)
        {
            DateTime hedef;
            try
            {
                hedef = HedefTarih(args, utcSimdi);
            }
            catch (ArgumentException ex)
            {
                Console.WriteLine($"HATA: {ex.Message}");
                return BasarisizCikis;
            }

            Console.WriteLine($"[{utcSimdi:yyyy-MM-dd HH:mm:ss} UTC] Üretim başladı. Türkiye'de bugün {TurkiyeBugun(utcSimdi):yyyy-MM-dd}, " +
                              $"hedef tarih {hedef:yyyy-MM-dd}" + (ElleVerilenTarih(args) != null ? " (elle verildi)." : " (yarın)."));

            try
            {
                await uretici.Uret(hedef);
            }
            catch (Exception ex)
            {
                // Sonuç aşağıdaki kontrole göre belirlenir: oyunların hepsi varsa çalışma yine başarılıdır
                Console.WriteLine($"HATA: Üretim yarıda kaldı: {ex.Message}");
            }

            HashSet<string> mevcut;
            try
            {
                mevcut = await uretici.MevcutOyunTipleri(hedef);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"HATA: {hedef:yyyy-MM-dd} günün oyunları kontrol edilemedi: {ex.Message}");
                return BasarisizCikis;
            }

            var eksikler = EksikOyunlar(mevcut);
            if (eksikler.Count > 0)
            {
                Console.WriteLine($"HATA: {hedef:yyyy-MM-dd} için {eksikler.Count} oyun eksik: {string.Join(", ", eksikler)}");
                return BasarisizCikis;
            }

            Console.WriteLine($"Tamam: {hedef:yyyy-MM-dd} için beklenen {BeklenenOyunTipleri.Count} oyunun hepsi veritabanında.");
            return BasariliCikis;
        }
    }
}
