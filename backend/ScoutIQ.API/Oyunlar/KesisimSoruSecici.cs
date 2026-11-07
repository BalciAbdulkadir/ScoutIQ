using System;
using System.Collections.Generic;
using System.Linq;
using ScoutIQ.API.Models;

namespace ScoutIQ.API.Oyunlar
{
    // Kesişim oyununun bir modu için 5 soruyu seçer. Veritabanına dokunmaz: kulüpleri, kariyer geçmişini ve
    // oyuncu kademelerini parametre olarak alır, böylece kurallar gerçek veri olmadan test edilebilir.
    //
    // Her soru bir kulüp çiftidir. Sorunun kademesi, iki kulüpte de oynamış oyuncular arasındaki en bilinen oyuncunun
    // kademesidir. Modun kademe dağılımı ZorlukDagilimi'ndedir (zor: 2 ünlü, 2 bilinen, 1 diğer soru).
    public class KesisimSoruSecici
    {
        public const int SoruSayisi = 5;

        // Sorulabilecek kulüpler büyük ve baş altı kulüplerdir. Transfermarkt ID'si ile eşleştirilir, isimler değişebilir.
        public static readonly IReadOnlyDictionary<string, string> BuyukKulupler = new Dictionary<string, string>
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

        public static readonly IReadOnlyDictionary<string, string> BasAltiKulupler = new Dictionary<string, string>
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

        public static readonly IReadOnlyDictionary<string, string> Kulupler =
            BuyukKulupler.Concat(BasAltiKulupler).ToDictionary(k => k.Key, k => k.Value);

        // OrtakOyuncuSayisi: iki kulüpte de kaydı olan bütün oyuncular (cevap olarak kabul edilenler).
        // Kademe: bunlardan maça çıkmış ve soru havuzunda olanların en bilineninin kademesi.
        public record KesisimSorusu(Kulup KulupA, Kulup KulupB, int OrtakOyuncuSayisi, Kademe Kademe);

        // Sorular: 5 soru ya da yeterli çift yoksa null. Havuzlar ve uyarılar günlüğe yazılmak içindir.
        public record SecimSonucu(
            List<KesisimSorusu>? Sorular,
            IReadOnlyDictionary<Kademe, int> HavuzBoyutlari,
            List<string> Uyarilar);

        private readonly Random _random;

        public KesisimSoruSecici(Random? random = null)
        {
            _random = random ?? new Random();
        }

        // Listedeki kulüplerden kurulabilen bütün çiftleri kademelerine ayırır, modun dağılımına göre rastgele seçer.
        // Bir oyunda aynı kulüp iki kez çıkmaz. Sorular kolaydan zora sıralanır (önce ünlü).
        public SecimSonucu Sec(Zorluk zorluk, IEnumerable<Kulup> kulupListesi, IEnumerable<KariyerGecmisi> kariyer,
            IReadOnlyDictionary<string, Kademe> kademeler)
        {
            var havuzlar = Havuzlar(kulupListesi, kariyer, kademeler);
            var havuzBoyutlari = havuzlar.ToDictionary(h => h.Key, h => h.Value.Count);

            // Az bulunan kademe önce seçilir ki kulüpleri daha bol olan kademelere kapılmasın
            var istenenler = ZorlukDagilimi.Dagit(zorluk, SoruSayisi)
                .OrderByDescending(d => d.Key)
                .SelectMany(d => Enumerable.Repeat(d.Key, d.Value))
                .ToList();

            // Kulüpler sorular arasında paylaşılamadığı için tek bir karıştırma kurulabilecek seti kaçırabilir:
            // önce dağılıma tam uyan set birkaç karıştırmayla aranır, bulunamazsa yedek kademelere izin verilir.
            foreach (bool yedekli in new[] { false, true })
            {
                for (int deneme = 0; deneme < MaxDeneme; deneme++)
                {
                    var uyarilar = new List<string>();
                    var sorular = Dene(havuzlar, istenenler, yedekli, uyarilar);
                    if (sorular != null) return new SecimSonucu(sorular, havuzBoyutlari, uyarilar);
                }
            }

            return new SecimSonucu(null, havuzBoyutlari, new List<string> { $"Kesişim ({zorluk}) için 5 eşleşme bulunamadı." });
        }

        private const int MaxDeneme = 50;

        private List<KesisimSorusu>? Dene(Dictionary<Kademe, List<KesisimSorusu>> havuzlar, List<Kademe> istenenler, bool yedekli,
            List<string> uyarilar)
        {
            foreach (var havuz in havuzlar.Values)
            {
                Karistir(havuz);
            }

            var sorular = new List<KesisimSorusu>();
            var kullanilanKulupler = new HashSet<string>();

            foreach (var istenen in istenenler)
            {
                KesisimSorusu? secilen = null;

                foreach (var kademe in yedekli ? ZorlukDagilimi.YedekSirasi(istenen) : new[] { istenen })
                {
                    secilen = havuzlar[kademe].FirstOrDefault(c =>
                        !kullanilanKulupler.Contains(c.KulupA.Id) && !kullanilanKulupler.Contains(c.KulupB.Id));

                    if (secilen != null)
                    {
                        if (kademe != istenen)
                        {
                            uyarilar.Add($"{istenen} çift kalmadı, yerine {kademe} çift kullanıldı.");
                        }
                        break;
                    }
                }

                if (secilen == null) return null;

                kullanilanKulupler.Add(secilen.KulupA.Id);
                kullanilanKulupler.Add(secilen.KulupB.Id);

                // Hangi kulübün solda görüneceği de rastgele olsun
                if (_random.Next(2) == 0)
                {
                    secilen = secilen with { KulupA = secilen.KulupB, KulupB = secilen.KulupA };
                }

                sorular.Add(secilen);
            }

            return sorular.OrderBy(s => s.Kademe).ToList();
        }

        // Sorulabilecek bütün çiftler, kademelerine göre. Sıralı gezilir ki aynı tohumla (seed) aynı sonuç çıksın.
        // Aynı ligden iki kulüp (iki büyük kulüp hariç) sorulmaz: transferler çoğunlukla lig içinde olduğu için
        // aksi halde sorular hep aynı ligden çıkıyor.
        private static Dictionary<Kademe, List<KesisimSorusu>> Havuzlar(
            IEnumerable<Kulup> kulupListesi, IEnumerable<KariyerGecmisi> kariyer, IReadOnlyDictionary<string, Kademe> kademeler)
        {
            var kulupler = kulupListesi.Where(k => Kulupler.ContainsKey(k.TransfermarktId)).ToDictionary(k => k.Id);

            var kayitlar = kariyer.Where(k => kulupler.ContainsKey(k.KulupId)).ToList();
            var tumOyuncular = kayitlar.GroupBy(k => k.KulupId).ToDictionary(g => g.Key, g => g.Select(k => k.OyuncuId).ToHashSet());
            var oynayanlar = kayitlar.Where(k => k.Oynadi).GroupBy(k => k.KulupId)
                .ToDictionary(g => g.Key, g => g.Select(k => k.OyuncuId).ToHashSet());

            var havuzlar = Enum.GetValues<Kademe>().ToDictionary(k => k, _ => new List<KesisimSorusu>());

            var kulupIdleri = tumOyuncular.Keys.OrderBy(id => id, StringComparer.Ordinal).ToList();
            for (int i = 0; i < kulupIdleri.Count; i++)
            {
                for (int j = i + 1; j < kulupIdleri.Count; j++)
                {
                    var (a, b) = (kulupler[kulupIdleri[i]], kulupler[kulupIdleri[j]]);
                    if (!Sorulabilir(a, b)) continue;

                    int ortak = tumOyuncular[a.Id].Count(tumOyuncular[b.Id].Contains);
                    if (ortak == 0) continue;

                    var oynayanOrtak = oynayanlar.GetValueOrDefault(a.Id, new HashSet<string>())
                        .Where(oynayanlar.GetValueOrDefault(b.Id, new HashSet<string>()).Contains);
                    var kademe = ZorlukDagilimi.EnBilinen(oynayanOrtak, kademeler);
                    if (kademe != null) havuzlar[kademe.Value].Add(new KesisimSorusu(a, b, ortak, kademe.Value));
                }
            }

            return havuzlar;
        }

        public static bool Sorulabilir(Kulup a, Kulup b) =>
            a.Lig != b.Lig || (BuyukKulupler.ContainsKey(a.TransfermarktId) && BuyukKulupler.ContainsKey(b.TransfermarktId));

        // Listedeki Transfermarkt ID'lerine denk gelen kulüplerin veritabanı ID'lerini döndürür
        public static HashSet<string> ListedekiKulupIdleri(IReadOnlyDictionary<string, string> liste, IEnumerable<Kulup> kulupler)
        {
            return kulupler.Where(k => liste.ContainsKey(k.TransfermarktId)).Select(k => k.Id).ToHashSet();
        }

        private void Karistir<T>(List<T> liste)
        {
            for (int i = liste.Count - 1; i > 0; i--)
            {
                int j = _random.Next(i + 1);
                (liste[i], liste[j]) = (liste[j], liste[i]);
            }
        }
    }
}
