using ScoutIQ.API.Models;
using ScoutIQ.API.Oyunlar;
using static ScoutIQ.API.Oyunlar.Top10SoruSecici;

namespace ScoutIQ.API.Tests;

public class Top10SoruSeciciTests
{
    private static readonly DateTime Bugun = new(2026, 11, 15);

    // Testler için küçük bir futbol dünyası: kulüpler, oyuncular, transferler ve Ballon d'Or sıralamaları
    private sealed class TestVerisi
    {
        public List<Kulup> Kulupler { get; } = new();
        public List<Transfer> Transferler { get; } = new();
        public Dictionary<string, OyuncuBilgisi> Oyuncular { get; } = new();
        public Dictionary<string, Kademe> Kademeler { get; } = new();
        public List<BallonDorSatiri> BallonDor { get; } = new();
        public List<KulupSayisi> KulupSayilari { get; } = new();
        public List<Gecmis> Gecmis { get; } = new();
        private int _oyuncuNo;

        public Kulup Kulup(string tmId, string lig = "XX", string? kademe = KulupKademeleri.Buyuk)
        {
            var kulup = new Kulup { Id = $"kulup-{tmId}", TransfermarktId = tmId, Isim = tmId, Lig = lig, Kademe = kademe };
            Kulupler.Add(kulup);
            return kulup;
        }

        public string Oyuncu(Kademe? kademe = Kademe.Unlu, string uyruk = "Spain")
        {
            var id = $"oyuncu-{++_oyuncuNo:000}";
            Oyuncular[id] = new OyuncuBilgisi($"Oyuncu {_oyuncuNo}", uyruk);
            if (kademe != null) Kademeler[id] = kademe.Value;
            return id;
        }

        public void Transfer(string oyuncu, Kulup? eski, Kulup? yeni, long bedel, int yil = 2020, string? sezon = null) =>
            Transferler.Add(new Transfer(oyuncu, eski?.TransfermarktId, yeni?.TransfermarktId, new DateTime(yil, 7, 1),
                sezon ?? $"{yil % 100:00}/{(yil + 1) % 100:00}", bedel));

        public Veri Veri() => new(Kulupler, Transferler, Oyuncular, BallonDor, KulupSayilari);

        public SecimSonucu Sec(int tohum = 1, DateTime? bugun = null) =>
            new Top10SoruSecici(new Random(tohum)).Sec(bugun ?? Bugun, Veri(), Kademeler, Gecmis);
    }

    // Galatasaray'a (141) 12 oyuncu farklı bedellerle transfer olmuş; başka hiçbir şablon kurulamaz (kulüp 6 ligin dışında)
    private static (TestVerisi Veri, Kulup Gs, List<string> Oyuncular) TekKulup()
    {
        var v = new TestVerisi();
        var gs = v.Kulup("141");
        var disari = v.Kulup("999", lig: "XX", kademe: null);
        var oyuncular = new List<string>();
        for (int i = 0; i < 12; i++)
        {
            var o = v.Oyuncu(uyruk: $"Ulke{i}");
            oyuncular.Add(o);
            v.Transfer(o, disari, gs, (12 - i) * 1_000_000L, yil: 2010 + i, sezon: $"x{i}");
        }
        return (v, gs, oyuncular);
    }

    [Fact]
    public void Sec_KulubunEnPahaliTransferleri_SiraliVeDegerli()
    {
        var (v, _, oyuncular) = TekKulup();

        var soru = v.Sec().Soru;

        Assert.NotNull(soru);
        Assert.Equal("T1", soru!.Sablon);
        Assert.Equal("Galatasaray'ın en pahalı 10 transferi", soru.Baslik);
        Assert.Equal(Enumerable.Range(1, 10), soru.Satirlar.Select(s => s.Sira));
        Assert.Equal(oyuncular.Take(10), soru.Satirlar.Select(s => s.OyuncuId));
        Assert.Equal("12 M€", soru.Satirlar[0].Deger);
        Assert.Contains("2000'den bugüne", soru.AltBaslik);
    }

    [Fact]
    public void Sec_OyuncuBirdenFazlaKayitlaGecerse_EnYuksekKaydiSayilir()
    {
        var (v, gs, oyuncular) = TekKulup();
        var disari = v.Kulupler[1];
        // 12. oyuncu kulübe ikinci kez daha yüksek bedelle gelir: listede bir kez, en yüksek bedelle
        v.Transfer(oyuncular[11], disari, gs, 50_000_000L, yil: 2024, sezon: "y");

        var soru = v.Sec().Soru!;

        Assert.Equal(oyuncular[11], soru.Satirlar[0].OyuncuId);
        Assert.Equal(10, soru.Satirlar.Select(s => s.OyuncuId).Distinct().Count());
    }

    [Fact]
    public void Sec_OnuncuVeOnBirinciEsitse_SoruUretilmez()
    {
        var (v, gs, oyuncular) = TekKulup();
        var disari = v.Kulupler[1];
        // 11. oyuncunun bedeli 10. ile aynı olsun
        v.Transferler.RemoveAll(t => t.OyuncuId == oyuncular[10]);
        v.Transfer(oyuncular[10], disari, gs, 3_000_000L, yil: 2030, sezon: "z");

        Assert.Null(v.Sec().Soru);
    }

    [Fact]
    public void Sec_IlkOndaEsitlikte_EskiTarihliTransferUstte()
    {
        var (v, gs, oyuncular) = TekKulup();
        var disari = v.Kulupler[1];
        // 1. ve 2. oyuncu aynı bedelle: daha eski tarihli üstte
        v.Transferler.RemoveAll(t => t.OyuncuId == oyuncular[0] || t.OyuncuId == oyuncular[1]);
        v.Transfer(oyuncular[0], disari, gs, 20_000_000L, yil: 2022, sezon: "a");
        v.Transfer(oyuncular[1], disari, gs, 20_000_000L, yil: 2015, sezon: "b");

        var soru = v.Sec().Soru!;

        Assert.Equal(oyuncular[1], soru.Satirlar[0].OyuncuId);
        Assert.Equal(oyuncular[0], soru.Satirlar[1].OyuncuId);
    }

    [Fact]
    public void Sec_TaninanOyuncuAzsa_SoruUretilmez()
    {
        var (v, _, oyuncular) = TekKulup();
        // İlk 10'un 5'i havuz dışı: eşik 6
        foreach (var o in oyuncular.Take(5)) v.Kademeler.Remove(o);

        Assert.Null(v.Sec().Soru);

        // 4'ü havuz dışı: soru üretilir
        v.Kademeler[oyuncular[0]] = Kademe.Diger;
        Assert.Null(v.Sec().Soru);
        v.Kademeler[oyuncular[0]] = Kademe.Bilinen;
        Assert.NotNull(v.Sec().Soru);
    }

    [Fact]
    public void Sec_DokuzOyuncuVarsa_SoruUretilmez()
    {
        var (v, _, oyuncular) = TekKulup();
        v.Transferler.RemoveAll(t => t.OyuncuId == oyuncular[10] || t.OyuncuId == oyuncular[11] || t.OyuncuId == oyuncular[9]);

        Assert.Null(v.Sec().Soru);
    }

    [Fact]
    public void Sec_BaslangicYilindanOnceki_VeBedelsizTransferlerSayilmaz()
    {
        var (v, gs, oyuncular) = TekKulup();
        var disari = v.Kulupler[1];
        // 1999'daki rekor transfer ve bedelsiz transfer listeye girmez
        var eski = v.Oyuncu();
        v.Transfer(eski, disari, gs, 999_000_000L, yil: 1999, sezon: "c");
        var bedelsiz = v.Oyuncu();
        v.Transfer(bedelsiz, disari, gs, 0, yil: 2021, sezon: "d");

        var soru = v.Sec().Soru!;

        Assert.DoesNotContain(soru.Satirlar, s => s.OyuncuId == eski || s.OyuncuId == bedelsiz);
    }

    [Fact]
    public void Sec_BasAltiKulupKullanilir_DigerVeKademesizKullanilmaz()
    {
        foreach (var (kademe, beklenen) in new[] { (KulupKademeleri.BasAlti, true), ("diger", false), ((string?)null, false) })
        {
            var v = new TestVerisi();
            var kulup = v.Kulup("449", kademe: kademe);
            var disari = v.Kulup("999", lig: "XX", kademe: null);
            for (int i = 0; i < 11; i++) v.Transfer(v.Oyuncu(uyruk: $"U{i}"), disari, kulup, (11 - i) * 1_000_000L, yil: 2010 + i, sezon: $"s{i}");

            Assert.Equal(beklenen, v.Sec().Soru != null);
        }
    }

    [Fact]
    public void Sec_AyniSablonVeDegisken_YuzSeksenGunIcindeTekrarEtmez()
    {
        var (v, gs, _) = TekKulup();
        v.Gecmis.Add(new Gecmis("T1", gs.TransfermarktId, TransferEkseni, Bugun.AddDays(-(TekrarGunu - 1))));

        Assert.Null(v.Sec().Soru);

        v.Gecmis.Clear();
        v.Gecmis.Add(new Gecmis("T1", gs.TransfermarktId, TransferEkseni, Bugun.AddDays(-TekrarGunu)));
        Assert.NotNull(v.Sec().Soru);
    }

    // Transfer ve Ballon d'Or eksenleri ikisi de kurulabilir
    private static TestVerisi IkiEksen()
    {
        var (v, _, oyuncular) = TekKulup();
        for (int i = 0; i < 12; i++)
            v.BallonDor.Add(new BallonDorSatiri(2015, i + 1, oyuncular[i], 100 - i, null));
        return v;
    }

    [Fact]
    public void Sec_DunkuEksendenFarkliEksenSecilir()
    {
        var v = IkiEksen();
        v.Gecmis.Add(new Gecmis("T5", "x", TransferEkseni, Bugun.AddDays(-1)));

        for (int tohum = 0; tohum < 20; tohum++)
            Assert.Equal(BallonDorEkseni, v.Sec(tohum).Soru!.Eksen);

        v.Gecmis.Clear();
        v.Gecmis.Add(new Gecmis("B1", "1999", BallonDorEkseni, Bugun.AddDays(-1)));
        for (int tohum = 0; tohum < 20; tohum++)
            Assert.Equal(TransferEkseni, v.Sec(tohum).Soru!.Eksen);
    }

    [Fact]
    public void Sec_DigerEksendeSoruYoksa_AyniEksenKullanilir()
    {
        var (v, _, _) = TekKulup();
        v.Gecmis.Add(new Gecmis("T5", "x", TransferEkseni, Bugun.AddDays(-1)));

        var sonuc = v.Sec();

        Assert.NotNull(sonuc.Soru);
        Assert.Equal(TransferEkseni, sonuc.Soru!.Eksen);
    }

    [Fact]
    public void Sec_BallonDor_IlkOnVePuan()
    {
        var v = new TestVerisi();
        var oyuncular = Enumerable.Range(0, 12).Select(_ => v.Oyuncu()).ToList();
        for (int i = 0; i < 12; i++)
            v.BallonDor.Add(new BallonDorSatiri(2023, i + 1, oyuncular[i], 500 - i * 10, null));

        var soru = v.Sec().Soru!;

        Assert.Equal("B1", soru.Sablon);
        Assert.Equal("2023 Ballon d'Or sıralamasında ilk 10", soru.Baslik);
        Assert.Equal(oyuncular.Take(10), soru.Satirlar.Select(s => s.OyuncuId));
        Assert.Equal("500 puan", soru.Satirlar[0].Deger);
    }

    [Fact]
    public void Sec_BallonDor_IlkOndakiOyuncuVeritabanindaYoksa_YaDaOnuncuSiraEsitse_SoruUretilmez()
    {
        var v = new TestVerisi();
        var oyuncular = Enumerable.Range(0, 12).Select(_ => v.Oyuncu()).ToList();
        for (int i = 0; i < 12; i++)
            v.BallonDor.Add(new BallonDorSatiri(2023, i + 1, i == 4 ? null : oyuncular[i], 500 - i * 10, null));
        Assert.Null(v.Sec().Soru);

        v.BallonDor.Clear();
        // 10. ve 11. aynı sırada (eşit puan)
        for (int i = 0; i < 12; i++)
            v.BallonDor.Add(new BallonDorSatiri(2023, Math.Min(i + 1, 10), oyuncular[i], 500 - Math.Min(i, 9) * 10, null));
        Assert.Null(v.Sec().Soru);
    }

    [Fact]
    public void Sec_LiginEnPahaliTransferleri_LigdekiKuluplerdenKurulur()
    {
        var v = new TestVerisi();
        // Süper Lig'de 3 kulüp (biri kademesiz: lig sorusunda kulüp kademesine bakılmaz), dışarıdan 12 transfer
        var ligKulupleri = new[] { v.Kulup("141", "TR1"), v.Kulup("36", "TR1"), v.Kulup("7777", "TR1", kademe: null) };
        var disari = v.Kulup("999", kademe: null);
        var oyuncular = new List<string>();
        for (int i = 0; i < 12; i++)
        {
            var o = v.Oyuncu(uyruk: $"U{i}");
            oyuncular.Add(o);
            v.Transfer(o, disari, ligKulupleri[i % 3], (12 - i) * 1_000_000L, yil: 2010 + i, sezon: $"s{i}");
        }
        // Kulüp sorularını engelle: sadece lig sorusu kalsın
        v.Gecmis.Add(new Gecmis("T1", "141", TransferEkseni, Bugun.AddDays(-1)));
        v.Gecmis.Add(new Gecmis("T1", "36", TransferEkseni, Bugun.AddDays(-1)));

        var soru = v.Sec().Soru!;

        Assert.Equal("T3", soru.Sablon);
        Assert.Equal("Süper Lig'in en pahalı 10 transferi", soru.Baslik);
        Assert.Equal(oyuncular.Take(10), soru.Satirlar.Select(s => s.OyuncuId));
    }

    [Fact]
    public void Sec_HicSoruYoksa_NullVeUyari()
    {
        var sonuc = new TestVerisi().Sec();

        Assert.Null(sonuc.Soru);
        Assert.NotEmpty(sonuc.Uyarilar);
    }

    [Theory]
    [InlineData("18/19", 2018, "2018/19")]
    [InlineData("99/00", 1999, "1999/00")]
    [InlineData("00/01", 2000, "2000/01")]
    public void Sezon_YilVeAd(string sezon, int yil, string ad)
    {
        Assert.Equal(yil, SezonYili(sezon));
        Assert.Equal(ad, SezonAdi(sezon));
    }

    [Theory]
    [InlineData(222_000_000L, "222 M€")]
    [InlineData(7_500_000L, "7,5 M€")]
    [InlineData(850_000L, "0,85 M€")]
    public void Milyon_Bicim(long euro, string metin) => Assert.Equal(metin, Milyon(euro));

    [Fact]
    public void KulupIyelik_KesisiminBuyukVeBasAltiKulupleriniKapsar()
    {
        Assert.All(KesisimSoruSecici.Kulupler.Keys.Where(id => id is not "1050" and not "681"),
            id => Assert.True(KulupIyelik.ContainsKey(id), $"İyelik hali eksik: {KesisimSoruSecici.Kulupler[id]}"));
    }
}
