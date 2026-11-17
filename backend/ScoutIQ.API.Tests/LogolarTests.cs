using ScoutIQ.API.Oyunlar;

namespace ScoutIQ.API.Tests;

public class LogolarTests
{
    // Milli takım isimleri ve oyuncu uyrukları farklı yazılabilir; ikisi de aynı bayrağı bulur
    [Theory]
    [InlineData("Turkiye", "tr")]
    [InlineData("Türkiye", "tr")]
    [InlineData("Ivory Coast", "ci")]
    [InlineData("Cote d'Ivoire", "ci")]
    [InlineData("Czechia", "cz")]
    [InlineData("Czech Republic", "cz")]
    [InlineData("Czechoslovakia (-1993)", "cz")]
    [InlineData("South Korea", "kr")]
    [InlineData("Korea, South", "kr")]
    [InlineData("Republic of Ireland", "ie")]
    [InlineData("Ireland", "ie")]
    [InlineData("DR Congo", "cd")]
    [InlineData("Spain", "es")]
    [InlineData("England", "gb-eng")]
    public void Bayrak_flagcdn(string ulke, string kod)
    {
        Assert.Equal($"https://flagcdn.com/w160/{kod}.png", Logolar.Bayrak(ulke));
    }

    // Artık olmayan ülkelerin bayrağı uygulamanın içindeki dosyadır
    [Theory]
    [InlineData("Yugoslavia", "yugoslavya")]
    [InlineData("Soviet Union (-1991)", "sovyetler_birligi")]
    [InlineData("East Germany", "dogu_almanya")]
    [InlineData("Serbia and Montenegro", "sirbistan_karadag")]
    [InlineData("Netherlands Antilles", "hollanda_antilleri")]
    [InlineData("Zaire", "zaire")]
    public void Bayrak_eski_ulke(string ulke, string dosya)
    {
        Assert.Equal($"asset:assets/bayraklar/{dosya}.png", Logolar.Bayrak(ulke));
    }

    [Fact]
    public void Bayrak_bilinmeyen_ulke_null()
    {
        Assert.Null(Logolar.Bayrak("Atlantis"));
    }

    // Backend'in gösterdiği her uygulama bayrağı mobil uygulamada gerçekten var
    [Fact]
    public void Eski_ulke_bayrak_dosyalari_uygulamada_var()
    {
        var kok = Directory.GetCurrentDirectory();
        while (kok != null && !Directory.Exists(Path.Combine(kok, "mobile"))) kok = Path.GetDirectoryName(kok);
        Assert.NotNull(kok);
        foreach (var ulke in new[] { "Yugoslavia", "Soviet Union (-1991)", "East Germany", "Serbia and Montenegro", "Netherlands Antilles", "Zaire" })
        {
            var yol = Logolar.Bayrak(ulke)!["asset:".Length..];
            Assert.True(File.Exists(Path.Combine(kok!, "mobile", yol)), yol);
        }
    }
}
