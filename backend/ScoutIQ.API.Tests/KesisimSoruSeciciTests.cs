using ScoutIQ.API.Models;
using ScoutIQ.API.Oyunlar;
using static ScoutIQ.API.Oyunlar.KesisimSoruSecici;

namespace ScoutIQ.API.Tests;

public class KesisimSoruSeciciTests
{
    // Testler için küçük bir futbol dünyası: kulüpler, aralarındaki ortak oyuncular ve oyuncu kademeleri
    private sealed class TestVerisi
    {
        public List<Kulup> Kulupler { get; } = new();
        public List<KariyerGecmisi> Kariyer { get; } = new();
        public Dictionary<string, Kademe> Kademeler { get; } = new();
        private int _oyuncuNo;

        public Kulup Kulup(string transfermarktId, string isim, string? lig)
        {
            var kulup = new Kulup { Id = $"kulup-{transfermarktId}", TransfermarktId = transfermarktId, Isim = isim, Lig = lig };
            Kulupler.Add(kulup);
            return kulup;
        }

        // İki kulüpte de oynamış "adet" kadar yeni oyuncu ekler. kademe null: soru havuzunda değil.
        // macSayisi 0: kadroda olmuş ama maça çıkmamış.
        public void OrtakOyuncuEkle(Kulup a, Kulup b, int adet, Kademe? kademe, int macSayisi = 10)
        {
            for (int i = 0; i < adet; i++)
            {
                var oyuncuId = $"oyuncu-{++_oyuncuNo}";
                Kariyer.Add(new KariyerGecmisi { OyuncuId = oyuncuId, KulupId = a.Id, MacSayisi = macSayisi });
                Kariyer.Add(new KariyerGecmisi { OyuncuId = oyuncuId, KulupId = b.Id, MacSayisi = macSayisi });
                if (kademe != null) Kademeler[oyuncuId] = kademe.Value;
            }
        }

        public HashSet<string> Oyunculari(Kulup k, bool sadeceOynayan) =>
            Kariyer.Where(r => r.KulupId == k.Id && (!sadeceOynayan || r.Oynadi)).Select(r => r.OyuncuId).ToHashSet();

        public int GercekOrtakSayisi(Kulup a, Kulup b) => Oyunculari(a, false).Intersect(Oyunculari(b, false)).Count();

        public Kademe? GercekKademe(Kulup a, Kulup b) =>
            ZorlukDagilimi.EnBilinen(Oyunculari(a, true).Intersect(Oyunculari(b, true)), Kademeler);

        public SecimSonucu Sec(int tohum, Zorluk zorluk) => new KesisimSoruSecici(new Random(tohum)).Sec(zorluk, Kulupler, Kariyer, Kademeler);
    }

    private static bool Buyuk(Kulup k) => BuyukKulupler.ContainsKey(k.TransfermarktId);

    // Listedeki 16 kulüp birbirine bağlı; çiftlerin kademeleri karışık. Tuzaklar da var.
    private static TestVerisi ZenginVeri()
    {
        var v = new TestVerisi();
        var kulupler = new[]
        {
            v.Kulup("141", "Galatasaray", "TR1"), v.Kulup("36", "Fenerbahce", "TR1"), v.Kulup("449", "Trabzonspor", "TR1"),
            v.Kulup("281", "Manchester City", "GB1"), v.Kulup("631", "Chelsea FC", "GB1"), v.Kulup("405", "Aston Villa", "GB1"),
            v.Kulup("418", "Real Madrid", "ES1"), v.Kulup("131", "FC Barcelona", "ES1"), v.Kulup("368", "Sevilla FC", "ES1"),
            v.Kulup("506", "Juventus FC", "IT1"), v.Kulup("6195", "SSC Napoli", "IT1"),
            v.Kulup("27", "FC Bayern Munich", "L1"), v.Kulup("15", "Bayer 04 Leverkusen", "L1"),
            v.Kulup("583", "Paris Saint-Germain", "FR1"), v.Kulup("244", "Olympique Marseille", "FR1"), v.Kulup("162", "AS Monaco", "FR1"),
        };

        for (int i = 0; i < kulupler.Length; i++)
        {
            for (int j = i + 1; j < kulupler.Length; j++)
            {
                // Her çiftte en bilinen oyuncunun kademesi farklı; havuz dışı bir oyuncu da var
                var kademe = ((i + 2 * j) % 3) switch { 0 => Kademe.Unlu, 1 => Kademe.Bilinen, _ => Kademe.Diger };
                v.OrtakOyuncuEkle(kulupler[i], kulupler[j], 1 + (i + j) % 2, kademe);
                if (kademe != Kademe.Diger) v.OrtakOyuncuEkle(kulupler[i], kulupler[j], 1, Kademe.Diger);
                v.OrtakOyuncuEkle(kulupler[i], kulupler[j], 1, null);

                // Tuzak: kadroda olup maça çıkmamış ünlü oyuncu çiftin kademesini yükseltmemeli
                if ((i + j) % 4 == 0) v.OrtakOyuncuEkle(kulupler[i], kulupler[j], 1, Kademe.Unlu, macSayisi: 0);
            }
        }

        // Tuzak: listede olmayan kulüpler, ünlü ortak oyuncuları olsa da sorulmamalı
        var parma = v.Kulup("130", "Parma Calcio 1913", "IT1");
        var brest = v.Kulup("3911", "Stade Brestois 29", "FR1");
        foreach (var kulup in kulupler)
        {
            v.OrtakOyuncuEkle(parma, kulup, 5, Kademe.Unlu);
            v.OrtakOyuncuEkle(brest, kulup, 5, Kademe.Unlu);
        }

        return v;
    }

    public static IEnumerable<object[]> TohumVeZorluklar() =>
        from tohum in Enumerable.Range(0, 50)
        from zorluk in Enum.GetValues<Zorluk>()
        select new object[] { tohum, zorluk };

    [Theory]
    [MemberData(nameof(TohumVeZorluklar))]
    public void Sec_HerTohumda_TumKurallaraUyar(int tohum, Zorluk zorluk)
    {
        var veri = ZenginVeri();

        var sonuc = veri.Sec(tohum, zorluk);

        Assert.NotNull(sonuc.Sorular);
        Assert.Empty(sonuc.Uyarilar);
        var sorular = sonuc.Sorular!;
        Assert.Equal(SoruSayisi, sorular.Count);

        // Kademe dağılımı moda tam uyar ve sorular kolaydan zora sıralıdır
        var dagilim = ZorlukDagilimi.Dagit(zorluk, SoruSayisi);
        foreach (var kademe in Enum.GetValues<Kademe>())
            Assert.Equal(dagilim.GetValueOrDefault(kademe), sorular.Count(s => s.Kademe == kademe));
        Assert.Equal(sorular.Select(s => s.Kademe).OrderBy(k => k), sorular.Select(s => s.Kademe));

        foreach (var soru in sorular)
        {
            var (a, b) = (soru.KulupA, soru.KulupB);
            Assert.True(Kulupler.ContainsKey(a.TransfermarktId) && Kulupler.ContainsKey(b.TransfermarktId), $"Listede olmayan kulüp: {a.Isim} x {b.Isim}");
            Assert.Equal(veri.GercekOrtakSayisi(a, b), soru.OrtakOyuncuSayisi);
            Assert.Equal(veri.GercekKademe(a, b), soru.Kademe);
            Assert.True(a.Lig != b.Lig || (Buyuk(a) && Buyuk(b)), $"Aynı ligden büyük olmayan çift: {a.Isim} x {b.Isim}");
        }

        var kullanilanKulupler = sorular.SelectMany(s => new[] { s.KulupA.Id, s.KulupB.Id }).ToList();
        Assert.Equal(kullanilanKulupler.Count, kullanilanKulupler.Distinct().Count());
    }

    [Fact]
    public void Sec_AyniTohumla_AyniSorulariSecer()
    {
        var veri = ZenginVeri();

        var ilk = veri.Sec(42, Zorluk.Zor).Sorular!;
        var ikinci = veri.Sec(42, Zorluk.Zor).Sorular!;

        Assert.Equal(ilk.Select(s => (s.KulupA.Id, s.KulupB.Id)), ikinci.Select(s => (s.KulupA.Id, s.KulupB.Id)));
    }

    [Fact]
    public void Sec_FarkliTohumlarla_FarkliSorularSecer()
    {
        var veri = ZenginVeri();

        var setler = Enumerable.Range(0, 20)
            .Select(t => string.Join("|", veri.Sec(t, Zorluk.Orta).Sorular!.Select(s => $"{s.KulupA.Id}-{s.KulupB.Id}")))
            .ToHashSet();

        Assert.True(setler.Count > 1, "Her gün aynı sorular seçiliyor");
    }

    // Birbirinden bağımsız 5 kulüp çifti: her çiftin ortak oyuncusu verilen kademede
    private static TestVerisi BesCift(params Kademe[] kademeler)
    {
        var v = new TestVerisi();
        var kulupler = new[]
        {
            v.Kulup("141", "Galatasaray", "TR1"), v.Kulup("281", "Manchester City", "GB1"),
            v.Kulup("36", "Fenerbahce", "TR1"), v.Kulup("631", "Chelsea FC", "GB1"),
            v.Kulup("418", "Real Madrid", "ES1"), v.Kulup("506", "Juventus FC", "IT1"),
            v.Kulup("131", "FC Barcelona", "ES1"), v.Kulup("27", "FC Bayern Munich", "L1"),
            v.Kulup("583", "Paris Saint-Germain", "FR1"), v.Kulup("16", "Borussia Dortmund", "L1"),
        };
        for (int i = 0; i < kademeler.Length; i++)
            v.OrtakOyuncuEkle(kulupler[2 * i], kulupler[2 * i + 1], 2, kademeler[i]);
        return v;
    }

    [Fact]
    public void Sec_DigerCiftKalmazsa_BilinenKullanir_UyariVerir()
    {
        var veri = BesCift(Kademe.Unlu, Kademe.Unlu, Kademe.Bilinen, Kademe.Bilinen, Kademe.Bilinen);

        var sonuc = veri.Sec(1, Zorluk.Zor);

        Assert.NotNull(sonuc.Sorular);
        Assert.Equal(new[] { Kademe.Unlu, Kademe.Unlu, Kademe.Bilinen, Kademe.Bilinen, Kademe.Bilinen }, sonuc.Sorular!.Select(s => s.Kademe));
        Assert.Contains(sonuc.Uyarilar, u => u.Contains("Diger çift kalmadı"));
    }

    [Fact]
    public void Sec_KolaydaUnluCiftYetmezse_DahaZorCiftKullanmaz_NullDoner()
    {
        var veri = BesCift(Kademe.Unlu, Kademe.Unlu, Kademe.Unlu, Kademe.Unlu, Kademe.Bilinen);

        var sonuc = veri.Sec(1, Zorluk.Kolay);

        Assert.Null(sonuc.Sorular);
        Assert.Contains(sonuc.Uyarilar, u => u.Contains("5 eşleşme bulunamadı"));
    }

    [Fact]
    public void Sec_TamDagilimKurulabiliyorsa_YedekKademeKullanmaz()
    {
        // Bilinen çiftlerden biri, tek diğer çiftin kulübünü kullanıyor: ilk karıştırmada diğer çift kaçırılabilir,
        // seçici yine de dağılıma tam uyan seti bulmalı
        var veri = BesCift(Kademe.Unlu, Kademe.Unlu, Kademe.Bilinen, Kademe.Bilinen, Kademe.Diger);
        var psg = veri.Kulupler.Single(k => k.TransfermarktId == "583");
        var juve = veri.Kulupler.Single(k => k.TransfermarktId == "506");
        veri.OrtakOyuncuEkle(psg, juve, 2, Kademe.Bilinen);

        for (int tohum = 0; tohum < 30; tohum++)
        {
            var sonuc = veri.Sec(tohum, Zorluk.Zor);
            Assert.Empty(sonuc.Uyarilar);
            Assert.Equal(new[] { Kademe.Unlu, Kademe.Unlu, Kademe.Bilinen, Kademe.Bilinen, Kademe.Diger }, sonuc.Sorular!.Select(s => s.Kademe));
        }
    }

    [Fact]
    public void Sec_MacaCikmayanUnluOyuncu_CiftiUnluYapmaz()
    {
        var veri = BesCift(Kademe.Unlu, Kademe.Unlu, Kademe.Unlu, Kademe.Unlu, Kademe.Diger);
        // Son çiftte maça çıkmamış bir ünlü oyuncu da var: çift yine diğer sayılmalı
        var psg = veri.Kulupler.Single(k => k.TransfermarktId == "583");
        var bvb = veri.Kulupler.Single(k => k.TransfermarktId == "16");
        veri.OrtakOyuncuEkle(psg, bvb, 1, Kademe.Unlu, macSayisi: 0);

        Assert.Null(veri.Sec(1, Zorluk.Kolay).Sorular);
        Assert.Equal(Kademe.Diger, veri.Sec(1, Zorluk.Zor).Sorular!.Single(s => s.KulupA == psg || s.KulupB == psg).Kademe);
    }

    [Fact]
    public void Sec_MacSayisiBilinmeyenOyuncu_OynamisSayilir()
    {
        var veri = BesCift(Kademe.Unlu, Kademe.Unlu, Kademe.Unlu, Kademe.Unlu, Kademe.Diger);
        var psg = veri.Kulupler.Single(k => k.TransfermarktId == "583");
        var bvb = veri.Kulupler.Single(k => k.TransfermarktId == "16");
        veri.OrtakOyuncuEkle(psg, bvb, 1, Kademe.Unlu);
        veri.Kariyer.Where(k => k.KulupId == psg.Id || k.KulupId == bvb.Id).ToList().ForEach(k => k.MacSayisi = null);

        Assert.NotNull(veri.Sec(1, Zorluk.Kolay).Sorular);
    }

    [Fact]
    public void Sec_HavuzdanOrtakOyuncusuOlmayanCift_Sorulmaz()
    {
        var veri = BesCift(Kademe.Unlu, Kademe.Unlu, Kademe.Unlu, Kademe.Unlu);
        var psg = veri.Kulupler.Single(k => k.TransfermarktId == "583");
        var bvb = veri.Kulupler.Single(k => k.TransfermarktId == "16");
        veri.OrtakOyuncuEkle(psg, bvb, 3, null);

        Assert.Null(veri.Sec(1, Zorluk.Kolay).Sorular);
    }

    [Fact]
    public void Sec_KariyerVerisiBossa_NullDoner()
    {
        var v = new TestVerisi();
        v.Kulup("141", "Galatasaray", "TR1");
        v.Kulup("36", "Fenerbahce", "TR1");

        Assert.Null(v.Sec(1, Zorluk.Kolay).Sorular);
    }

    // Sorulabilir: aynı ligden çift sadece iki büyük kulüpse sorulur

    private static readonly Kulup Galatasaray = new() { Id = "gs", TransfermarktId = "141", Lig = "TR1" };
    private static readonly Kulup Fenerbahce = new() { Id = "fb", TransfermarktId = "36", Lig = "TR1" };
    private static readonly Kulup Trabzonspor = new() { Id = "ts", TransfermarktId = "449", Lig = "TR1" };
    private static readonly Kulup Chelsea = new() { Id = "chelsea", TransfermarktId = "631", Lig = "GB1" };
    private static readonly Kulup AstonVilla = new() { Id = "villa", TransfermarktId = "405", Lig = "GB1" };

    [Fact]
    public void Sorulabilir_IkiBuyukKulup_AyniLigdeBile() => Assert.True(Sorulabilir(Galatasaray, Fenerbahce));

    [Fact]
    public void Sorulabilir_FarkliLig() => Assert.True(Sorulabilir(Trabzonspor, AstonVilla));

    [Fact]
    public void Sorulabilir_AyniLig_BuyukCiftDegilse_Hayir()
    {
        Assert.False(Sorulabilir(Trabzonspor, Galatasaray));
        Assert.False(Sorulabilir(AstonVilla, Chelsea));
    }

    [Fact]
    public void KulupListeleri_BirbiriyleCakismaz() =>
        Assert.Empty(BuyukKulupler.Keys.Intersect(BasAltiKulupler.Keys));
}
