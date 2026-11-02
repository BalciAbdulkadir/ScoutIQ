using ScoutIQ.API.Models;
using ScoutIQ.API.Oyunlar;
using static ScoutIQ.API.Oyunlar.IzgaraSoruSecici;

namespace ScoutIQ.API.Tests;

public class IzgaraSoruSeciciTests
{
    // Testler için küçük bir futbol dünyası: kulüpler, milli takımlar ve hepsinde oynamış oyuncular
    private sealed class TestVerisi
    {
        public List<Kulup> Kulupler { get; } = new();
        public List<KariyerGecmisi> Kariyer { get; } = new();
        public List<MilliTakimKariyeri> MilliKariyer { get; } = new();
        private int _oyuncuNo;

        public Kulup Kulup(string transfermarktId, string isim, string? lig = "XX")
        {
            var kulup = new Kulup { Id = $"kulup-{transfermarktId}", TransfermarktId = transfermarktId, Isim = isim, Lig = lig };
            Kulupler.Add(kulup);
            return kulup;
        }

        // Kulüpte ve (varsa) milli takımda oynamış "adet" kadar yeni oyuncu ekler
        public void OyuncuEkle(Kulup kulup, int adet, Kulup? ikinciKulup = null, string? milliTmId = null, string milliIsim = "")
        {
            for (int i = 0; i < adet; i++)
            {
                var oyuncuId = $"oyuncu-{++_oyuncuNo}";
                Kariyer.Add(new KariyerGecmisi { OyuncuId = oyuncuId, KulupId = kulup.Id });
                if (ikinciKulup != null) Kariyer.Add(new KariyerGecmisi { OyuncuId = oyuncuId, KulupId = ikinciKulup.Id });
                if (milliTmId != null) MilliKariyer.Add(new MilliTakimKariyeri { OyuncuId = oyuncuId, MilliTakimTmId = milliTmId, MilliTakimIsim = milliIsim });
            }
        }

        public HashSet<string> Oyunculari(Baslik baslik) => baslik.Tip == BaslikTipi.Kulup
            ? Kariyer.Where(k => k.KulupId == baslik.KulupId).Select(k => k.OyuncuId).ToHashSet()
            : MilliKariyer.Where(m => m.MilliTakimTmId == baslik.TmId).Select(m => m.OyuncuId).ToHashSet();
    }

    private const string Fransa = "3377", Ispanya = "3375", Turkiye = "3381", Sirbistan = "3438", Gana = "3441";

    // Listedeki 10 kulüp birbirine ve 4 milli takıma 3'er ortak oyuncuyla bağlı. Tuzaklar da var.
    private static TestVerisi ZenginVeri()
    {
        var v = new TestVerisi();
        var kulupler = new[]
        {
            v.Kulup("141", "Galatasaray"), v.Kulup("36", "Fenerbahce"), v.Kulup("281", "Manchester City"),
            v.Kulup("418", "Real Madrid"), v.Kulup("131", "FC Barcelona"), v.Kulup("506", "Juventus FC"),
            v.Kulup("5", "AC Milan"), v.Kulup("27", "FC Bayern Munich"), v.Kulup("6195", "SSC Napoli"), v.Kulup("244", "Olympique Marseille"),
        };

        for (int i = 0; i < kulupler.Length; i++)
            for (int j = i + 1; j < kulupler.Length; j++)
                v.OyuncuEkle(kulupler[i], 3, kulupler[j]);

        foreach (var kulup in kulupler)
        {
            v.OyuncuEkle(kulup, 3, milliTmId: Fransa, milliIsim: "France");
            v.OyuncuEkle(kulup, 3, milliTmId: Ispanya, milliIsim: "Spain");
            v.OyuncuEkle(kulup, 3, milliTmId: Turkiye, milliIsim: "Turkiye");
            v.OyuncuEkle(kulup, 3, milliTmId: Sirbistan, milliIsim: "Serbia");
            // Tuzak: Gana her kulüpte tek oyuncuyla temsil ediliyor, hiçbir hücre yeterli cevap bulamaz
            v.OyuncuEkle(kulup, 1, milliTmId: Gana, milliIsim: "Ghana");
        }

        // Tuzak: listede olmayan kulüp, herkesle çok ortak oyuncusu olsa da başlık olmamalı
        var parma = v.Kulup("130", "Parma Calcio 1913");
        foreach (var kulup in kulupler)
            v.OyuncuEkle(parma, 10, kulup);

        return v;
    }

    public static IEnumerable<object[]> TohumVeZorluklar() =>
        from tohum in Enumerable.Range(0, 40)
        from zorluk in Enum.GetValues<Zorluk>()
        select new object[] { tohum, zorluk };

    [Theory]
    [MemberData(nameof(TohumVeZorluklar))]
    public void Sec_HerTohumda_TumKurallaraUyar(int tohum, Zorluk zorluk)
    {
        var veri = ZenginVeri();

        var izgara = new IzgaraSoruSecici(new Random(tohum)).Sec(zorluk, veri.Kulupler, veri.Kariyer, veri.MilliKariyer);

        Assert.NotNull(izgara);
        Assert.Equal(Boyut, izgara!.Satirlar.Count);
        Assert.Equal(Boyut, izgara.Sutunlar.Count);

        var basliklar = izgara.Satirlar.Concat(izgara.Sutunlar).ToList();
        Assert.Equal(basliklar.Count, basliklar.Select(b => b.TmId).Distinct().Count());
        Assert.All(basliklar.Where(b => b.Tip == BaslikTipi.Kulup), b => Assert.True(Kulupler.ContainsKey(b.TmId), $"Listede olmayan kulüp: {b.Isim}"));

        // Hücre cevap sayıları doğru ve hepsi yeterli
        for (int s = 0; s < Boyut; s++)
            for (int t = 0; t < Boyut; t++)
            {
                var gercek = veri.Oyunculari(izgara.Satirlar[s]).Intersect(veri.Oyunculari(izgara.Sutunlar[t])).Count();
                Assert.Equal(gercek, izgara.CevapSayilari[s * Boyut + t]);
                Assert.True(gercek >= MinCevap, $"{izgara.Satirlar[s].Isim} x {izgara.Sutunlar[t].Isim}: {gercek} cevap");
            }

        var milliler = basliklar.Where(b => b.Tip == BaslikTipi.Milli).ToList();
        switch (zorluk)
        {
            case Zorluk.Kolay:
                Assert.Empty(milliler);
                break;
            case Zorluk.Orta:
                Assert.InRange(milliler.Count, 1, MaxMilliTakim);
                Assert.All(milliler, m => Assert.True(OrtaMilliTakimlar.ContainsKey(m.TmId)));
                break;
            case Zorluk.Zor:
                Assert.InRange(milliler.Count, 1, MaxMilliTakim);
                Assert.All(milliler, m => Assert.False(OrtaMilliTakimlar.ContainsKey(m.TmId)));
                break;
        }

        // Milli takımlar aynı eksende: milli takım x milli takım hücresi yok
        bool satirdaMilli = izgara.Satirlar.Any(b => b.Tip == BaslikTipi.Milli);
        bool sutundaMilli = izgara.Sutunlar.Any(b => b.Tip == BaslikTipi.Milli);
        Assert.False(satirdaMilli && sutundaMilli);
    }

    [Fact]
    public void Sec_OrtaSeviyede_MilliTakimTurkceIsimleGosterilir_ZordaTransfermarktIsmiyle()
    {
        var veri = ZenginVeri();

        var orta = new IzgaraSoruSecici(new Random(3)).Sec(Zorluk.Orta, veri.Kulupler, veri.Kariyer, veri.MilliKariyer)!;
        var zor = new IzgaraSoruSecici(new Random(3)).Sec(Zorluk.Zor, veri.Kulupler, veri.Kariyer, veri.MilliKariyer)!;

        Assert.All(orta.Satirlar.Concat(orta.Sutunlar).Where(b => b.Tip == BaslikTipi.Milli),
            m => Assert.Contains(m.Isim, new[] { "Fransa", "İspanya" }));
        Assert.All(zor.Satirlar.Concat(zor.Sutunlar).Where(b => b.Tip == BaslikTipi.Milli),
            m => Assert.Contains(m.Isim, new[] { "Turkiye", "Serbia" }));
    }

    [Fact]
    public void Sec_AyniTohumla_AyniTahtayiSecer()
    {
        var veri = ZenginVeri();

        var ilk = new IzgaraSoruSecici(new Random(42)).Sec(Zorluk.Orta, veri.Kulupler, veri.Kariyer, veri.MilliKariyer)!;
        var ikinci = new IzgaraSoruSecici(new Random(42)).Sec(Zorluk.Orta, veri.Kulupler, veri.Kariyer, veri.MilliKariyer)!;

        Assert.Equal(ilk.Satirlar, ikinci.Satirlar);
        Assert.Equal(ilk.Sutunlar, ikinci.Sutunlar);
    }

    [Fact]
    public void Sec_FarkliTohumlarla_FarkliTahtalarSecer()
    {
        var veri = ZenginVeri();

        var tahtalar = Enumerable.Range(0, 20)
            .Select(t => new IzgaraSoruSecici(new Random(t)).Sec(Zorluk.Kolay, veri.Kulupler, veri.Kariyer, veri.MilliKariyer)!)
            .Select(i => string.Join("|", i.Satirlar.Concat(i.Sutunlar).Select(b => b.TmId)))
            .ToHashSet();

        Assert.True(tahtalar.Count > 1, "Her gün aynı tahta seçiliyor");
    }

    [Fact]
    public void Sec_YeterliOrtakOyuncuYoksa_NullDoner()
    {
        var v = new TestVerisi();
        var kulupler = new[]
        {
            v.Kulup("141", "Galatasaray"), v.Kulup("36", "Fenerbahce"), v.Kulup("281", "Manchester City"),
            v.Kulup("418", "Real Madrid"), v.Kulup("131", "FC Barcelona"), v.Kulup("506", "Juventus FC"),
        };
        // Her çiftin sadece 2 ortak oyuncusu var, hiçbir hücre en az 3 cevaba ulaşamaz
        for (int i = 0; i < kulupler.Length; i++)
            for (int j = i + 1; j < kulupler.Length; j++)
                v.OyuncuEkle(kulupler[i], MinCevap - 1, kulupler[j]);

        var izgara = new IzgaraSoruSecici(new Random(1)).Sec(Zorluk.Kolay, v.Kulupler, v.Kariyer, v.MilliKariyer);

        Assert.Null(izgara);
    }

    [Fact]
    public void Sec_UygunMilliTakimYoksa_OrtaIcinNullDoner()
    {
        var veri = ZenginVeri();
        // Sadece zor seviyenin milli takımları kalsın
        veri.MilliKariyer.RemoveAll(m => OrtaMilliTakimlar.ContainsKey(m.MilliTakimTmId));

        var izgara = new IzgaraSoruSecici(new Random(1)).Sec(Zorluk.Orta, veri.Kulupler, veri.Kariyer, veri.MilliKariyer);

        Assert.Null(izgara);
    }
}
