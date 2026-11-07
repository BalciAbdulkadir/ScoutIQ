using System;
using System.Collections.Generic;
using System.Linq;
using ScoutIQ.API.Models;

namespace ScoutIQ.API.Oyunlar
{
    // 3x3 Izgara oyununun tahtasını seçer. Veritabanına dokunmaz: kulüpleri, kariyerleri ve oyuncu kademelerini
    // parametre olarak alır, böylece kurallar gerçek veri olmadan test edilebilir.
    //
    // 3 satır ve 3 sütun başlığı vardır; her hücrenin cevabı, satırdaki ve sütundaki başlığın ikisinde de oynamış bir oyuncudur.
    // Kolay: sadece kulüpler. Orta: kulüpler + çok bilinen milli takımlardan 1-2 tanesi.
    // Zor: kulüpler + diğer milli takımlardan 1-2 tanesi.
    // Hücrenin kademesi, cevapları arasındaki en bilinen oyuncunun kademesidir. 9 hücrenin kademeleri modun dağılımına
    // tam uyar (ZorlukDagilimi): kolay 9 ünlü, orta 5 ünlü + 4 bilinen, zor 4 ünlü + 3 bilinen + 2 diğer hücre.
    // Milli takımlar hep aynı eksende olur: "Fransa x İspanya" gibi neredeyse çözümsüz hücre oluşmaz.
    // Oyun kuralları (oyuncu tekrarı yok, hücreye yerleştirme, süre) sunucuda, 011_izgara.sql ve 013_izgara_sure.sql'de.
    public class IzgaraSoruSecici
    {
        public const int Boyut = 3;

        // Her hücrede en az bu kadar doğru cevap olur
        public const int MinCevap = 3;

        public const int MaxMilliTakim = 2;

        // Başlık olabilecek kulüpler: Kesişim'in kulüpleri. Transfermarkt ID'si ile eşleştirilir.
        public static readonly IReadOnlyDictionary<string, string> Kulupler = KesisimSoruSecici.Kulupler;

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

        // CevapSayilari ve HucreKademeleri satır satır: hücre = satır * 3 + sütun
        public record Izgara(List<Baslik> Satirlar, List<Baslik> Sutunlar, int[] CevapSayilari, Kademe[] HucreKademeleri);

        // Arama deneme üst sınırı: veri yetersizse aramayı sonsuza kadar sürdürmesin.
        // Gerçek veride zor tahtaların yaklaşık binde 3'ü dağılıma tam uyuyor; bu sınırla neredeyse her gün tahta bulunur.
        private const int MaxDeneme = 20000;

        // Başlık: cevap olarak kabul edilen bütün oyuncular ve kademe hesabına giren, maça çıkmış oyuncular
        private record Aday(Baslik Baslik, HashSet<string> Oyuncular, HashSet<string> Oynayanlar);

        private readonly Random _random;

        // İki başlığın ortak oyuncu sayısı ve kademesi, aramada tekrar tekrar sorulduğu için bir kez hesaplanır
        private readonly Dictionary<(int, int), (int Sayi, Kademe? Kademe)> _hucreler = new();
        private List<Aday> _adaylar = new();
        private IReadOnlyDictionary<string, Kademe> _kademeler = new Dictionary<string, Kademe>();

        public IzgaraSoruSecici(Random? random = null)
        {
            _random = random ?? new Random();
        }

        // Kurallara uyan bir tahta ya da bulunamazsa null
        public Izgara? Sec(Zorluk zorluk, IEnumerable<Kulup> kulupler, IEnumerable<KariyerGecmisi> kariyer,
            IEnumerable<MilliTakimKariyeri> milliKariyer, IReadOnlyDictionary<string, Kademe> kademeler)
        {
            var kayitlar = kariyer.ToList();
            var kulupOyunculari = kayitlar.GroupBy(k => k.KulupId).ToDictionary(g => g.Key, g => g.Select(k => k.OyuncuId).ToHashSet());
            var kulupOynayanlari = kayitlar.Where(k => k.Oynadi).GroupBy(k => k.KulupId)
                .ToDictionary(g => g.Key, g => g.Select(k => k.OyuncuId).ToHashSet());

            // Sıralı tutulur ki aynı tohumla (seed) aynı tahta çıksın
            var kulupAdaylari = kulupler
                .Where(k => Kulupler.ContainsKey(k.TransfermarktId) && kulupOyunculari.ContainsKey(k.Id))
                .OrderBy(k => k.TransfermarktId, StringComparer.Ordinal)
                .Select(k => new Aday(
                    new Baslik(BaslikTipi.Kulup, k.Id, k.TransfermarktId, Kulupler[k.TransfermarktId], k.LogoUrl),
                    kulupOyunculari[k.Id],
                    kulupOynayanlari.GetValueOrDefault(k.Id, new HashSet<string>())))
                .ToList();

            // Milli takım kariyerinde sadece maça çıkılan takımlar vardır
            var milliAdaylari = zorluk == Zorluk.Kolay
                ? new List<Aday>()
                : milliKariyer
                    .GroupBy(m => m.MilliTakimTmId)
                    .Where(g => (zorluk == Zorluk.Orta) == OrtaMilliTakimlar.ContainsKey(g.Key))
                    .OrderBy(g => g.Key, StringComparer.Ordinal)
                    .Select(g =>
                    {
                        var oyuncular = g.Select(m => m.OyuncuId).ToHashSet();
                        var isim = OrtaMilliTakimlar.TryGetValue(g.Key, out var turkce) ? turkce : g.First().MilliTakimIsim;
                        return new Aday(new Baslik(BaslikTipi.Milli, null, g.Key, isim), oyuncular, oyuncular);
                    })
                    .ToList();

            _adaylar = kulupAdaylari.Concat(milliAdaylari).ToList();
            _kademeler = kademeler;
            _hucreler.Clear();

            var kulupIndisleri = Enumerable.Range(0, kulupAdaylari.Count).ToList();
            var milliIndisleri = Enumerable.Range(kulupAdaylari.Count, milliAdaylari.Count).ToList();
            var hedef = ZorlukDagilimi.Dagit(zorluk, Boyut * Boyut);

            for (int deneme = 0; deneme < MaxDeneme; deneme++)
            {
                // Kolayda milli takım yok; orta ve zorda 1 ya da 2
                int milliSayisi = zorluk == Zorluk.Kolay ? 0 : _random.Next(1, MaxMilliTakim + 1);
                var izgara = Dene(kulupIndisleri, milliIndisleri, milliSayisi, hedef);
                if (izgara != null) return izgara;
            }

            return null;
        }

        // Rastgele 3 kulüp satıra konur; sütunlar, üç satırla da yeterli ortak oyuncusu olan başlıklardan seçilir.
        // Milli takımlar sütunlara konur, sonra eksenler rastgele yer değiştirir. Hücre kademeleri hedefe uymazsa null.
        private Izgara? Dene(List<int> kulupler, List<int> milliler, int milliSayisi, Dictionary<Kademe, int> hedef)
        {
            if (kulupler.Count < 2 * Boyut - milliSayisi || milliler.Count < milliSayisi) return null;

            var satirlar = RastgeleSec(kulupler, Boyut);
            bool Uygun(int aday) => satirlar.All(s => Hucre(s, aday).Sayi >= MinCevap);

            var milliAdaylar = milliler.Where(Uygun).ToList();
            var kulupAdaylar = kulupler.Where(k => !satirlar.Contains(k)).Where(Uygun).ToList();
            if (milliAdaylar.Count < milliSayisi || kulupAdaylar.Count < Boyut - milliSayisi) return null;

            var sutunlar = RastgeleSec(kulupAdaylar, Boyut - milliSayisi).Concat(RastgeleSec(milliAdaylar, milliSayisi)).ToList();

            var kademeSayilari = new Dictionary<Kademe, int>();
            foreach (var s in satirlar)
            {
                foreach (var t in sutunlar)
                {
                    var kademe = Hucre(s, t).Kademe;
                    if (kademe == null) return null;
                    kademeSayilari[kademe.Value] = kademeSayilari.GetValueOrDefault(kademe.Value) + 1;
                }
            }
            if (!hedef.Where(h => h.Value > 0).OrderBy(h => h.Key).SequenceEqual(kademeSayilari.OrderBy(k => k.Key))) return null;

            Karistir(sutunlar);
            if (_random.Next(2) == 0)
            {
                (satirlar, sutunlar) = (sutunlar, satirlar);
            }

            var cevapSayilari = new int[Boyut * Boyut];
            var hucreKademeleri = new Kademe[Boyut * Boyut];
            for (int s = 0; s < Boyut; s++)
            {
                for (int t = 0; t < Boyut; t++)
                {
                    var hucre = Hucre(satirlar[s], sutunlar[t]);
                    cevapSayilari[s * Boyut + t] = hucre.Sayi;
                    hucreKademeleri[s * Boyut + t] = hucre.Kademe!.Value;
                }
            }

            return new Izgara(
                satirlar.Select(i => _adaylar[i].Baslik).ToList(),
                sutunlar.Select(i => _adaylar[i].Baslik).ToList(),
                cevapSayilari,
                hucreKademeleri);
        }

        private (int Sayi, Kademe? Kademe) Hucre(int a, int b)
        {
            var anahtar = a < b ? (a, b) : (b, a);
            if (_hucreler.TryGetValue(anahtar, out var hucre)) return hucre;

            var (x, y) = (_adaylar[a], _adaylar[b]);
            var (kucuk, buyuk) = x.Oyuncular.Count <= y.Oyuncular.Count ? (x.Oyuncular, y.Oyuncular) : (y.Oyuncular, x.Oyuncular);
            int sayi = kucuk.Count(buyuk.Contains);
            var kademe = sayi == 0 ? null : ZorlukDagilimi.EnBilinen(x.Oynayanlar.Where(y.Oynayanlar.Contains), _kademeler);

            return _hucreler[anahtar] = (sayi, kademe);
        }

        private List<T> RastgeleSec<T>(List<T> liste, int adet)
        {
            var kopya = liste.ToList();
            Karistir(kopya);
            return kopya.Take(adet).ToList();
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
