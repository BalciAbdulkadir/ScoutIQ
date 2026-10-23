using ScoutIQ.API.Models;
using ScoutIQ.API.Oyunlar;
using static ScoutIQ.API.Oyunlar.KesisimSoruSecici;

namespace ScoutIQ.API.Tests;

public class KesisimSoruSeciciTests
{
    // Testler için küçük bir futbol dünyası: kulüpler ve aralarındaki ortak oyuncular
    private sealed class TestVerisi
    {
        public List<Kulup> Kulupler { get; } = new();
        public List<KariyerGecmisi> Kariyer { get; } = new();
        private int _oyuncuNo;

        public Kulup Kulup(string transfermarktId, string isim, string lig)
        {
            var kulup = new Kulup { Id = $"kulup-{transfermarktId}", TransfermarktId = transfermarktId, Isim = isim, Lig = lig };
            Kulupler.Add(kulup);
            return kulup;
        }

        // İki kulüpte de oynamış "adet" kadar yeni oyuncu ekler
        public void OrtakOyuncuEkle(Kulup a, Kulup b, int adet)
        {
            for (int i = 0; i < adet; i++)
            {
                var oyuncuId = $"oyuncu-{++_oyuncuNo}";
                Kariyer.Add(new KariyerGecmisi { OyuncuId = oyuncuId, KulupId = a.Id });
                Kariyer.Add(new KariyerGecmisi { OyuncuId = oyuncuId, KulupId = b.Id });
            }
        }

        public int GercekOrtakSayisi(Kulup a, Kulup b)
        {
            var aOyunculari = Kariyer.Where(k => k.KulupId == a.Id).Select(k => k.OyuncuId).ToHashSet();
            return Kariyer.Where(k => k.KulupId == b.Id).Select(k => k.OyuncuId).Distinct().Count(aOyunculari.Contains);
        }
    }

    private static bool Buyuk(Kulup k) => BuyukKulupler.ContainsKey(k.TransfermarktId);
    private static bool BasAlti(Kulup k) => BasAltiKulupler.ContainsKey(k.TransfermarktId);

    // Her zorluk için bol çift olan, tuzaklar da içeren gerçekçi bir veri seti
    private static TestVerisi ZenginVeri()
    {
        var v = new TestVerisi();

        var buyukler = new[]
        {
            v.Kulup("141", "Galatasaray", "TR1"), v.Kulup("36", "Fenerbahce", "TR1"), v.Kulup("114", "Beşiktaş JK", "TR1"),
            v.Kulup("281", "Manchester City", "GB1"), v.Kulup("631", "Chelsea FC", "GB1"),
            v.Kulup("418", "Real Madrid", "ES1"), v.Kulup("131", "FC Barcelona", "ES1"),
            v.Kulup("506", "Juventus FC", "IT1"), v.Kulup("27", "FC Bayern Munich", "L1"), v.Kulup("583", "Paris Saint-Germain", "FR1"),
        };
        var basAltilar = new[]
        {
            v.Kulup("244", "Olympique Marseille", "FR1"), v.Kulup("405", "Aston Villa", "GB1"), v.Kulup("368", "Sevilla FC", "ES1"),
            v.Kulup("6195", "SSC Napoli", "IT1"), v.Kulup("15", "Bayer 04 Leverkusen", "L1"), v.Kulup("449", "Trabzonspor", "TR1"),
        };
        var siradanlar = new[]
        {
            v.Kulup("10484", "Kasımpaşa", "TR1"), v.Kulup("130", "Parma Calcio 1913", "IT1"), v.Kulup("3911", "Stade Brestois 29", "FR1"),
            v.Kulup("989", "AFC Bournemouth", "GB1"), v.Kulup("1531", "Elche CF", "ES1"), v.Kulup("39", "1.FSV Mainz 05", "L1"),
        };

        // Büyük kulüplerin hepsi birbirine 1-2 ortak oyuncuyla bağlı: kolay havuzu
        for (int i = 0; i < buyukler.Length; i++)
            for (int j = i + 1; j < buyukler.Length; j++)
                v.OrtakOyuncuEkle(buyukler[i], buyukler[j], 1 + (i + j) % 2);

        // Baş altı kulüpler, farklı ligdeki büyük ve baş altı kulüplere 2-3 ortak oyuncuyla bağlı: orta havuzu
        var ustSeviye = buyukler.Concat(basAltilar).ToArray();
        for (int i = 0; i < ustSeviye.Length; i++)
            for (int j = i + 1; j < ustSeviye.Length; j++)
                if (ustSeviye[i].Lig != ustSeviye[j].Lig && (BasAlti(ustSeviye[i]) || BasAlti(ustSeviye[j])))
                    v.OrtakOyuncuEkle(ustSeviye[i], ustSeviye[j], 2 + (i + j) % 2);

        // Sıradan kulüpler farklı ligdeki kulüplere tek ortak oyuncuyla bağlı: zor havuzu
        foreach (var siradan in siradanlar)
            foreach (var diger in siradanlar.Where(k => k.Lig != siradan.Lig && string.CompareOrdinal(k.Id, siradan.Id) < 0))
                v.OrtakOyuncuEkle(siradan, diger, 1);

        // Tuzaklar: hiçbiri kurallara aykırı bir yerde sorulmamalı
        v.OrtakOyuncuEkle(siradanlar[0], basAltilar[5], 6);  // Kasımpaşa x Trabzonspor: aynı lig, çok ortak oyuncu
        v.OrtakOyuncuEkle(siradanlar[1], basAltilar[3], 5);  // Parma x Napoli: aynı lig
        v.OrtakOyuncuEkle(siradanlar[2], basAltilar[1], 4);  // Brest x Aston Villa: baş altı + sıradan, orta sayılmamalı

        return v;
    }

    public static IEnumerable<object[]> Tohumlar() => Enumerable.Range(0, 100).Select(t => new object[] { t });

    [Theory]
    [MemberData(nameof(Tohumlar))]
    public void Sec_HerTohumda_TumKurallaraUyar(int tohum)
    {
        var veri = ZenginVeri();

        var sonuc = new KesisimSoruSecici(new Random(tohum)).Sec(veri.Kulupler, veri.Kariyer);

        Assert.NotNull(sonuc.Sorular);
        var sorular = sonuc.Sorular!;
        Assert.Equal(SoruSirasi, sorular.Select(s => s.Zorluk).ToList());

        foreach (var soru in sorular)
        {
            var (a, b) = (soru.Cift.KulupA, soru.Cift.KulupB);
            Assert.Equal(veri.GercekOrtakSayisi(a, b), soru.Cift.OrtakOyuncuSayisi);
            Assert.True(soru.Cift.OrtakOyuncuSayisi >= 1, $"{a.Isim} x {b.Isim}: ortak oyuncu yok");

            switch (soru.Zorluk)
            {
                case Zorluk.Kolay:
                    Assert.True(Buyuk(a) && Buyuk(b), $"Kolay soruda büyük olmayan kulüp: {a.Isim} x {b.Isim}");
                    break;
                case Zorluk.Orta:
                    Assert.True(BasAlti(a) || BasAlti(b), $"Orta soruda baş altı kulüp yok: {a.Isim} x {b.Isim}");
                    Assert.True((Buyuk(a) || BasAlti(a)) && (Buyuk(b) || BasAlti(b)), $"Orta soruda sıradan kulüp: {a.Isim} x {b.Isim}");
                    Assert.NotEqual(a.Lig, b.Lig);
                    Assert.True(soru.Cift.OrtakOyuncuSayisi >= OrtaMinOrtakOyuncu, $"Orta soruda 2'den az ortak oyuncu: {a.Isim} x {b.Isim}");
                    break;
                case Zorluk.Zor:
                    Assert.NotEqual(a.Lig, b.Lig);
                    break;
            }
        }

        var kullanilanKulupler = sorular.SelectMany(s => new[] { s.Cift.KulupA.Id, s.Cift.KulupB.Id }).ToList();
        Assert.Equal(kullanilanKulupler.Count, kullanilanKulupler.Distinct().Count());
    }

    [Fact]
    public void Sec_AyniTohumla_AyniSorulariSecer()
    {
        var veri = ZenginVeri();

        var ilk = new KesisimSoruSecici(new Random(42)).Sec(veri.Kulupler, veri.Kariyer).Sorular!;
        var ikinci = new KesisimSoruSecici(new Random(42)).Sec(veri.Kulupler, veri.Kariyer).Sorular!;

        Assert.Equal(
            ilk.Select(s => (s.Cift.KulupA.Id, s.Cift.KulupB.Id)),
            ikinci.Select(s => (s.Cift.KulupA.Id, s.Cift.KulupB.Id)));
    }

    [Fact]
    public void Sec_FarkliTohumlarla_FarkliSorularSecer()
    {
        var veri = ZenginVeri();

        var setler = Enumerable.Range(0, 20)
            .Select(t => string.Join("|", new KesisimSoruSecici(new Random(t)).Sec(veri.Kulupler, veri.Kariyer).Sorular!
                .Select(s => $"{s.Cift.KulupA.Id}-{s.Cift.KulupB.Id}")))
            .ToHashSet();

        Assert.True(setler.Count > 1, "Her gün aynı sorular seçiliyor");
    }

    [Fact]
    public void Sec_OrtaCiftKalmazsa_ZorCiftKullanmaz_KolayaDuser()
    {
        var v = new TestVerisi();
        var gs = v.Kulup("141", "Galatasaray", "TR1");
        var fb = v.Kulup("36", "Fenerbahce", "TR1");
        var city = v.Kulup("281", "Manchester City", "GB1");
        var chelsea = v.Kulup("631", "Chelsea FC", "GB1");
        var real = v.Kulup("418", "Real Madrid", "ES1");
        var barca = v.Kulup("131", "FC Barcelona", "ES1");
        var juve = v.Kulup("506", "Juventus FC", "IT1");
        var bayern = v.Kulup("27", "FC Bayern Munich", "L1");
        var parma = v.Kulup("130", "Parma Calcio 1913", "IT1");
        var brest = v.Kulup("3911", "Stade Brestois 29", "FR1");

        // Sadece kolay ve zor çiftler var, hiç orta çift yok
        v.OrtakOyuncuEkle(gs, fb, 1);
        v.OrtakOyuncuEkle(city, chelsea, 1);
        v.OrtakOyuncuEkle(real, barca, 1);
        v.OrtakOyuncuEkle(juve, bayern, 1);
        v.OrtakOyuncuEkle(parma, brest, 1);

        var sonuc = new KesisimSoruSecici(new Random(1)).Sec(v.Kulupler, v.Kariyer);

        Assert.NotNull(sonuc.Sorular);
        var ortaSorular = sonuc.Sorular!.Where(s => s.Zorluk == Zorluk.Orta).ToList();
        Assert.Equal(2, ortaSorular.Count);
        Assert.All(ortaSorular, s => Assert.True(Buyuk(s.Cift.KulupA) && Buyuk(s.Cift.KulupB)));
        Assert.Contains(sonuc.Uyarilar, u => u.Contains("Orta çift kalmadı"));
    }

    [Fact]
    public void Sec_YeterliCiftYoksa_NullVeUyariDoner()
    {
        var v = new TestVerisi();
        var gs = v.Kulup("141", "Galatasaray", "TR1");
        var fb = v.Kulup("36", "Fenerbahce", "TR1");
        var parma = v.Kulup("130", "Parma Calcio 1913", "IT1");
        var brest = v.Kulup("3911", "Stade Brestois 29", "FR1");
        v.OrtakOyuncuEkle(gs, fb, 2);
        v.OrtakOyuncuEkle(parma, brest, 1);

        var sonuc = new KesisimSoruSecici(new Random(1)).Sec(v.Kulupler, v.Kariyer);

        Assert.Null(sonuc.Sorular);
        Assert.Contains(sonuc.Uyarilar, u => u.Contains("5 eşleşme bulunamadı"));
    }

    [Fact]
    public void Sec_KariyerVerisiBossa_NullDoner()
    {
        var v = new TestVerisi();
        v.Kulup("141", "Galatasaray", "TR1");
        v.Kulup("36", "Fenerbahce", "TR1");

        var sonuc = new KesisimSoruSecici(new Random(1)).Sec(v.Kulupler, v.Kariyer);

        Assert.Null(sonuc.Sorular);
    }

    // ZorlukBelirle: tek tek kural örnekleri

    private static readonly Kulup Galatasaray = new() { Id = "gs", TransfermarktId = "141", Lig = "TR1" };
    private static readonly Kulup Fenerbahce = new() { Id = "fb", TransfermarktId = "36", Lig = "TR1" };
    private static readonly Kulup Chelsea = new() { Id = "chelsea", TransfermarktId = "631", Lig = "GB1" };
    private static readonly Kulup Marsilya = new() { Id = "om", TransfermarktId = "244", Lig = "FR1" };
    private static readonly Kulup AstonVilla = new() { Id = "villa", TransfermarktId = "405", Lig = "GB1" };
    private static readonly Kulup Trabzonspor = new() { Id = "ts", TransfermarktId = "449", Lig = "TR1" };
    private static readonly Kulup Kasimpasa = new() { Id = "kasimpasa", TransfermarktId = "10484", Lig = "TR1" };
    private static readonly Kulup Parma = new() { Id = "parma", TransfermarktId = "130", Lig = "IT1" };

    private static Zorluk? Belirle(Kulup a, Kulup b, int ortak)
    {
        var kulupler = new[] { Galatasaray, Fenerbahce, Chelsea, Marsilya, AstonVilla, Trabzonspor, Kasimpasa, Parma };
        return ZorlukBelirle(
            new KulupCifti(a, b, ortak),
            ListedekiKulupIdleri(BuyukKulupler, kulupler),
            ListedekiKulupIdleri(BasAltiKulupler, kulupler));
    }

    [Fact]
    public void ZorlukBelirle_IkiBuyukKulup_AyniLigdeBileKolay() =>
        Assert.Equal(Zorluk.Kolay, Belirle(Galatasaray, Fenerbahce, 1));

    [Fact]
    public void ZorlukBelirle_BasAltiVeBuyuk_FarkliLig_IkiOrtak_Orta() =>
        Assert.Equal(Zorluk.Orta, Belirle(Marsilya, Chelsea, 2));

    [Fact]
    public void ZorlukBelirle_IkiBasAlti_FarkliLig_IkiOrtak_Orta() =>
        Assert.Equal(Zorluk.Orta, Belirle(Marsilya, AstonVilla, 3));

    [Fact]
    public void ZorlukBelirle_BasAltiVeBuyuk_TekOrtak_Zor() =>
        Assert.Equal(Zorluk.Zor, Belirle(Marsilya, Chelsea, 1));

    [Fact]
    public void ZorlukBelirle_BasAltiVeSiradan_CokOrtakOlsaBile_Zor() =>
        Assert.Equal(Zorluk.Zor, Belirle(Marsilya, Parma, 5));

    [Fact]
    public void ZorlukBelirle_AyniLig_BuyukCiftDegilse_Sorulmaz()
    {
        Assert.Null(Belirle(Kasimpasa, Trabzonspor, 6));
        Assert.Null(Belirle(Trabzonspor, Galatasaray, 4));
        Assert.Null(Belirle(AstonVilla, Chelsea, 3));
    }

    // Kulüp listeleri elle düzenlendiği için temel tutarlılık kontrolleri

    [Fact]
    public void KulupListeleri_BirbiriyleCakismaz() =>
        Assert.Empty(BuyukKulupler.Keys.Intersect(BasAltiKulupler.Keys));

    [Fact]
    public void SoruSirasi_IkiKolayIkiOrtaBirZor() =>
        Assert.Equal(new[] { Zorluk.Kolay, Zorluk.Kolay, Zorluk.Orta, Zorluk.Orta, Zorluk.Zor }, SoruSirasi);

    [Fact]
    public void YedekSirasi_OrtaSoruIcinZorCiftKullanilmaz() =>
        Assert.DoesNotContain(Zorluk.Zor, YedekSirasi(Zorluk.Orta));
}
