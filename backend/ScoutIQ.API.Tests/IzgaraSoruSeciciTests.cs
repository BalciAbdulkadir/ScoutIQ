using ScoutIQ.API.Models;
using ScoutIQ.API.Oyunlar;
using static ScoutIQ.API.Oyunlar.IzgaraSoruSecici;

namespace ScoutIQ.API.Tests;

public class IzgaraSoruSeciciTests
{
    // Testler için küçük bir futbol dünyası: kulüpler, milli takımlar, hepsinde oynamış oyuncular ve kademeleri
    private sealed class TestVerisi
    {
        public List<Kulup> Kulupler { get; } = new();
        public List<KariyerGecmisi> Kariyer { get; } = new();
        public List<MilliTakimKariyeri> MilliKariyer { get; } = new();
        public Dictionary<string, Kademe> Kademeler { get; } = new();
        private int _oyuncuNo;

        public Kulup Kulup(string transfermarktId, string isim, string? lig = "XX")
        {
            var kulup = new Kulup { Id = $"kulup-{transfermarktId}", TransfermarktId = transfermarktId, Isim = isim, Lig = lig };
            Kulupler.Add(kulup);
            return kulup;
        }

        // Kulüpte ve (varsa) ikinci kulüpte ya da milli takımda oynamış "adet" kadar yeni oyuncu ekler.
        // kademe null: soru havuzunda değil. macSayisi 0: kulüp kadrosunda olmuş ama maça çıkmamış.
        public void OyuncuEkle(Kulup kulup, int adet, Kademe? kademe, Kulup? ikinciKulup = null, string? milliTmId = null,
            string milliIsim = "", int macSayisi = 10)
        {
            for (int i = 0; i < adet; i++)
            {
                var oyuncuId = $"oyuncu-{++_oyuncuNo}";
                Kariyer.Add(new KariyerGecmisi { OyuncuId = oyuncuId, KulupId = kulup.Id, MacSayisi = macSayisi });
                if (ikinciKulup != null) Kariyer.Add(new KariyerGecmisi { OyuncuId = oyuncuId, KulupId = ikinciKulup.Id, MacSayisi = macSayisi });
                if (milliTmId != null) MilliKariyer.Add(new MilliTakimKariyeri { OyuncuId = oyuncuId, MilliTakimTmId = milliTmId, MilliTakimIsim = milliIsim });
                if (kademe != null) Kademeler[oyuncuId] = kademe.Value;
            }
        }

        public HashSet<string> Oyunculari(Baslik baslik, bool sadeceOynayan = false) => baslik.Tip == BaslikTipi.Kulup
            ? Kariyer.Where(k => k.KulupId == baslik.KulupId && (!sadeceOynayan || k.Oynadi)).Select(k => k.OyuncuId).ToHashSet()
            : MilliKariyer.Where(m => m.MilliTakimTmId == baslik.TmId).Select(m => m.OyuncuId).ToHashSet();

        public Izgara? Sec(int tohum, Zorluk zorluk) =>
            new IzgaraSoruSecici(new Random(tohum)).Sec(zorluk, Kulupler, Kariyer, MilliKariyer, Kademeler);
    }

    private const string Fransa = "3377", Ispanya = "3375", Turkiye = "3381", Sirbistan = "3438", Gana = "3441";

    // Hücrenin en bilinen cevabının kademesi, çiftten çifte değişir: ünlü ağırlıklı, arada bilinen ve diğer
    private static Kademe CiftKademesi(int a, int b) => ((a * 31 + b * 17) % 10) switch
    {
        < 6 => Kademe.Unlu,
        < 8 => Kademe.Bilinen,
        _ => Kademe.Diger
    };

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

        void UcOyuncu(Kulup kulup, Kademe kademe, Kulup? ikinci = null, string? milli = null, string milliIsim = "")
        {
            // En bilinen oyuncu verilen kademede, diğer ikisi daha az bilinen ya da havuz dışı
            v.OyuncuEkle(kulup, 1, kademe, ikinci, milli, milliIsim);
            v.OyuncuEkle(kulup, 1, Kademe.Diger, ikinci, milli, milliIsim);
            v.OyuncuEkle(kulup, 1, null, ikinci, milli, milliIsim);
        }

        for (int i = 0; i < kulupler.Length; i++)
        {
            for (int j = i + 1; j < kulupler.Length; j++)
            {
                UcOyuncu(kulupler[i], CiftKademesi(i, j), kulupler[j]);
                // Tuzak: maça çıkmamış ünlü oyuncu hücrenin kademesini yükseltmemeli (cevap olarak yine sayılır)
                if ((i + j) % 3 == 0) v.OyuncuEkle(kulupler[i], 1, Kademe.Unlu, kulupler[j], macSayisi: 0);
            }
        }

        var milliler = new[] { (Fransa, "France"), (Ispanya, "Spain"), (Turkiye, "Turkiye"), (Sirbistan, "Serbia") };
        for (int i = 0; i < kulupler.Length; i++)
        {
            for (int m = 0; m < milliler.Length; m++)
                UcOyuncu(kulupler[i], CiftKademesi(i, 20 + m), milli: milliler[m].Item1, milliIsim: milliler[m].Item2);
            // Tuzak: Gana her kulüpte tek oyuncuyla temsil ediliyor, hiçbir hücre yeterli cevap bulamaz
            v.OyuncuEkle(kulupler[i], 1, Kademe.Unlu, milliTmId: Gana, milliIsim: "Ghana");
        }

        // Tuzak: listede olmayan kulüp, herkesle çok ortak ünlü oyuncusu olsa da başlık olmamalı
        var parma = v.Kulup("130", "Parma Calcio 1913");
        foreach (var kulup in kulupler)
            v.OyuncuEkle(parma, 10, Kademe.Unlu, kulup);

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

        var izgara = veri.Sec(tohum, zorluk);

        Assert.NotNull(izgara);
        Assert.Equal(Boyut, izgara!.Satirlar.Count);
        Assert.Equal(Boyut, izgara.Sutunlar.Count);

        var basliklar = izgara.Satirlar.Concat(izgara.Sutunlar).ToList();
        Assert.Equal(basliklar.Count, basliklar.Select(b => b.TmId).Distinct().Count());
        Assert.All(basliklar.Where(b => b.Tip == BaslikTipi.Kulup), b => Assert.True(Kulupler.ContainsKey(b.TmId), $"Listede olmayan kulüp: {b.Isim}"));

        // Hücre cevap sayıları ve kademeleri doğru, cevaplar yeterli
        for (int s = 0; s < Boyut; s++)
        {
            for (int t = 0; t < Boyut; t++)
            {
                var (satir, sutun) = (izgara.Satirlar[s], izgara.Sutunlar[t]);
                var gercek = veri.Oyunculari(satir).Intersect(veri.Oyunculari(sutun)).Count();
                Assert.Equal(gercek, izgara.CevapSayilari[s * Boyut + t]);
                Assert.True(gercek >= MinCevap, $"{satir.Isim} x {sutun.Isim}: {gercek} cevap");

                var gercekKademe = ZorlukDagilimi.EnBilinen(veri.Oyunculari(satir, true).Intersect(veri.Oyunculari(sutun, true)), veri.Kademeler);
                Assert.Equal(gercekKademe, izgara.HucreKademeleri[s * Boyut + t]);
            }
        }

        // Hücre kademeleri moda tam uyar
        var dagilim = ZorlukDagilimi.Dagit(zorluk, Boyut * Boyut);
        foreach (var kademe in Enum.GetValues<Kademe>())
            Assert.Equal(dagilim.GetValueOrDefault(kademe), izgara.HucreKademeleri.Count(k => k == kademe));

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

        var orta = veri.Sec(3, Zorluk.Orta)!;
        var zor = veri.Sec(3, Zorluk.Zor)!;

        Assert.All(orta.Satirlar.Concat(orta.Sutunlar).Where(b => b.Tip == BaslikTipi.Milli),
            m => Assert.Contains(m.Isim, new[] { "Fransa", "İspanya" }));
        Assert.All(zor.Satirlar.Concat(zor.Sutunlar).Where(b => b.Tip == BaslikTipi.Milli),
            m => Assert.Contains(m.Isim, new[] { "Turkiye", "Serbia" }));
    }

    [Fact]
    public void Sec_AyniTohumla_AyniTahtayiSecer()
    {
        var veri = ZenginVeri();

        var ilk = veri.Sec(42, Zorluk.Orta)!;
        var ikinci = veri.Sec(42, Zorluk.Orta)!;

        Assert.Equal(ilk.Satirlar, ikinci.Satirlar);
        Assert.Equal(ilk.Sutunlar, ikinci.Sutunlar);
    }

    [Fact]
    public void Sec_FarkliTohumlarla_FarkliTahtalarSecer()
    {
        var veri = ZenginVeri();

        var tahtalar = Enumerable.Range(0, 20)
            .Select(t => veri.Sec(t, Zorluk.Kolay)!)
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
                v.OyuncuEkle(kulupler[i], MinCevap - 1, Kademe.Unlu, kulupler[j]);

        Assert.Null(v.Sec(1, Zorluk.Kolay));
    }

    [Fact]
    public void Sec_KademeDagilimiTutmazsa_NullDoner()
    {
        var v = new TestVerisi();
        var kulupler = new[]
        {
            v.Kulup("141", "Galatasaray"), v.Kulup("36", "Fenerbahce"), v.Kulup("281", "Manchester City"),
            v.Kulup("418", "Real Madrid"), v.Kulup("131", "FC Barcelona"), v.Kulup("506", "Juventus FC"),
        };
        // Bütün hücreler bilinen: kolay tahta (9 ünlü hücre) kurulamaz
        for (int i = 0; i < kulupler.Length; i++)
            for (int j = i + 1; j < kulupler.Length; j++)
                v.OyuncuEkle(kulupler[i], MinCevap, Kademe.Bilinen, kulupler[j]);

        Assert.Null(v.Sec(1, Zorluk.Kolay));
    }

    [Fact]
    public void Sec_UygunMilliTakimYoksa_OrtaIcinNullDoner()
    {
        var veri = ZenginVeri();
        // Sadece zor seviyenin milli takımları kalsın
        veri.MilliKariyer.RemoveAll(m => OrtaMilliTakimlar.ContainsKey(m.MilliTakimTmId));

        Assert.Null(veri.Sec(1, Zorluk.Orta));
    }
}
