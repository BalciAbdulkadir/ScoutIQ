using ScoutIQ.API.Oyunlar;
using static ScoutIQ.API.Oyunlar.BonservisSoruSecici;

namespace ScoutIQ.API.Tests;

public class BonservisSoruSeciciTests
{
    private const long M = 1_000_000;

    private static Aday Oyuncu(int no, long milyon) => new($"oyuncu-{no}", $"Oyuncu {no}", milyon * M);

    // 6 ile 200 milyon arasında, kurallara uyan pek çok ikili kurulabilen bir havuz
    private static List<Aday> GenisHavuz()
    {
        var havuz = new List<Aday>();
        for (int i = 0; i < 120; i++)
        {
            havuz.Add(Oyuncu(i, 6 + i * 3 / 2));
        }
        return havuz;
    }

    [Theory]
    [InlineData(1)]
    [InlineData(2)]
    [InlineData(3)]
    [InlineData(42)]
    [InlineData(2026)]
    public void Bes_soru_ve_on_farkli_oyuncu_secer(int tohum)
    {
        var sorular = new BonservisSoruSecici(new Random(tohum)).Sec(GenisHavuz());

        Assert.NotNull(sorular);
        Assert.Equal(SoruSayisi, sorular!.Count);

        var oyuncular = sorular.SelectMany(s => new[] { s.Sol.Id, s.Sag.Id }).Distinct().Count();
        Assert.Equal(SoruSayisi * 2, oyuncular);
    }

    [Theory]
    [InlineData(1)]
    [InlineData(7)]
    [InlineData(99)]
    public void Her_soruda_fark_sifirdan_buyuk_ve_en_fazla_30_milyon(int tohum)
    {
        var sorular = new BonservisSoruSecici(new Random(tohum)).Sec(GenisHavuz())!;

        foreach (var s in sorular)
        {
            long fark = Math.Abs(s.Sol.ToplamBonservis - s.Sag.ToplamBonservis);
            Assert.InRange(fark, 1, MaxFark);
        }
    }

    [Fact]
    public void Dogru_cevap_bazen_solda_bazen_sagda_olur()
    {
        var taraflar = Enumerable.Range(0, 20)
            .SelectMany(tohum => new BonservisSoruSecici(new Random(tohum)).Sec(GenisHavuz())!)
            .Select(s => s.Dogru == s.Sol)
            .ToList();

        Assert.Contains(true, taraflar);
        Assert.Contains(false, taraflar);
    }

    [Fact]
    public void Dogru_cevap_toplam_bonservisi_fazla_olandir()
    {
        var pahali = Oyuncu(1, 50);
        var ucuz = Oyuncu(2, 40);

        Assert.Equal(pahali, new BonservisSorusu(pahali, ucuz).Dogru);
        Assert.Equal(pahali, new BonservisSorusu(ucuz, pahali).Dogru);
    }

    [Fact]
    public void Bes_milyon_ve_alti_oyuncular_soruda_cikmaz()
    {
        var havuz = GenisHavuz();
        havuz.Add(new Aday("ucuz-1", "Ucuz 1", 5 * M));
        havuz.Add(new Aday("ucuz-2", "Ucuz 2", 3 * M));
        havuz.Add(new Aday("ucuz-3", "Ucuz 3", 0));

        for (int tohum = 0; tohum < 20; tohum++)
        {
            var sorular = new BonservisSoruSecici(new Random(tohum)).Sec(havuz)!;
            Assert.All(sorular, s =>
            {
                Assert.True(s.Sol.ToplamBonservis > MinToplamBonservis);
                Assert.True(s.Sag.ToplamBonservis > MinToplamBonservis);
            });
        }
    }

    [Fact]
    public void Esit_toplamli_oyuncular_eslesmez()
    {
        Assert.False(Eslesebilir(Oyuncu(1, 40), Oyuncu(2, 40)));
        Assert.True(Eslesebilir(Oyuncu(1, 40), Oyuncu(2, 41)));
    }

    [Fact]
    public void Otuz_milyon_sinir_dahildir_fazlasi_eslesmez()
    {
        Assert.True(Eslesebilir(Oyuncu(1, 10), Oyuncu(2, 40)));
        Assert.False(Eslesebilir(new Aday("a", "A", 10 * M), new Aday("b", "B", 40 * M + 1)));
    }

    [Fact]
    public void Ayni_oyuncu_havuzda_iki_kez_olsa_da_bir_kez_kullanilir()
    {
        var havuz = GenisHavuz();
        havuz.AddRange(GenisHavuz());

        var sorular = new BonservisSoruSecici(new Random(3)).Sec(havuz)!;

        var oyuncular = sorular.SelectMany(s => new[] { s.Sol.Id, s.Sag.Id }).Distinct().Count();
        Assert.Equal(SoruSayisi * 2, oyuncular);
    }

    [Fact]
    public void Ayni_tohumla_ayni_sorular_cikar()
    {
        var a = new BonservisSoruSecici(new Random(77)).Sec(GenisHavuz())!;
        var b = new BonservisSoruSecici(new Random(77)).Sec(GenisHavuz())!;

        Assert.Equal(a, b);
    }

    [Fact]
    public void Esi_olmayan_oyuncuyu_atlayip_diger_ikilileri_kurar()
    {
        // 300 milyonluk oyuncunun 30 milyon aralığında eşi yok, soruda çıkmamalı.
        // Geri kalanlar 10'ar milyon arayla dizili, 5 ikili onlardan kurulur.
        var havuz = new List<Aday> { Oyuncu(0, 300) };
        for (int i = 1; i <= 10; i++)
        {
            havuz.Add(Oyuncu(i, 10 * i));
        }

        for (int tohum = 0; tohum < 20; tohum++)
        {
            var sorular = new BonservisSoruSecici(new Random(tohum)).Sec(havuz);
            Assert.NotNull(sorular);
            Assert.DoesNotContain(sorular!, s => s.Sol.Id == "oyuncu-0" || s.Sag.Id == "oyuncu-0");
        }
    }

    [Fact]
    public void Kurallara_uyan_bes_ikili_yoksa_null_doner()
    {
        // Oyuncular arasında hep 40 milyon fark var: hiçbir ikili eşleşemez
        var havuz = Enumerable.Range(1, 20).Select(i => Oyuncu(i, 40 * i)).ToList();

        Assert.Null(new BonservisSoruSecici(new Random(1)).Sec(havuz));
    }

    [Fact]
    public void On_oyuncudan_az_havuzda_null_doner()
    {
        var havuz = Enumerable.Range(1, 9).Select(i => Oyuncu(i, 10 + i)).ToList();

        Assert.Null(new BonservisSoruSecici(new Random(1)).Sec(havuz));
    }

    [Fact]
    public void Bos_havuzda_null_doner()
    {
        Assert.Null(new BonservisSoruSecici(new Random(1)).Sec(new List<Aday>()));
    }

    [Fact]
    public void Kulup_listesinde_29_kulup_var()
    {
        Assert.Equal(29, Kulupler.Count);
    }
}
