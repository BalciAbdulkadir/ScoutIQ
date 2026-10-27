using Coravel.Invocable;
using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Supabase;
using ScoutIQ.API.Models;
using ScoutIQ.API.Oyunlar;
using System.Linq;
using static Supabase.Postgrest.Constants;

namespace ScoutIQ.API.Jobs
{
    public class DailyQuestionJob : IInvocable
    {
        // Oyun günleri Türkiye saatine göre başlar ve biter
        public static readonly TimeZoneInfo TurkiyeSaatDilimi = TimeZoneInfo.FindSystemTimeZoneById("Europe/Istanbul");

        private const int SayfaBoyutu = 1000; // Supabase tek istekte en fazla 1000 satır döndürür

        private readonly Client _supabaseClient;

        public DailyQuestionJob(Client supabaseClient)
        {
            _supabaseClient = supabaseClient;
        }

        public async Task Invoke()
        {
            DateTime bugun = TimeZoneInfo.ConvertTimeFromUtc(DateTime.UtcNow, TurkiyeSaatDilimi).Date;
            Console.WriteLine($"[{DateTime.Now}] CRON TETİKLENDİ: {bugun:yyyy-MM-dd} için Hub oyunları hazırlanıyor...");

            // Oyunlar ayrı ayrı denenir: birinde hata olursa diğeri yine üretilir
            try
            {
                await UretKesisimOyunlari(bugun);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Kesişim: hata oluştu: {ex.Message}");
            }

            try
            {
                await UretBonservisOyunlari(bugun);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Bonservis: hata oluştu: {ex.Message}");
            }
        }

        private async Task<bool> OyunVarMi(string oyunTipi, DateTime tarih)
        {
            var response = await _supabaseClient.From<GunlukOyun>()
                .Select("id")
                .Filter("oyun_tipi", Operator.Equals, oyunTipi)
                .Filter("tarih", Operator.Equals, tarih.ToString("yyyy-MM-dd"))
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

            var sorular = await KesisimSorulariniSec();
            if (sorular == null) return;

            var yeniOyun = new GunlukOyun
            {
                OyunTipi = "kesisim",
                Tarih = tarih,
                SoruVerisi = sorular.Select(s => new
                {
                    kulup_a = s.Cift.KulupA.Isim,
                    kulup_b = s.Cift.KulupB.Isim,
                    kulup_a_id = s.Cift.KulupA.Id,
                    kulup_b_id = s.Cift.KulupB.Id,
                    zorluk = s.Zorluk.ToString().ToLowerInvariant()
                }).ToList()
            };

            await _supabaseClient.From<GunlukOyun>().Insert(yeniOyun);
            Console.WriteLine($"Başarılı: Kesişim için {tarih:yyyy-MM-dd} tarihli 5 soruluk set eklendi.");
            foreach (var soru in sorular)
            {
                Console.WriteLine($"   [{soru.Zorluk}] {soru.Cift.KulupA.Isim} x {soru.Cift.KulupB.Isim} ({soru.Cift.OrtakOyuncuSayisi} ortak oyuncu)");
            }
        }

        // Veritabanına yazmadan bir soru seti seçip ekrana basar. Zorluk eşiklerini ayarlarken kullanılır:
        // dotnet run -- --kesisim-onizleme
        public async Task KesisimOnizleme()
        {
            var sorular = await KesisimSorulariniSec(ayrintili: true);
            if (sorular == null) return;

            Console.WriteLine("Önizleme (veritabanına yazılmadı):");
            for (int i = 0; i < sorular.Count; i++)
            {
                var soru = sorular[i];
                Console.WriteLine($"   {i + 1}. [{soru.Zorluk}] {soru.Cift.KulupA.Isim} x {soru.Cift.KulupB.Isim} ({soru.Cift.OrtakOyuncuSayisi} ortak oyuncu)");
            }
        }

        // Kulüpleri ve kariyer geçmişini veritabanından çeker, seçimi KesisimSoruSecici'ye bırakır
        private async Task<List<KesisimSoruSecici.KesisimSorusu>?> KesisimSorulariniSec(bool ayrintili = false)
        {
            var kuluplerResponse = await _supabaseClient.From<Kulup>().Select("id, isim, lig, transfermarkt_id").Get();
            var kulupler = kuluplerResponse.Models;

            if (kulupler.Count < 2)
            {
                Console.WriteLine("Uyarı: Kesişim için veritabanında yeterli kulüp yok.");
                return null;
            }

            KulupListesiniKontrolEt(KesisimSoruSecici.BuyukKulupler, "büyük", kulupler, ayrintili);
            KulupListesiniKontrolEt(KesisimSoruSecici.BasAltiKulupler, "baş altı", kulupler, ayrintili);

            var sonuc = new KesisimSoruSecici().Sec(kulupler, await TumKariyerGecmisi());

            var havuz = sonuc.HavuzBoyutlari;
            Console.WriteLine($"Kesişim havuzları: {havuz[KesisimSoruSecici.Zorluk.Kolay]} kolay, {havuz[KesisimSoruSecici.Zorluk.Orta]} orta-zor, {havuz[KesisimSoruSecici.Zorluk.Zor]} zor çift.");
            foreach (var uyari in sonuc.Uyarilar)
            {
                Console.WriteLine($"Uyarı: {uyari}");
            }

            return sonuc.Sorular;
        }

        private async Task UretBonservisOyunlari(DateTime tarih)
        {
            if (await OyunVarMi("bonservis", tarih))
            {
                Console.WriteLine($"Bonservis: {tarih:yyyy-MM-dd} için oyun zaten var, atlanıyor.");
                return;
            }

            var sorular = await BonservisSorulariniSec();
            if (sorular == null) return;

            // Toplam bonservisler de kaydedilir: cevaptan sonra ekranda gösterilir
            var yeniOyun = new GunlukOyun
            {
                OyunTipi = "bonservis",
                Tarih = tarih,
                SoruVerisi = sorular.Select(s => new
                {
                    oyuncu_a = s.Sol.Isim,
                    oyuncu_b = s.Sag.Isim,
                    oyuncu_a_id = s.Sol.Id,
                    oyuncu_b_id = s.Sag.Id,
                    oyuncu_a_bonservis = s.Sol.ToplamBonservis,
                    oyuncu_b_bonservis = s.Sag.ToplamBonservis,
                    oyuncu_a_foto = s.Sol.FotoUrl,
                    oyuncu_b_foto = s.Sag.FotoUrl
                }).ToList()
            };

            await _supabaseClient.From<GunlukOyun>().Insert(yeniOyun);
            Console.WriteLine($"Başarılı: Bonservis için {tarih:yyyy-MM-dd} tarihli 5 soruluk set eklendi.");
            BonservisSorulariniYaz(sorular);
        }

        // Veritabanına yazmadan bir Bonservis soru seti seçip ekrana basar:
        // dotnet run -- --bonservis-onizleme
        public async Task BonservisOnizleme()
        {
            var sorular = await BonservisSorulariniSec(ayrintili: true);
            if (sorular == null) return;

            Console.WriteLine("Önizleme (veritabanına yazılmadı):");
            BonservisSorulariniYaz(sorular);
        }

        private static void BonservisSorulariniYaz(List<BonservisSoruSecici.BonservisSorusu> sorular)
        {
            for (int i = 0; i < sorular.Count; i++)
            {
                var s = sorular[i];
                Console.WriteLine($"   {i + 1}. {s.Sol.Isim} ({Milyon(s.Sol.ToplamBonservis)}) x {s.Sag.Isim} ({Milyon(s.Sag.ToplamBonservis)}) -> doğru: {s.Dogru.Isim}");
            }
        }

        private static string Milyon(long euro) => $"{euro / 1_000_000.0:0.#} M€";

        // Listedeki kulüplerde güncel sezonda oynayan, toplam bonservisi yeterli oyuncuları çeker,
        // seçimi BonservisSoruSecici'ye bırakır
        private async Task<List<BonservisSoruSecici.BonservisSorusu>?> BonservisSorulariniSec(bool ayrintili = false)
        {
            var kulupler = (await _supabaseClient.From<Kulup>().Select("id, isim, lig, transfermarkt_id").Get()).Models;
            KulupListesiniKontrolEt(BonservisSoruSecici.Kulupler, "Bonservis", kulupler, ayrintili);

            var kulupIdleri = KesisimSoruSecici.ListedekiKulupIdleri(BonservisSoruSecici.Kulupler, kulupler);
            var kariyer = await KulupKariyerleri(kulupIdleri);
            if (kariyer.Count == 0)
            {
                Console.WriteLine("Uyarı: Bonservis kulüpleri için kariyer verisi yok.");
                return null;
            }

            // Güncel sezon: bu kulüpler için veritabanındaki en son sezon
            int guncelSezon = kariyer.Max(k => k.BitisYili ?? 0);
            var guncelOyuncular = kariyer.Where(k => k.BitisYili == guncelSezon).Select(k => k.OyuncuId).ToHashSet();

            var adaylar = (await PahaliOyuncular())
                .Where(o => guncelOyuncular.Contains(o.Id))
                .Select(o => new BonservisSoruSecici.Aday(o.Id, o.Isim, o.ToplamBonservis, o.FotoUrl))
                .ToList();

            Console.WriteLine($"Bonservis havuzu: {guncelSezon}/{guncelSezon + 1} sezonunda {guncelOyuncular.Count} oyuncu, " +
                              $"toplam bonservisi {Milyon(BonservisSoruSecici.MinToplamBonservis)} üstünde olan {adaylar.Count} oyuncu.");

            var sorular = new BonservisSoruSecici().Sec(adaylar);
            if (sorular == null)
            {
                Console.WriteLine("Uyarı: Bonservis için kurallara uyan 5 soruluk zincir kurulamadı.");
            }
            return sorular;
        }

        // Verilen kulüplerin kariyer kayıtları (oyuncu, kulüp, son sezon)
        private async Task<List<KariyerGecmisi>> KulupKariyerleri(HashSet<string> kulupIdleri)
        {
            var tumu = new List<KariyerGecmisi>();
            var filtre = kulupIdleri.Cast<object>().ToList();

            for (int bas = 0; ; bas += SayfaBoyutu)
            {
                var sayfa = await _supabaseClient.From<KariyerGecmisi>()
                    .Select("oyuncu_id, kulup_id, bitis_yili")
                    .Filter("kulup_id", Operator.In, filtre)
                    .Order("oyuncu_id", Ordering.Ascending)
                    .Order("kulup_id", Ordering.Ascending)
                    .Range(bas, bas + SayfaBoyutu - 1)
                    .Get();

                tumu.AddRange(sayfa.Models);
                if (sayfa.Models.Count < SayfaBoyutu) break;
            }

            return tumu;
        }

        // Toplam bonservisi alt sınırın üzerindeki tüm oyuncular
        private async Task<List<Oyuncu>> PahaliOyuncular()
        {
            var tumu = new List<Oyuncu>();

            for (int bas = 0; ; bas += SayfaBoyutu)
            {
                var sayfa = await _supabaseClient.From<Oyuncu>()
                    .Select("id, isim, toplam_bonservis, foto_url")
                    .Filter("toplam_bonservis", Operator.GreaterThan, BonservisSoruSecici.MinToplamBonservis.ToString())
                    .Order("id", Ordering.Ascending)
                    .Range(bas, bas + SayfaBoyutu - 1)
                    .Get();

                tumu.AddRange(sayfa.Models);
                if (sayfa.Models.Count < SayfaBoyutu) break;
            }

            return tumu;
        }

        private async Task<List<KariyerGecmisi>> TumKariyerGecmisi()
        {
            var tumu = new List<KariyerGecmisi>();

            // Sayfalar arasında satır kaymasın diye benzersiz (oyuncu_id, kulup_id) sırasıyla okunur
            for (int bas = 0; ; bas += SayfaBoyutu)
            {
                var sayfa = await _supabaseClient.From<KariyerGecmisi>()
                    .Select("oyuncu_id, kulup_id")
                    .Order("oyuncu_id", Ordering.Ascending)
                    .Order("kulup_id", Ordering.Ascending)
                    .Range(bas, bas + SayfaBoyutu - 1)
                    .Get();

                tumu.AddRange(sayfa.Models);
                if (sayfa.Models.Count < SayfaBoyutu) break;
            }

            return tumu;
        }

        // Listedeki kulüplerin veritabanında olup olmadığını kontrol eder; ayrıntılı modda eşleşmeleri listeler
        private static void KulupListesiniKontrolEt(IReadOnlyDictionary<string, string> liste, string listeAdi, List<Kulup> kulupler, bool ayrintili)
        {
            var bulunanlar = kulupler.Where(k => liste.ContainsKey(k.TransfermarktId)).ToList();

            var bulunamayanlar = liste.Keys.Except(bulunanlar.Select(k => k.TransfermarktId)).Select(id => liste[id]).ToList();
            if (bulunamayanlar.Count > 0)
            {
                Console.WriteLine($"Uyarı: Veritabanında bulunamayan {listeAdi} kulüpler: {string.Join(", ", bulunamayanlar)}");
            }

            if (ayrintili)
            {
                // Listedeki ID'lerin doğru kulübe denk geldiğini gözle kontrol etmek için
                Console.WriteLine($"{char.ToUpper(listeAdi[0])}{listeAdi[1..]} kulüpler (Transfermarkt ID -> veritabanındaki isim):");
                foreach (var kulup in bulunanlar.OrderBy(k => k.Lig).ThenBy(k => k.Isim))
                {
                    Console.WriteLine($"   {kulup.TransfermarktId,-6} {liste[kulup.TransfermarktId],-20} -> {kulup.Isim} ({kulup.Lig})");
                }
            }
        }
    }
}
