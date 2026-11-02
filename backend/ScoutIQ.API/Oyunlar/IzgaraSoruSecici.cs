using System;
using System.Collections.Generic;
using System.Linq;
using ScoutIQ.API.Models;

namespace ScoutIQ.API.Oyunlar
{
    // 3x3 Izgara oyununun tahtasını seçer. Veritabanına dokunmaz: kulüpleri ve kariyerleri parametre olarak alır,
    // böylece kurallar gerçek veri olmadan test edilebilir.
    //
    // 3 satır ve 3 sütun başlığı vardır; her hücrenin cevabı, satırdaki ve sütundaki başlığın ikisinde de oynamış bir oyuncudur.
    // Kolay: sadece kulüpler. Orta: kulüpler + çok bilinen milli takımlardan 1-2 tanesi.
    // Zor: kulüpler + diğer milli takımlardan 1-2 tanesi.
    // Milli takımlar hep aynı eksende olur: "Fransa x İspanya" gibi neredeyse çözümsüz hücre oluşmaz.
    // Oyun kuralları (9 tahmin hakkı, oyuncu tekrarı yok, hücreye yerleştirme) sunucuda, 011_izgara.sql'de.
    public class IzgaraSoruSecici
    {
        public enum Zorluk { Kolay, Orta, Zor }

        public const int Boyut = 3;

        // Her hücrede en az bu kadar doğru cevap olur
        public const int MinCevap = 3;

        public const int MaxMilliTakim = 2;

        // Başlık olabilecek kulüpler: Kesişim'in büyük ve baş altı kulüpleri. Transfermarkt ID'si ile eşleştirilir.
        public static readonly IReadOnlyDictionary<string, string> Kulupler =
            KesisimSoruSecici.BuyukKulupler.Concat(KesisimSoruSecici.BasAltiKulupler).ToDictionary(k => k.Key, k => k.Value);

        // Orta seviyenin milli takımları. Zor seviye bunların dışındaki milli takımları kullanır.
        // Transfermarkt'taki milli takım ID'si -> ekranda görünen isim
        public static readonly IReadOnlyDictionary<string, string> OrtaMilliTakimlar = new Dictionary<string, string>
        {
            ["3375"] = "İspanya", ["3437"] = "Arjantin", ["3377"] = "Fransa", ["3299"] = "İngiltere",
            ["3439"] = "Brezilya", ["3575"] = "Fas", ["3300"] = "Portekiz", ["3382"] = "Belçika",
            ["3379"] = "Hollanda", ["6303"] = "Meksika", ["3816"] = "Kolombiya", ["3262"] = "Almanya",
            ["3556"] = "Hırvatistan", ["3384"] = "İsviçre", ["3376"] = "İtalya", ["3505"] = "ABD",
            ["3435"] = "Japonya", ["3499"] = "Senegal", ["3440"] = "Norveç", ["3449"] = "Uruguay",
        };

        public enum BaslikTipi { Kulup, Milli }

        // KulupId: kulübün veritabanı ID'si (milli takımda null). LogoUrl sadece uygulamaya taşınır.
        public record Baslik(BaslikTipi Tip, string? KulupId, string TmId, string Isim, string? LogoUrl = null);

        // CevapSayilari satır satır: hücre = satır * 3 + sütun
        public record Izgara(List<Baslik> Satirlar, List<Baslik> Sutunlar, int[] CevapSayilari);

        // Arama deneme üst sınırı: veri yetersizse aramayı sonsuza kadar sürdürmesin
        private const int MaxDeneme = 2000;

        private readonly Random _random;

        public IzgaraSoruSecici(Random? random = null)
        {
            _random = random ?? new Random();
        }

        // Kurallara uyan bir tahta ya da bulunamazsa null
        public Izgara? Sec(Zorluk zorluk, IEnumerable<Kulup> kulupler, IEnumerable<KariyerGecmisi> kariyer, IEnumerable<MilliTakimKariyeri> milliKariyer)
        {
            var kulupOyunculari = kariyer.GroupBy(k => k.KulupId).ToDictionary(g => g.Key, g => g.Select(k => k.OyuncuId).ToHashSet());

            // Sıralı tutulur ki aynı tohumla (seed) aynı tahta çıksın
            var kulupBasliklari = kulupler
                .Where(k => Kulupler.ContainsKey(k.TransfermarktId) && kulupOyunculari.ContainsKey(k.Id))
                .OrderBy(k => k.TransfermarktId, StringComparer.Ordinal)
                .Select(k => (Baslik: new Baslik(BaslikTipi.Kulup, k.Id, k.TransfermarktId, Kulupler[k.TransfermarktId], k.LogoUrl),
                              Oyuncular: kulupOyunculari[k.Id]))
                .ToList();

            var milliBasliklari = zorluk == Zorluk.Kolay
                ? new List<(Baslik Baslik, HashSet<string> Oyuncular)>()
                : milliKariyer
                    .GroupBy(m => m.MilliTakimTmId)
                    .Where(g => (zorluk == Zorluk.Orta) == OrtaMilliTakimlar.ContainsKey(g.Key))
                    .OrderBy(g => g.Key, StringComparer.Ordinal)
                    .Select(g => (Baslik: new Baslik(BaslikTipi.Milli, null, g.Key,
                                      OrtaMilliTakimlar.TryGetValue(g.Key, out var isim) ? isim : g.First().MilliTakimIsim),
                                  Oyuncular: g.Select(m => m.OyuncuId).ToHashSet()))
                    .ToList();

            for (int deneme = 0; deneme < MaxDeneme; deneme++)
            {
                // Kolayda milli takım yok; orta ve zorda 1 ya da 2
                int milliSayisi = zorluk == Zorluk.Kolay ? 0 : _random.Next(1, MaxMilliTakim + 1);
                var izgara = Dene(kulupBasliklari, milliBasliklari, milliSayisi);
                if (izgara != null) return izgara;
            }

            return null;
        }

        // Rastgele 3 kulüp satıra konur; sütunlar, üç satırla da yeterli ortak oyuncusu olan başlıklardan seçilir.
        // Milli takımlar sütunlara konur, sonra eksenler rastgele yer değiştirir.
        private Izgara? Dene(
            List<(Baslik Baslik, HashSet<string> Oyuncular)> kulupler,
            List<(Baslik Baslik, HashSet<string> Oyuncular)> milliler,
            int milliSayisi)
        {
            if (kulupler.Count < 2 * Boyut - milliSayisi || milliler.Count < milliSayisi) return null;

            var satirlar = RastgeleSec(kulupler, Boyut);
            bool Uygun((Baslik Baslik, HashSet<string> Oyuncular) aday) =>
                satirlar.All(s => OrtakSayisi(s.Oyuncular, aday.Oyuncular) >= MinCevap);

            var milliAdaylar = milliler.Where(Uygun).ToList();
            var kulupAdaylar = kulupler.Where(k => !satirlar.Contains(k)).Where(Uygun).ToList();
            if (milliAdaylar.Count < milliSayisi || kulupAdaylar.Count < Boyut - milliSayisi) return null;

            var sutunlar = RastgeleSec(kulupAdaylar, Boyut - milliSayisi).Concat(RastgeleSec(milliAdaylar, milliSayisi)).ToList();
            Karistir(sutunlar);

            if (_random.Next(2) == 0)
            {
                (satirlar, sutunlar) = (sutunlar, satirlar);
            }

            var cevapSayilari = new int[Boyut * Boyut];
            for (int s = 0; s < Boyut; s++)
                for (int t = 0; t < Boyut; t++)
                    cevapSayilari[s * Boyut + t] = OrtakSayisi(satirlar[s].Oyuncular, sutunlar[t].Oyuncular);

            return new Izgara(satirlar.Select(s => s.Baslik).ToList(), sutunlar.Select(s => s.Baslik).ToList(), cevapSayilari);
        }

        private List<T> RastgeleSec<T>(List<T> liste, int adet)
        {
            var kopya = liste.ToList();
            Karistir(kopya);
            return kopya.Take(adet).ToList();
        }

        private static int OrtakSayisi(HashSet<string> a, HashSet<string> b)
        {
            var (kucuk, buyuk) = a.Count <= b.Count ? (a, b) : (b, a);
            return kucuk.Count(buyuk.Contains);
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
