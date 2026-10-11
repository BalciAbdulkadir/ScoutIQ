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
        private readonly Client _supabaseClient;

        public DailyQuestionJob(Client supabaseClient)
        {
            _supabaseClient = supabaseClient;
        }

        public async Task Invoke()
        {
            Console.WriteLine($"[{DateTime.Now}] CRON TETİKLENDİ: Yeni nesil Hub oyunları hazırlanıyor...");
            DateTime yarin = DateTime.UtcNow.AddDays(1).Date;

            try
            {
                // 1. Kesişim Oyunu İçin 5 Soruluk Set Üret
                await UretKesisimOyunlari(yarin);

                // 2. Bonservis Oyunu İçin Set Üret (Şimdilik boş, ileride içini dolduracağız)
                // await UretBonservisOyunlari(yarin);
                
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Hata oluştu: {ex.Message}");
            }
        }

        private async Task UretKesisimOyunlari(DateTime tarih)
        {
            var kuluplerResponse = await _supabaseClient.From<Kulup>().Select("id").Get();
            var kulupIdListesi = kuluplerResponse.Models.Select(k => k.Id).ToList();

            var random = new Random();
            var sorular = new List<object>(); // 5 soruluk JSON dizimiz
            int denemeSayisi = 0;
            int maxDeneme = 200; // 5 soru bulmak için limiti artırdık

            while (sorular.Count < 5 && denemeSayisi < maxDeneme)
            {
                denemeSayisi++;
                string kulupA = kulupIdListesi[random.Next(kulupIdListesi.Count)];
                string kulupB = kulupIdListesi[random.Next(kulupIdListesi.Count)];

                if (kulupA == kulupB) continue;

                var parametreler = new Dictionary<string, object>
                {
                    { "kulup_a_id", kulupA },
                    { "kulup_b_id", kulupB }
                };

                var rpcResponse = await _supabaseClient.Rpc("get_ortak_oyuncular", parametreler);
                
                if (rpcResponse.Content != null && rpcResponse.Content.Length > 5)
                {
                    // Aynı iki takımı tekrar tekrar sormamak için kontrol
                    bool zatenVar = sorular.Any(s => 
                        JsonSerializer.Serialize(s).Contains(kulupA) && 
                        JsonSerializer.Serialize(s).Contains(kulupB));

                    if (!zatenVar)
                    {
                        sorular.Add(new { kulup_a = kulupA, kulup_b = kulupB });
                    }
                }
            }

            if (sorular.Count == 5)
            {
                var yeniOyun = new GunlukOyun
                {
                    OyunTipi = "kesisim",
                    Tarih = tarih,
                    SoruVerisi = sorular
                };

                await _supabaseClient.From<GunlukOyun>().Insert(yeniOyun);
                Console.WriteLine("Başarılı: Kesişim için 5 soruluk set JSONB olarak eklendi.");
            }
            else
            {
                Console.WriteLine($"Uyarı: Kesişim için 5 eşleşme bulunamadı. Bulunan: {sorular.Count} (Veritabanında yeterli kariyer verisi yok)");
            }
        }
    }
}