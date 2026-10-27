using System;
using System.Collections.Generic;
using System.Linq;

namespace ScoutIQ.API.Oyunlar
{
    // Bonservis oyununun 5 sorusunu seçer. Veritabanına dokunmaz: aday oyuncuları parametre olarak alır,
    // böylece kurallar gerçek veri olmadan test edilebilir.
    //
    // Her soruda rastgele iki oyuncu çıkar, toplam bonservisi fazla olan doğru cevaptır.
    // Bir oyunda aynı oyuncu iki kez çıkmaz: 5 soru, 10 farklı oyuncu.
    // Yanlış cevapta oyun biter (bu kural mobil tarafta).
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

        // FotoUrl seçimi etkilemez, sadece soruyla birlikte uygulamaya taşınır
        public record Aday(string Id, string Isim, long ToplamBonservis, string? FotoUrl = null);

        // Sol ve Sag ekrandaki yerlerdir; doğru cevabın hangi tarafta olacağı rastgeledir
        public record BonservisSorusu(Aday Sol, Aday Sag)
        {
            public Aday Dogru => Sol.ToplamBonservis > Sag.ToplamBonservis ? Sol : Sag;
        }

        // Arama adımı üst sınırı: havuzda uygun 5 ikili yoksa aramayı sonsuza kadar sürdürmesin
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

        // 5 soruyu döndürür, kurallara uyan 5 ikili bulunamazsa null
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
            var ikililer = new List<(Aday, Aday)>();
            if (!IkilileriTamamla(havuz, 0, new HashSet<string>(), ikililer)) return null;

            return ikililer
                .Select(i => _random.Next(2) == 0 ? new BonservisSorusu(i.Item1, i.Item2) : new BonservisSorusu(i.Item2, i.Item1))
                .ToList();
        }

        // Karışık sırada gezer, her oyuncuya kurallara uyan kullanılmamış bir eş arar.
        // Bir ikili sonraki soruları imkânsız kılarsa geri dönüp başka eş ya da başka oyuncu dener.
        private bool IkilileriTamamla(List<Aday> havuz, int bas, HashSet<string> kullanilan, List<(Aday, Aday)> ikililer)
        {
            if (ikililer.Count == SoruSayisi) return true;

            for (int i = bas; i < havuz.Count; i++)
            {
                var a = havuz[i];
                if (kullanilan.Contains(a.Id)) continue;

                for (int j = i + 1; j < havuz.Count; j++)
                {
                    if (++_adim > MaxAdim) return false;

                    var b = havuz[j];
                    if (kullanilan.Contains(b.Id) || !Eslesebilir(a, b)) continue;

                    kullanilan.Add(a.Id);
                    kullanilan.Add(b.Id);
                    ikililer.Add((a, b));
                    if (IkilileriTamamla(havuz, i + 1, kullanilan, ikililer)) return true;
                    ikililer.RemoveAt(ikililer.Count - 1);
                    kullanilan.Remove(a.Id);
                    kullanilan.Remove(b.Id);
                }
            }

            return false;
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
