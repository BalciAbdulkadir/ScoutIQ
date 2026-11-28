using System;
using System.Collections.Generic;
using System.Linq;

namespace ScoutIQ.API.Oyunlar
{
    // Günün Bingo kartını ve oyuncu destesini seçer. Bingo'nun zorluk modu yoktur, günde tek kart vardır.
    // Veritabanına dokunmaz: kategorileri (her biri kendisine uyan oyuncularla) ve oyuncu kademelerini parametre olarak alır,
    // böylece kurallar gerçek veri olmadan test edilebilir.
    //
    // Kart 4 satır, 3 sütundur (12 kutu): 4 kulüp, 3 milli takım, 2 lig ve 3 başarı kategorisi. Deste 32 oyuncudur;
    // oyuncular sırayla gelir, kullanıcı her oyuncuyu uyduğu kutuya koyar ya da pas geçer. Pas sınırsızdır: pas geçilen
    // oyuncu destenin sonuna gider ve sırası gelince tekrar gelir.
    // Kulüp kategorileri büyük kulüplerdir; kartta en fazla MaxBasAltiKulup baş altı kulüp olur.
    // Deste ünlü ağırlıklıdır: her kutuya ayrı bir ünlü oyuncu (12; kart böylece her zaman doldurulabilir),
    // en az bir kutuya uyan EkUyanSayisi oyuncu (kutulara dengeli dağıtılır: en az oyuncusu olan kutuya önce) ve hiçbir
    // kutuya uymayan UymayanSayisi oyuncu. Ek oyuncuların çoğu
    // ünlüdür (EkUyanUnluSayisi, UymayanUnluSayisi); kalanı bilinen kademesinin üst sıralarındandır (EkOyuncuSiraSiniri).
    // Kulüp ve lig kategorilerinde oyuncu, kulüpte en az KariyerGecmisi.MinSoruMaci maça çıkmışsa desteye girer.
    // Hepsi karıştırılır.
    // Oyun kuralları (sıra, yanlış kutu, pas, süre) sunucuda: 020_bingo.sql, 021_bingo_tek_mod.sql, 023_bingo_sinirsiz_pas.sql.
    public class BingoSoruSecici
    {
        public const string OyunTipi = "bingo";
        public const int SatirSayisi = 4;
        public const int SutunSayisi = 3;
        public const int HucreSayisi = SatirSayisi * SutunSayisi;
        public const int EkUyanSayisi = 16;
        public const int UymayanSayisi = 4; // Destenin sekizde biri: kutuya uymayan oyuncu az gelir
        public const int DesteBoyutu = HucreSayisi + EkUyanSayisi + UymayanSayisi;

        // Ek oyuncuların ünlü olanları; kalanı bilinen kademesinin üst sıralarındandır. Destede toplam 26 ünlü, 6 bilinen olur.
        // Yeterli ünlü (ya da bilinen) yoksa eksik diğerinden tamamlanır.
        public const int EkUyanUnluSayisi = 11;
        public const int UymayanUnluSayisi = 3;
        public const int MinUnluSayisi = HucreSayisi + EkUyanUnluSayisi + UymayanUnluSayisi;

        // Desteye girebilen bilinen oyuncular: bilinirlik sırasında ilk bu kadar oyuncunun içinde olanlar (ilk 500 ünlüdür)
        public const int EkOyuncuSiraSiniri = 800;

        // Karttaki 4 kulübün en fazla bu kadarı baş altı kulüptür, kalanı büyük kulüptür
        public const int MaxBasAltiKulup = 1;

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
        // BasAlti: baş altı kulüp (kartta sayısı sınırlıdır); diğer kategorilerde false.
        public record Kategori(KategoriTipi Tip, string Anahtar, string Isim, string? KulupId = null, string? LogoUrl = null,
            bool BasAlti = false);

        // Oyuncular: kategoriye uyan bütün oyuncular (cevap olarak kabul edilenler).
        // Oynayanlar: kartı kurarken kullanılanlar; kulüp ve ligde sadece kulüpte yeterince maça çıkmış oyuncular.
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

        // Kurallara uyan bir kart ya da bulunamazsa null.
        // ekBilinenler: desteye ek oyuncu olarak girebilen bilinen oyuncular (bilinirlik sırası EkOyuncuSiraSiniri içinde olanlar).
        public BingoKarti? Sec(IEnumerable<Aday> adayListesi, IReadOnlyDictionary<string, Kademe> kademeler,
            IReadOnlySet<string> ekBilinenler)
        {
            bool Unlu(string o) => kademeler.TryGetValue(o, out var k) && k == Kademe.Unlu;
            bool EkBilinen(string o) => ekBilinenler.Contains(o) && kademeler.TryGetValue(o, out var k) && k == Kademe.Bilinen;

            // Sıralı tutulur ki aynı tohumla (seed) aynı kart çıksın. Ünlü oyuncusu olmayan kategori kullanılamaz.
            var adaylar = adayListesi
                .Where(a => a.Oynayanlar.Any(Unlu))
                .OrderBy(a => a.Kategori.Tip).ThenBy(a => a.Kategori.Anahtar, StringComparer.Ordinal)
                .ToList();
            var tipler = KartDagilimi.ToDictionary(k => k.Key, k => adaylar.Where(a => a.Kategori.Tip == k.Key).ToList());
            if (KartDagilimi.Any(k => tipler[k.Key].Count < k.Value)) return null;
            if (tipler[KategoriTipi.Kulup].Count(a => !a.Kategori.BasAlti) < KartDagilimi[KategoriTipi.Kulup] - MaxBasAltiKulup) return null;

            // Her kategorinin desteye girebilen oyuncuları, sıralı
            List<string> Sirali(IEnumerable<string> oyuncular) => oyuncular.OrderBy(o => o, StringComparer.Ordinal).ToList();
            var unluler = adaylar.ToDictionary(a => a, a => Sirali(a.Oynayanlar.Where(Unlu)));
            var bilinenler = adaylar.ToDictionary(a => a, a => Sirali(a.Oynayanlar.Where(EkBilinen)));

            // Kutuya uymayan oyuncu adayları: bir kategoride yer alan, desteye girebilen bütün oyuncular
            var havuzUnlu = Sirali(unluler.Values.SelectMany(o => o).Distinct());
            var havuzBilinen = Sirali(bilinenler.Values.SelectMany(o => o).Distinct());

            for (int deneme = 0; deneme < MaxDeneme; deneme++)
            {
                var kart = Dene(tipler, unluler, bilinenler, havuzUnlu, havuzBilinen);
                if (kart != null) return kart;
            }
            return null;
        }

        private BingoKarti? Dene(
            Dictionary<KategoriTipi, List<Aday>> tipler,
            Dictionary<Aday, List<string>> unluler,
            Dictionary<Aday, List<string>> bilinenler,
            List<string> havuzUnlu,
            List<string> havuzBilinen)
        {
            var hucreler = KartDagilimi.SelectMany(k => k.Key == KategoriTipi.Kulup
                ? KulupleriSec(tipler[k.Key], k.Value)
                : RastgeleSec(tipler[k.Key], k.Value)).ToList();
            if (hucreler.Count < HucreSayisi) return null;
            Karistir(hucreler);

            var kullanilan = new HashSet<string>();
            var deste = new List<string>();

            // Adaylardan "adet" oyuncu ekler; yetmezse eksik kalan sayıyı döndürür
            int Ekle(List<string> oyuncuAdaylari, int adet)
            {
                for (; adet > 0; adet--)
                {
                    var oyuncu = RastgeleOyuncu(oyuncuAdaylari, kullanilan);
                    if (oyuncu == null) break;
                    kullanilan.Add(oyuncu);
                    deste.Add(oyuncu);
                }
                return adet;
            }

            // Önce ünlülerden istenen kadar, kalanı bilinenlerden alınır; biri yetmezse eksik diğerinden tamamlanır
            bool EkOyuncular(List<string> unluAdaylari, List<string> bilinenAdaylari, int adet, int unluAdedi)
            {
                int eksik = Ekle(unluAdaylari, unluAdedi);
                eksik = Ekle(bilinenAdaylari, adet - unluAdedi + eksik);
                return Ekle(unluAdaylari, eksik) == 0;
            }

            // Her kutuya, kutuya uyan ayrı bir ünlü oyuncu: kart böylece her zaman doldurulabilir
            foreach (var hucre in hucreler)
            {
                if (Ekle(unluler[hucre], 1) != 0) return null;
            }

            // Ek oyuncular en az bir kutuya uyar ve kutulara dengeli dağıtılır: kalabalık kategoriler (Premier Lig,
            // Şampiyonlar Ligi gibi) ek oyuncuların çoğunu almasın, o kutular erken dolunca oyuncular boşa düşmesin.
            // Kapsama: destede kutuya uyan (kabul edilen cevaplara göre) oyuncu sayısı.
            var kapsama = hucreler.Select(h => deste.Count(h.Oyuncular.Contains)).ToArray();

            // Her adımda, havuzunda kullanılmamış oyuncu kalan kutulardan kapsaması en az olanlardan rastgele biri seçilir,
            // ona uyan rastgele bir oyuncu eklenir. Yetmezse eksik kalan sayıyı döndürür.
            int DengeliEkle(Dictionary<Aday, List<string>> oyuncular, int adet)
            {
                for (; adet > 0; adet--)
                {
                    var uygun = Enumerable.Range(0, HucreSayisi)
                        .Where(h => oyuncular[hucreler[h]].Any(o => !kullanilan.Contains(o)))
                        .ToList();
                    if (uygun.Count == 0) break;
                    int enAz = uygun.Min(h => kapsama[h]);
                    var enAzlar = uygun.Where(h => kapsama[h] == enAz).ToList();
                    var hucre = enAzlar[_random.Next(enAzlar.Count)];
                    var oyuncu = RastgeleOyuncu(oyuncular[hucreler[hucre]], kullanilan)!;
                    kullanilan.Add(oyuncu);
                    deste.Add(oyuncu);
                    for (int h = 0; h < HucreSayisi; h++)
                    {
                        if (hucreler[h].Oyuncular.Contains(oyuncu)) kapsama[h]++;
                    }
                }
                return adet;
            }

            // Önce ünlüler, kalanı bilinenler; biri yetmezse eksik diğerinden tamamlanır (EkOyuncular gibi)
            int eksikUyan = DengeliEkle(unluler, EkUyanUnluSayisi);
            eksikUyan = DengeliEkle(bilinenler, EkUyanSayisi - EkUyanUnluSayisi + eksikUyan);
            if (DengeliEkle(unluler, eksikUyan) != 0) return null;

            // Hiçbir kutuya uymayan oyuncular: kabul edilen cevaplara (Oyuncular) bakılır, yeterince maça çıkmamış olsa da uyan sayılır
            bool Uymaz(string o) => !hucreler.Any(h => h.Oyuncular.Contains(o));
            if (!EkOyuncular(havuzUnlu.Where(Uymaz).ToList(), havuzBilinen.Where(Uymaz).ToList(), UymayanSayisi, UymayanUnluSayisi))
                return null;

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

        // Kartın kulüpleri: en fazla MaxBasAltiKulup baş altı kulüp, kalanı büyük kulüp
        private List<Aday> KulupleriSec(List<Aday> kulupler, int adet)
        {
            var basAltilar = kulupler.Where(k => k.Kategori.BasAlti).ToList();
            var buyukler = kulupler.Where(k => !k.Kategori.BasAlti).ToList();
            int basAltiAdedi = _random.Next(Math.Min(MaxBasAltiKulup, basAltilar.Count) + 1);
            return RastgeleSec(buyukler, adet - basAltiAdedi).Concat(RastgeleSec(basAltilar, basAltiAdedi)).ToList();
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
