using Coravel.Invocable;
using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Supabase;
using ScoutIQ.API.Models;
using System.Linq;
using static Supabase.Postgrest.Constants;

namespace ScoutIQ.API.Jobs
{
    public class DailyQuestionJob : IInvocable
    {
        // Oyun günleri Türkiye saatine göre başlar ve biter
        public static readonly TimeZoneInfo TurkiyeSaatDilimi = TimeZoneInfo.FindSystemTimeZoneById("Europe/Istanbul");

        public enum Zorluk { Kolay, Orta, Zor }

        // Kesişim soruları kolaydan zora sıralanır: 2 kolay, 2 orta-zor, 1 zor
        private static readonly Zorluk[] KesisimSoruSirasi = { Zorluk.Kolay, Zorluk.Kolay, Zorluk.Orta, Zorluk.Orta, Zorluk.Zor };

        // Kolay sorularda iki kulüp de bu listeden olur. Transfermarkt ID'si ile eşleştirilir, isimler değişebilir.
        private static readonly Dictionary<string, string> BuyukKulupler = new()
        {
            // Türkiye: 3 büyükler
            ["141"] = "Galatasaray", ["36"] = "Fenerbahçe", ["114"] = "Beşiktaş",
            // İngiltere: Big Six
            ["281"] = "Manchester City", ["985"] = "Manchester United", ["31"] = "Liverpool",
            ["11"] = "Arsenal", ["631"] = "Chelsea", ["148"] = "Tottenham",
            // İspanya
            ["418"] = "Real Madrid", ["131"] = "Barcelona", ["13"] = "Atlético Madrid",
            // İtalya
            ["506"] = "Juventus", ["46"] = "Inter", ["5"] = "Milan",
            // Almanya
            ["27"] = "Bayern Münih", ["16"] = "Borussia Dortmund",
            // Fransa
            ["583"] = "PSG",
        };

        // Orta-zor sorularda en az bir kulüp bu listeden olur, diğeri bu listeden ya da büyük kulüplerden.
        private static readonly Dictionary<string, string> BasAltiKulupler = new()
        {
            // İngiltere
            ["762"] = "Newcastle", ["405"] = "Aston Villa", ["379"] = "West Ham",
            // İspanya
            ["368"] = "Sevilla", ["1050"] = "Villarreal", ["681"] = "Real Sociedad",
            ["621"] = "Athletic Bilbao", ["150"] = "Real Betis", ["1049"] = "Valencia",
            // İtalya
            ["6195"] = "Napoli", ["12"] = "Roma", ["398"] = "Lazio", ["800"] = "Atalanta", ["430"] = "Fiorentina",
            // Almanya
            ["15"] = "Leverkusen", ["23826"] = "RB Leipzig", ["24"] = "Eintracht Frankfurt", ["79"] = "Stuttgart",
            // Fransa
            ["244"] = "Marsilya", ["162"] = "Monaco", ["1041"] = "Lyon", ["1082"] = "Lille",
            // Türkiye
            ["449"] = "Trabzonspor", ["6890"] = "Başakşehir",
        };

        // Kolay: iki kulüp de büyük. Orta-zor: baş altı kulüp içerir, farklı liglerden, en az 2 ortak oyuncu.
        // Zor: geri kalan farklı lig çiftleri. Aynı ligden çiftler (büyükler hariç) sorulmaz:
        // transferler çoğunlukla lig içinde olduğu için aksi halde sorular hep aynı ligden çıkıyor.
        private const int OrtaMinOrtakOyuncu = 2;

        private const int SayfaBoyutu = 1000; // Supabase tek istekte en fazla 1000 satır döndürür

        public record KulupCifti(Kulup KulupA, Kulup KulupB, int OrtakOyuncuSayisi);
        public record KesisimSorusu(KulupCifti Cift, Zorluk Zorluk);

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

        // Tüm kulüp çiftlerinin ortak oyuncu sayısını hesaplar ve her zorluktan rastgele çift seçer.
        // Sadece en az bir ortak oyuncusu olan çiftler soru olabilir. Bir oyunda aynı kulüp iki kez çıkmaz.
        public async Task<List<KesisimSorusu>?> KesisimSorulariniSec(bool ayrintili = false)
        {
            var kuluplerResponse = await _supabaseClient.From<Kulup>().Select("id, isim, lig, transfermarkt_id").Get();
            var kulupler = kuluplerResponse.Models.ToDictionary(k => k.Id);

            if (kulupler.Count < 2)
            {
                Console.WriteLine("Uyarı: Kesişim için veritabanında yeterli kulüp yok.");
                return null;
            }

            var buyukKulupIdleri = ListedekiKulupler(BuyukKulupler, "büyük", kulupler.Values, ayrintili);
            var basAltiKulupIdleri = ListedekiKulupler(BasAltiKulupler, "baş altı", kulupler.Values, ayrintili);

            var kulupOyunculari = (await TumKariyerGecmisi())
                .Where(k => kulupler.ContainsKey(k.KulupId))
                .GroupBy(k => k.KulupId)
                .ToDictionary(g => g.Key, g => g.Select(k => k.OyuncuId).ToHashSet());

            var havuzlar = new Dictionary<Zorluk, List<KulupCifti>>
            {
                [Zorluk.Kolay] = new(),
                [Zorluk.Orta] = new(),
                [Zorluk.Zor] = new()
            };

            var kulupIdleri = kulupOyunculari.Keys.ToList();
            for (int i = 0; i < kulupIdleri.Count; i++)
            {
                for (int j = i + 1; j < kulupIdleri.Count; j++)
                {
                    int ortak = OrtakSayisi(kulupOyunculari[kulupIdleri[i]], kulupOyunculari[kulupIdleri[j]]);
                    if (ortak == 0) continue;

                    var cift = new KulupCifti(kulupler[kulupIdleri[i]], kulupler[kulupIdleri[j]], ortak);
                    var zorluk = ZorlukBelirle(cift, buyukKulupIdleri, basAltiKulupIdleri);
                    if (zorluk != null) havuzlar[zorluk.Value].Add(cift);
                }
            }

            Console.WriteLine($"Kesişim havuzları: {havuzlar[Zorluk.Kolay].Count} kolay, {havuzlar[Zorluk.Orta].Count} orta-zor, {havuzlar[Zorluk.Zor].Count} zor çift.");

            var random = new Random();
            foreach (var havuz in havuzlar.Values)
            {
                Karistir(havuz, random);
            }

            var sorular = new List<KesisimSorusu>();
            var kullanilanKulupler = new HashSet<string>();

            foreach (var istenen in KesisimSoruSirasi)
            {
                KulupCifti? secilen = null;

                // İstenen zorlukta uygun çift kalmadıysa en yakın zorluktan alınır
                foreach (var zorluk in YedekSirasi(istenen))
                {
                    secilen = havuzlar[zorluk].FirstOrDefault(c =>
                        !kullanilanKulupler.Contains(c.KulupA.Id) && !kullanilanKulupler.Contains(c.KulupB.Id));

                    if (secilen != null)
                    {
                        if (zorluk != istenen)
                        {
                            Console.WriteLine($"Uyarı: {istenen} çift kalmadı, yerine {zorluk} çift kullanıldı.");
                        }
                        break;
                    }
                }

                if (secilen == null)
                {
                    Console.WriteLine($"Uyarı: Kesişim için 5 eşleşme bulunamadı. Bulunan: {sorular.Count} (Veritabanında yeterli kariyer verisi yok)");
                    return null;
                }

                kullanilanKulupler.Add(secilen.KulupA.Id);
                kullanilanKulupler.Add(secilen.KulupB.Id);

                // Hangi kulübün solda görüneceği de rastgele olsun
                if (random.Next(2) == 0)
                {
                    secilen = secilen with { KulupA = secilen.KulupB, KulupB = secilen.KulupA };
                }

                sorular.Add(new KesisimSorusu(secilen, istenen));
            }

            return sorular;
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

        private static int OrtakSayisi(HashSet<string> a, HashSet<string> b)
        {
            var (kucuk, buyuk) = a.Count <= b.Count ? (a, b) : (b, a);
            return kucuk.Count(buyuk.Contains);
        }

        // Çiftin hangi zorlukta sorulacağını döndürür, hiç sorulmayacaksa null
        private static Zorluk? ZorlukBelirle(KulupCifti cift, HashSet<string> buyukler, HashSet<string> basAltilar)
        {
            string a = cift.KulupA.Id, b = cift.KulupB.Id;

            if (buyukler.Contains(a) && buyukler.Contains(b)) return Zorluk.Kolay;
            if (cift.KulupA.Lig == cift.KulupB.Lig) return null;

            bool basAltiVar = basAltilar.Contains(a) || basAltilar.Contains(b);
            bool ikisiDeUstSeviye = (buyukler.Contains(a) || basAltilar.Contains(a)) && (buyukler.Contains(b) || basAltilar.Contains(b));
            if (basAltiVar && ikisiDeUstSeviye && cift.OrtakOyuncuSayisi >= OrtaMinOrtakOyuncu) return Zorluk.Orta;

            return Zorluk.Zor;
        }

        // Orta-zor yerine zor çift kullanılmaz: orta-zor soruda en az 2 ortak oyuncu şartı korunur
        private static Zorluk[] YedekSirasi(Zorluk istenen) => istenen switch
        {
            Zorluk.Kolay => new[] { Zorluk.Kolay, Zorluk.Orta },
            Zorluk.Orta => new[] { Zorluk.Orta, Zorluk.Kolay },
            _ => new[] { Zorluk.Zor, Zorluk.Orta, Zorluk.Kolay }
        };

        // Listedeki Transfermarkt ID'lerine denk gelen kulüplerin veritabanı ID'lerini döndürür
        private static HashSet<string> ListedekiKulupler(Dictionary<string, string> liste, string listeAdi, IEnumerable<Kulup> kulupler, bool ayrintili)
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

            return bulunanlar.Select(k => k.Id).ToHashSet();
        }

        private static void Karistir<T>(List<T> liste, Random random)
        {
            for (int i = liste.Count - 1; i > 0; i--)
            {
                int j = random.Next(i + 1);
                (liste[i], liste[j]) = (liste[j], liste[i]);
            }
        }
    }
}
