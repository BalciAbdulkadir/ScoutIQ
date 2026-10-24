using System;
using System.Collections.Generic;
using System.Linq;

namespace ScoutIQ.API.Oyunlar
{
    // Bonservis oyununun 5 sorusunu seçer. Veritabanına dokunmaz: aday oyuncuları parametre olarak alır,
    // böylece kurallar gerçek veri olmadan test edilebilir.
    //
    // Her soruda iki oyuncu çıkar, toplam bonservisi fazla olan doğru cevaptır. Doğru cevap olan oyuncu
    // sonraki soruda ekranda kalır, diğerinin yerine yeni bir oyuncu gelir. Bu yüzden 5 soru,
    // 6 farklı oyuncudan oluşan bir zincirdir. Yanlış cevapta oyun biter (bu kural mobil tarafta).
    public class BonservisSoruSecici
    {
        public const int SoruSayisi = 5;

        // Sadece toplam bonservisi bu tutarın üzerindeki oyuncular soru olabilir (Euro)
        public const long MinToplamBonservis = 5_000_000;

        // Eşleşen iki oyuncunun toplam bonservisleri arasında en fazla bu kadar fark olur (Euro).
        // Eşit toplamlı iki oyuncu da eşleşmez: doğru cevap belirsiz olur.
        public const long MaxFark = 30_000_000;

        // Soruda sadece güncel sezonda bu kulüplerde oynayan oyuncular çıkar. Transfermarkt ID'si ile eşleştirilir.
        public static readonly IReadOnlyDictionary<string, string> Kulupler = new Dictionary<string, string>
        {
            // Türkiye
            ["449"] = "Trabzonspor", ["141"] = "Galatasaray", ["36"] = "Fenerbahçe", ["114"] = "Beşiktaş",
            // İngiltere
            ["31"] = "Liverpool", ["631"] = "Chelsea", ["405"] = "Aston Villa", ["873"] = "Crystal Palace",
            ["281"] = "Manchester City", ["985"] = "Manchester United", ["148"] = "Tottenham", ["11"] = "Arsenal",
            // İtalya
            ["506"] = "Juventus", ["46"] = "Inter", ["5"] = "Milan", ["6195"] = "Napoli", ["12"] = "Roma",
            // Fransa
            ["583"] = "PSG", ["162"] = "Monaco", ["244"] = "Marsilya", ["1041"] = "Lyon",
            // Almanya
            ["27"] = "Bayern Münih", ["16"] = "Borussia Dortmund", ["15"] = "Leverkusen", ["23826"] = "RB Leipzig",
            // İspanya
            ["131"] = "Barcelona", ["418"] = "Real Madrid", ["13"] = "Atlético Madrid", ["621"] = "Athletic Bilbao",
        };

        public record Aday(string Id, string Isim, long ToplamBonservis);

        // Sol ve Sag ekrandaki yerlerdir. Kalan oyuncu yerini korur, yeni oyuncu kaybedenin yerine gelir.
        public record BonservisSorusu(Aday Sol, Aday Sag)
        {
            public Aday Dogru => Sol.ToplamBonservis > Sag.ToplamBonservis ? Sol : Sag;
        }

        // Zincir aramasının üst sınırı: havuzda uygun zincir yoksa aramayı sonsuza kadar sürdürmesin
        private const int MaxAdim = 200_000;

        private readonly Random _random;
        private int _adim;

        public BonservisSoruSecici(Random? random = null)
        {
            _random = random ?? new Random();
        }

        public static bool Eslesebilir(Aday a, Aday b)
        {
            long fark = Math.Abs(a.ToplamBonservis - b.ToplamBonservis);
            return fark > 0 && fark <= MaxFark;
        }

        // 5 soruluk zinciri döndürür, kurallara uyan zincir kurulamıyorsa null
        public List<BonservisSorusu>? Sec(IEnumerable<Aday> adaylar)
        {
            // Sıralı alınıp sonra karıştırılır ki aynı tohumla (seed) aynı sonuç çıksın
            var havuz = adaylar
                .Where(a => a.ToplamBonservis > MinToplamBonservis)
                .GroupBy(a => a.Id)
                .Select(g => g.First())
                .OrderBy(a => a.Id, StringComparer.Ordinal)
                .ToList();
            Karistir(havuz);

            _adim = 0;
            var kullanilan = new HashSet<string>();
            var zincir = new List<Aday>();

            // Zincir çıkmaza girerse (kalan oyuncunun 30 milyon aralığında kullanılmamış eşi kalmazsa)
            // geri dönülüp başka oyuncu denenir
            foreach (var ilk in havuz)
            {
                kullanilan.Add(ilk.Id);
                zincir.Add(ilk);
                if (ZinciriTamamla(havuz, kullanilan, zincir, ilk)) return SorulariKur(zincir);
                zincir.RemoveAt(zincir.Count - 1);
                kullanilan.Remove(ilk.Id);

                if (_adim > MaxAdim) break;
            }

            return null;
        }

        // zincir: [ilk oyuncu, 1. sorunun yeni oyuncusu, 2. sorunun yeni oyuncusu, ...]
        private bool ZinciriTamamla(List<Aday> havuz, HashSet<string> kullanilan, List<Aday> zincir, Aday kalan)
        {
            if (zincir.Count == SoruSayisi + 1) return true;

            foreach (var yeni in havuz)
            {
                if (++_adim > MaxAdim) return false;
                if (kullanilan.Contains(yeni.Id) || !Eslesebilir(kalan, yeni)) continue;

                kullanilan.Add(yeni.Id);
                zincir.Add(yeni);
                var sonrakiKalan = yeni.ToplamBonservis > kalan.ToplamBonservis ? yeni : kalan;
                if (ZinciriTamamla(havuz, kullanilan, zincir, sonrakiKalan)) return true;
                zincir.RemoveAt(zincir.Count - 1);
                kullanilan.Remove(yeni.Id);
            }

            return false;
        }

        private List<BonservisSorusu> SorulariKur(List<Aday> zincir)
        {
            var sorular = new List<BonservisSorusu>();

            // İlk soruda hangi oyuncunun solda görüneceği rastgele
            var soru = _random.Next(2) == 0
                ? new BonservisSorusu(zincir[0], zincir[1])
                : new BonservisSorusu(zincir[1], zincir[0]);
            sorular.Add(soru);

            for (int i = 2; i < zincir.Count; i++)
            {
                var kalanSolda = soru.Dogru == soru.Sol;
                soru = kalanSolda
                    ? new BonservisSorusu(soru.Sol, zincir[i])
                    : new BonservisSorusu(zincir[i], soru.Sag);
                sorular.Add(soru);
            }

            return sorular;
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
