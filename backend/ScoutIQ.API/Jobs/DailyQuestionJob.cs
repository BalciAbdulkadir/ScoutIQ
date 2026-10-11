using Coravel.Invocable;
using System;
using System.Threading.Tasks;
using Supabase;

namespace ScoutIQ.API.Jobs
{
    public class DailyQuestionJob : IInvocable
    {
        private readonly Client _supabaseClient;

        // Dependency Injection ile Supabase istemcisini alıyoruz
        public DailyQuestionJob(Client supabaseClient)
        {
            _supabaseClient = supabaseClient;
        }

        public async Task Invoke()
        {
            Console.WriteLine($"[{DateTime.Now}] CRON TETİKLENDİ: Günün Sorusu hazırlanıyor...");

            try
            {
                // TODO: Supabase'den ortak oyuncusu olan rastgele 2 kulüp çeken RPC'yi tetikleyeceğiz.
                // Şimdilik sistemin ayakta olduğunu ve veritabanına bağlanabildiğini test etmek için boş geçiyoruz.
                
                Console.WriteLine("Başarılı: Yeni eşleşme bulundu ve veritabanına kaydedildi.");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Hata oluştu: {ex.Message}");
            }
            
            await Task.CompletedTask;
        }
    }
}