using System;
using System.Collections.Generic;
using System.Linq;

namespace ScoutIQ.API.Oyunlar
{
    // Bingo oyununun bir modu için kartı ve oyuncu destesini seçer. Veritabanına dokunmaz: kategorileri (her biri
    // kendisine uyan oyuncularla) ve oyuncu kademelerini parametre olarak alır, böylece kurallar gerçek veri olmadan test edilebilir.
    //
    // Kart 4x4'tür: 6 kulüp, 4 milli takım, 2 lig ve 4 başarı kategorisi. Deste 20 oyuncudur; oyuncular sırayla gelir,
    // kullanıcı her oyuncuyu uyduğu kutuya koyar ya da pas geçer. Destedeki oyuncuların kademeleri modun dağılımına uyar
    // (ZorlukDagilimi): kolay 20 ünlü, orta 10 ünlü + 10 bilinen, zor 8 ünlü + 6 bilinen + 6 diğer.
    // Kart her zaman doldurulabilir: her kutuya desteden ayrı bir oyuncu uyar. Kalan 4 oyuncu da en az bir kutuya uyar.
    // Oyun kuralları (sıra, yanlış kutu, pas, süre) sunucuda, 020_bingo.sql'de.
    public class BingoSoruSecici
    {
        public const int Boyut = 4;
        public const int HucreSayisi = Boyut * Boyut;
        public const int DesteBoyutu = 20;

        public enum KategoriTipi { Kulup, Milli, Lig, Basari }

        // Karttaki kategori sayıları, toplamı 16
        public static readonly IReadOnlyDictionary<KategoriTipi, int> KartDagilimi = new Dictionary<KategoriTipi, int>
        {
            [KategoriTipi.Kulup] = 6,
            [KategoriTipi.Milli] = 4,
            [KategoriTipi.Lig] = 2,
            [KategoriTipi.Basari] = 4,
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

        // Deste: oyuncu ID'leri, geliş sırasıyla. Eslesmeler[i]: destedeki i. oyuncunun uyduğu kutular (0-15).
        public record BingoKarti(List<Kategori> Hucreler, List<string> Deste, List<int[]> Eslesmeler);

        // Arama deneme üst sınırı: veri yetersizse aramayı sonsuza kadar sürdürmesin
        private const int MaxDeneme = 500;

        private readonly Random _random;

        public BingoSoruSecici(Random? random = null)
        {
            _random = random ?? new Random();
        }

        // Kurallara uyan bir kart ya da bulunamazsa null
        public BingoKarti? Sec(Zorluk zorluk, IEnumerable<Aday> adayListesi, IReadOnlyDictionary<string, Kademe> kademeler)
        {
            // Sıralı tutulur ki aynı tohumla (seed) aynı kart çıksın. Havuzdan hiç oyuncusu olmayan kategori kullanılamaz.
            var adaylar = adayListesi
                .Where(a => a.Oynayanlar.Any(kademeler.ContainsKey))
                .OrderBy(a => a.Kategori.Tip).ThenBy(a => a.Kategori.Anahtar, StringComparer.Ordinal)
                .ToList();
            var tipler = KartDagilimi.ToDictionary(k => k.Key, k => adaylar.Where(a => a.Kategori.Tip == k.Key).ToList());
            if (KartDagilimi.Any(k => tipler[k.Key].Count < k.Value)) return null;

            // Her kategorinin kademeye göre oyuncuları, sıralı
            var kademeOyunculari = adaylar.ToDictionary(
                a => a,
                a => Enum.GetValues<Kademe>().ToDictionary(
                    k => k,
                    k => a.Oynayanlar.Where(o => kademeler.TryGetValue(o, out var ok) && ok == k).OrderBy(o => o, StringComparer.Ordinal).ToList()));

            var kademeSirasi = ZorlukDagilimi.Dagit(zorluk, DesteBoyutu).SelectMany(d => Enumerable.Repeat(d.Key, d.Value)).ToList();

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
