using System;
using System.Collections.Generic;
using System.Linq;

namespace ScoutIQ.API.Oyunlar
{
    // Günün Bingo kartını ve oyuncu destesini seçer. Bingo'nun zorluk modu yoktur, günde tek kart vardır.
    // Veritabanına dokunmaz: kategorileri (her biri kendisine uyan oyuncularla) ve oyuncu kademelerini parametre olarak alır,
    // böylece kurallar gerçek veri olmadan test edilebilir.
    //
    // Kart 4 satır, 3 sütundur (12 kutu): 4 kulüp, 3 milli takım, 2 lig ve 3 başarı kategorisi. Deste 16 oyuncudur;
    // oyuncular sırayla gelir, kullanıcı her oyuncuyu uyduğu kutuya koyar ya da pas geçer. Destede sadece ünlü ve bilinen
    // oyuncular vardır (DesteDagilimi): 8 ünlü, 8 bilinen. Kategoriler de bu oyuncuların kulüplerinden, milli takımlarından,
    // liglerinden ve başarılarından kurulur.
    // Kart her zaman doldurulabilir: her kutuya desteden ayrı bir oyuncu uyar. Kalan 4 oyuncu da en az bir kutuya uyar.
    // Oyun kuralları (sıra, yanlış kutu, pas, süre) sunucuda: 020_bingo.sql ve 021_bingo_tek_mod.sql.
    public class BingoSoruSecici
    {
        public const string OyunTipi = "bingo";
        public const int SatirSayisi = 4;
        public const int SutunSayisi = 3;
        public const int HucreSayisi = SatirSayisi * SutunSayisi;
        public const int DesteBoyutu = 16;

        // Destedeki oyuncuların kademeleri, toplamı DesteBoyutu
        public static readonly IReadOnlyDictionary<Kademe, int> DesteDagilimi = new Dictionary<Kademe, int>
        {
            [Kademe.Unlu] = 8,
            [Kademe.Bilinen] = 8,
        };

        public enum KategoriTipi { Kulup, Milli, Lig, Basari }

        // Karttaki kategori sayıları, toplamı HucreSayisi
        public static readonly IReadOnlyDictionary<KategoriTipi, int> KartDagilimi = new Dictionary<KategoriTipi, int>
        {
            [KategoriTipi.Kulup] = 4,
            [KategoriTipi.Milli] = 3,
            [KategoriTipi.Lig] = 2,
            [KategoriTipi.Basari] = 3,
        };

        // Lig kategorileri: Transfermarkt lig kodu -> ekranda görünen isim
        public static readonly IReadOnlyDictionary<string, string> Ligler = new Dictionary<string, string>
        {
            ["TR1"] = "Süper Lig", ["GB1"] = "Premier Lig", ["ES1"] = "La Liga",
            ["IT1"] = "Serie A", ["L1"] = "Bundesliga", ["FR1"] = "Ligue 1",
        };

        // Başarı kategorileri: anahtar -> (ekranda görünen isim, oyuncu_basarilari'ndaki başlıklar)
        public static readonly IReadOnlyDictionary<string, (string Isim, string[] Basliklar)> Basarilar =
            new Dictionary<string, (string, string[])>
            {
                ["sampiyonlar_ligi"] = ("Şampiyonlar Ligi", new[] { "UEFA Champions League winner", "European Champion Clubs' Cup winner" }),
                ["avrupa_ligi"] = ("UEFA Avrupa Ligi", new[] { "Europa League winner", "Uefa Cup winner" }),
                ["dunya_kupasi"] = ("Dünya Kupası", new[] { "World Cup winner" }),
                ["avrupa_sampiyonasi"] = ("Avrupa Şampiyonası", new[] { "European champion" }),
                ["copa_america"] = ("Copa América", new[] { "Copa América winner" }),
                ["ballon_dor"] = ("Ballon d'Or", new[] { "Winner Ballon d'Or" }),
                ["super_lig_sampiyonu"] = ("Süper Lig şampiyonu", new[] { "Turkish champion" }),
                ["premier_lig_sampiyonu"] = ("Premier Lig şampiyonu", new[] { "English Champion" }),
                ["la_liga_sampiyonu"] = ("La Liga şampiyonu", new[] { "Spanish champion" }),
                ["serie_a_sampiyonu"] = ("Serie A şampiyonu", new[] { "Italian champion" }),
                ["bundesliga_sampiyonu"] = ("Bundesliga şampiyonu", new[] { "German Champion" }),
                ["ligue_1_sampiyonu"] = ("Ligue 1 şampiyonu", new[] { "French champion" }),
            };

        // Anahtar: kulüp ve milli takımda Transfermarkt ID'si, ligde lig kodu, başarıda Basarilar'daki anahtar.
        // KulupId sadece kulüpte doludur. LogoUrl: kulüp logosu, bayrak, lig ya da kupa logosu (Logolar); uygulamaya taşınır.
        public record Kategori(KategoriTipi Tip, string Anahtar, string Isim, string? KulupId = null, string? LogoUrl = null);

        // Oyuncular: kategoriye uyan bütün oyuncular (cevap olarak kabul edilenler).
        // Oynayanlar: kartı kurarken kullanılanlar; kulüp ve ligde sadece gerçekten maça çıkmış oyuncular.
        public record Aday(Kategori Kategori, HashSet<string> Oyuncular, HashSet<string> Oynayanlar);

        // Deste: oyuncu ID'leri, geliş sırasıyla. Eslesmeler[i]: destedeki i. oyuncunun uyduğu kutular (0-11).
        public record BingoKarti(List<Kategori> Hucreler, List<string> Deste, List<int[]> Eslesmeler);

        // Arama deneme üst sınırı: veri yetersizse aramayı sonsuza kadar sürdürmesin
        private const int MaxDeneme = 500;

        private readonly Random _random;

        public BingoSoruSecici(Random? random = null)
        {
            _random = random ?? new Random();
        }

        // Kurallara uyan bir kart ya da bulunamazsa null
        public BingoKarti? Sec(IEnumerable<Aday> adayListesi, IReadOnlyDictionary<string, Kademe> tumKademeler)
        {
            // Sadece ünlü ve bilinen oyuncular: kategoriler de deste de onlardan kurulur
            var kademeler = tumKademeler.Where(k => DesteDagilimi.ContainsKey(k.Value)).ToDictionary(k => k.Key, k => k.Value);

            // Sıralı tutulur ki aynı tohumla (seed) aynı kart çıksın. Ünlü ya da bilinen oyuncusu olmayan kategori kullanılamaz.
            var adaylar = adayListesi
                .Where(a => a.Oynayanlar.Any(kademeler.ContainsKey))
                .OrderBy(a => a.Kategori.Tip).ThenBy(a => a.Kategori.Anahtar, StringComparer.Ordinal)
                .ToList();
            var tipler = KartDagilimi.ToDictionary(k => k.Key, k => adaylar.Where(a => a.Kategori.Tip == k.Key).ToList());
            if (KartDagilimi.Any(k => tipler[k.Key].Count < k.Value)) return null;

            // Her kategorinin kademeye göre oyuncuları, sıralı
            var kademeOyunculari = adaylar.ToDictionary(
                a => a,
                a => DesteDagilimi.Keys.ToDictionary(
                    k => k,
                    k => a.Oynayanlar.Where(o => kademeler.TryGetValue(o, out var ok) && ok == k).OrderBy(o => o, StringComparer.Ordinal).ToList()));

            var kademeSirasi = DesteDagilimi.OrderBy(d => d.Key).SelectMany(d => Enumerable.Repeat(d.Key, d.Value)).ToList();

            for (int deneme = 0; deneme < MaxDeneme; deneme++)
            {
                var kart = Dene(tipler, kademeOyunculari, kademeSirasi);
                if (kart != null) return kart;
            }
            return null;
        }

        private BingoKarti? Dene(
            Dictionary<KategoriTipi, List<Aday>> tipler,
            Dictionary<Aday, Dictionary<Kademe, List<string>>> kademeOyunculari,
            List<Kademe> kademeSirasi)
        {
            var hucreler = KartDagilimi.SelectMany(k => RastgeleSec(tipler[k.Key], k.Value)).ToList();
            Karistir(hucreler);

            var kademeler = kademeSirasi.ToList();
            Karistir(kademeler);

            var kullanilan = new HashSet<string>();
            var deste = new List<string>();

            // Her kutuya, kutunun kademesinden ve kutuya uyan ayrı bir oyuncu: kart böylece her zaman doldurulabilir
            for (int i = 0; i < HucreSayisi; i++)
            {
                var oyuncu = RastgeleOyuncu(kademeOyunculari[hucreler[i]][kademeler[i]], kullanilan);
                if (oyuncu == null) return null;
                kullanilan.Add(oyuncu);
                deste.Add(oyuncu);
            }

            // Kalan oyuncular en az bir kutuya uyar
            for (int i = HucreSayisi; i < DesteBoyutu; i++)
            {
                var uyanlar = hucreler.SelectMany(h => kademeOyunculari[h][kademeler[i]]).Distinct().OrderBy(o => o, StringComparer.Ordinal).ToList();
                var oyuncu = RastgeleOyuncu(uyanlar, kullanilan);
                if (oyuncu == null) return null;
                kullanilan.Add(oyuncu);
                deste.Add(oyuncu);
            }

            Karistir(deste);
            var eslesmeler = deste
                .Select(o => Enumerable.Range(0, HucreSayisi).Where(h => hucreler[h].Oyuncular.Contains(o)).ToArray())
                .ToList();

            return new BingoKarti(hucreler.Select(h => h.Kategori).ToList(), deste, eslesmeler);
        }

        private string? RastgeleOyuncu(List<string> adaylar, HashSet<string> kullanilan)
        {
            var bos = adaylar.Where(o => !kullanilan.Contains(o)).ToList();
            return bos.Count == 0 ? null : bos[_random.Next(bos.Count)];
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
