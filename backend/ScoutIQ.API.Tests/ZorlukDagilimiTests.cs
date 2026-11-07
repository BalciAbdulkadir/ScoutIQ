using ScoutIQ.API.Oyunlar;
using static ScoutIQ.API.Oyunlar.ZorlukDagilimi;

namespace ScoutIQ.API.Tests;

public class ZorlukDagilimiTests
{
    [Theory]
    [InlineData(Zorluk.Kolay, 5, 5, 0, 0)]
    [InlineData(Zorluk.Orta, 5, 3, 2, 0)]
    [InlineData(Zorluk.Zor, 5, 2, 2, 1)]
    [InlineData(Zorluk.Kolay, 9, 9, 0, 0)]
    [InlineData(Zorluk.Orta, 9, 5, 4, 0)]
    [InlineData(Zorluk.Zor, 9, 4, 3, 2)]
    [InlineData(Zorluk.Kolay, 10, 10, 0, 0)]
    [InlineData(Zorluk.Orta, 10, 5, 5, 0)]
    [InlineData(Zorluk.Zor, 10, 4, 3, 3)]
    public void Dagit_YuzdeleriKolayaYuvarlar(Zorluk zorluk, int adet, int unlu, int bilinen, int diger)
    {
        var dagilim = Dagit(zorluk, adet);

        Assert.Equal(unlu, dagilim.GetValueOrDefault(Kademe.Unlu));
        Assert.Equal(bilinen, dagilim.GetValueOrDefault(Kademe.Bilinen));
        Assert.Equal(diger, dagilim.GetValueOrDefault(Kademe.Diger));
    }

    [Fact]
    public void Dagit_ToplamHepAdeteEsit()
    {
        foreach (var zorluk in Enum.GetValues<Zorluk>())
            for (int adet = 0; adet <= 20; adet++)
                Assert.Equal(adet, Dagit(zorluk, adet).Values.Sum());
    }

    [Fact]
    public void Dagit_KolaydaSadeceUnlu_OrtadaDigerYok()
    {
        Assert.Equal(new[] { Kademe.Unlu }, Dagit(Zorluk.Kolay, 9).Where(d => d.Value > 0).Select(d => d.Key));
        Assert.DoesNotContain(Dagit(Zorluk.Orta, 9), d => d.Key == Kademe.Diger && d.Value > 0);
    }

    [Theory]
    [InlineData("unlu", null, Kademe.Unlu)]
    [InlineData("bilinen", null, Kademe.Bilinen)]
    [InlineData("diger", null, Kademe.Diger)]
    [InlineData("diger", "unlu", Kademe.Unlu)]
    [InlineData(null, "bilinen", Kademe.Bilinen)]
    public void Coz_ElleDuzeltmeOncelikli(string? kademe, string? kademeOverride, Kademe beklenen) =>
        Assert.Equal(beklenen, Coz(kademe, kademeOverride));

    [Theory]
    [InlineData("cevap", null)]
    [InlineData(null, null)]
    [InlineData("unlu", "cevap")]
    public void Coz_HavuzDisindaysaNull(string? kademe, string? kademeOverride) =>
        Assert.Null(Coz(kademe, kademeOverride));

    [Fact]
    public void EnBilinen_EnBilinenCevabinKademesiniVerir()
    {
        var kademeler = new Dictionary<string, Kademe> { ["a"] = Kademe.Diger, ["b"] = Kademe.Bilinen, ["c"] = Kademe.Unlu };

        Assert.Equal(Kademe.Unlu, EnBilinen(new[] { "a", "b", "c" }, kademeler));
        Assert.Equal(Kademe.Bilinen, EnBilinen(new[] { "a", "b", "havuz-disi" }, kademeler));
        Assert.Equal(Kademe.Diger, EnBilinen(new[] { "a" }, kademeler));
        Assert.Null(EnBilinen(new[] { "havuz-disi" }, kademeler));
        Assert.Null(EnBilinen(Array.Empty<string>(), kademeler));
    }

    [Fact]
    public void YedekSirasi_HicbirZamanDahaZorKademeyeDusmez()
    {
        foreach (var istenen in Enum.GetValues<Kademe>())
        {
            Assert.Equal(istenen, YedekSirasi(istenen)[0]);
            Assert.All(YedekSirasi(istenen), k => Assert.True(k <= istenen));
        }
    }

    [Fact]
    public void OyunTipi_OyunVeZorluktanOlusur()
    {
        Assert.Equal("kesisim_kolay", OyunTipi("kesisim", Zorluk.Kolay));
        Assert.Equal("bonservis_orta", OyunTipi("bonservis", Zorluk.Orta));
        Assert.Equal("izgara_zor", OyunTipi("izgara", Zorluk.Zor));
    }
}
