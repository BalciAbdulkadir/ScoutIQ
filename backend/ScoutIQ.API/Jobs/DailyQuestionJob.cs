using Coravel.Invocable;
using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Supabase;
using ScoutIQ.API.Models;
using System.Linq;
using System.Text.Json;

namespace ScoutIQ.API.Jobs
{
    public class DailyQuestionJob : IInvocable
    {
        // Oyun günleri Türkiye saatine göre başlar ve biter
        public static readonly TimeZoneInfo TurkiyeSaatDilimi = TimeZoneInfo.FindSystemTimeZoneById("Europe/Istanbul");

        private const int KesisimSoruSayisi = 5;
        private const int MaxDeneme = 200;

        private readonly Client _supabaseClient;

        public DailyQuestionJob(Client supabaseClient)
        {
            _supabaseClient = supabaseClient;
        }

        public async Task Invoke()
        {
            DateTime bugun = TimeZoneInfo.ConvertTimeFromUtc(DateTime.UtcNow, TurkiyeSaatDilimi).Date;
            Console.WriteLine($"[{DateTime.Now}] CRON TETİKLENDİ: {bugun:yyyy-MM-dd} için Hub oyunları hazırlanıyor...");

            try
            {
                // 1. Kesişim Oyunu İçin 5 Soruluk Set Üret
                await UretKesisimOyunlari(bugun);

                // 2. Bonservis Oyunu İçin Set Üret (Şimdilik boş, ileride içini dolduracağız)
                // await UretBonservisOyunlari(bugun);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Hata oluştu: {ex.Message}");
            }
        }

        private async Task<bool> OyunVarMi(string oyunTipi, DateTime tarih)
        {
            var response = await _supabaseClient.From<GunlukOyun>()
                .Select("id")
                .Filter("oyun_tipi", Supabase.Postgrest.Constants.Operator.Equals, oyunTipi)
                .Filter("tarih", Supabase.Postgrest.Constants.Operator.Equals, tarih.ToString("yyyy-MM-dd"))
                .Get();

            return response.Models.Count > 0;
        }

        private async Task UretKesisimOyunlari(DateTime tarih)
        {
            if (await OyunVarMi("kesisim", tarih))
            {
                Console.WriteLine($"Kesişim: {tarih:yyyy-MM-dd} için oyun zaten var, atlanıyor.");
                return;
            }

            var kuluplerResponse = await _supabaseClient.From<Kulup>().Select("id, isim").Get();
            var kulupler = kuluplerResponse.Models;

            if (kulupler.Count < 2)
            {
                Console.WriteLine("Uyarı: Kesişim için veritabanında yeterli kulüp yok.");
                return;
            }

            var random = new Random();
            var sorular = new List<object>(); // 5 soruluk JSON dizimiz
            var kullanilanCiftler = new HashSet<string>();
            int denemeSayisi = 0;

            while (sorular.Count < KesisimSoruSayisi && denemeSayisi < MaxDeneme)
            {
                denemeSayisi++;
                var kulupA = kulupler[random.Next(kulupler.Count)];
                var kulupB = kulupler[random.Next(kulupler.Count)];

                if (kulupA.Id == kulupB.Id) continue;

                // Aynı iki takımı (hangi sırayla gelirse gelsin) tekrar sormamak için
                string cift = string.CompareOrdinal(kulupA.Id, kulupB.Id) < 0
                    ? $"{kulupA.Id}|{kulupB.Id}"
                    : $"{kulupB.Id}|{kulupA.Id}";
                if (kullanilanCiftler.Contains(cift)) continue;

                var parametreler = new Dictionary<string, object>
                {
                    { "kulup_a_id", kulupA.Id },
                    { "kulup_b_id", kulupB.Id }
                };

                var rpcResponse = await _supabaseClient.Rpc("get_ortak_oyuncular", parametreler);
                if (string.IsNullOrEmpty(rpcResponse.Content)) continue;

                using var ortakOyuncular = JsonDocument.Parse(rpcResponse.Content);
                if (ortakOyuncular.RootElement.GetArrayLength() == 0) continue;

                kullanilanCiftler.Add(cift);
                sorular.Add(new
                {
                    kulup_a = kulupA.Isim,
                    kulup_b = kulupB.Isim,
                    kulup_a_id = kulupA.Id,
                    kulup_b_id = kulupB.Id
                });
            }

            if (sorular.Count == KesisimSoruSayisi)
            {
                var yeniOyun = new GunlukOyun
                {
                    OyunTipi = "kesisim",
                    Tarih = tarih,
                    SoruVerisi = sorular
                };

                await _supabaseClient.From<GunlukOyun>().Insert(yeniOyun);
                Console.WriteLine($"Başarılı: Kesişim için {tarih:yyyy-MM-dd} tarihli 5 soruluk set eklendi ({denemeSayisi} denemede).");
            }
            else
            {
                Console.WriteLine($"Uyarı: Kesişim için 5 eşleşme bulunamadı. Bulunan: {sorular.Count} (Veritabanında yeterli kariyer verisi yok)");
            }
        }
    }
}