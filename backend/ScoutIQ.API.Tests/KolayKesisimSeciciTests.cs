using ScoutIQ.API.Models;
using ScoutIQ.API.Oyunlar;
using static ScoutIQ.API.Oyunlar.KolayKesisimSecici;

namespace ScoutIQ.API.Tests;

public class KolayKesisimSeciciTests
{
    private static readonly DateTime Bugun = new(2026, 11, 15);

    // Testler için küçük bir futbol dünyası: kulüpler, oyuncular ve önceki günlerin soruları
    private sealed class TestVerisi
    {
        public List<Kulup> Kulupler { get; } = new();
        public List<KariyerGecmisi> Kariyer { get; } = new();
        public Dictionary<string, Kademe> Kademeler { get; } = new();
        public List<Gecmis> Gecmis { get; } = new();
        private int _oyuncuNo;

        public Kulup Kulup(string ad, string? kademe = KulupKademeleri.Buyuk)
        {
            var kulup = new Kulup { Id = $"kulup-{ad}", TransfermarktId = ad, Isim = ad, Lig = "XX", Kademe = kademe };
            Kulupler.Add(kulup);
            return kulup;
        }

        // Verilen kulüplerin hepsinde oynamış yeni bir oyuncu ekler ve ID'sini döndürür. kademe null: havuz dışı.
        public string Oyuncu(Kademe? kademe, int macSayisi, params Kulup[] kulupler)
        {
            var id = $"oyuncu-{++_oyuncuNo:000}";
            foreach (var k in kulupler)
                Kariyer.Add(new KariyerGecmisi { OyuncuId = id, KulupId = k.Id, MacSayisi = macSayisi });
            if (kademe != null) Kademeler[id] = kademe.Value;
            return id;
        }

        public string Unlu(params Kulup[] kulupler) => Oyuncu(Kademe.Unlu, 50, kulupler);

        public SecimSonucu Sec(int tohum, DateTime? bugun = null) =>
            new KolayKesisimSecici(new Random(tohum)).Sec(bugun ?? Bugun, Kulupler, Kariyer, Kademeler, Gecmis);

        public HashSet<string> BuyukKulupleri(string oyuncuId) => Kariyer
            .Where(k => k.OyuncuId == oyuncuId && k.SoruyaUygun && Kulupler.Any(ku => ku.Id == k.KulupId && ku.Kademe == KulupKademeleri.Buyuk))
            .Select(k => k.KulupId).ToHashSet();
    }

    // 12 büyük kulüp; her komşu üçlüde oynamış ünlü oyuncular (bol hedef, bol çift) ve tuzaklar
    private static TestVerisi ZenginVeri()
    {
        var v = new TestVerisi();
        var buyukler = Enumerable.Range(0, 12).Select(i => v.Kulup($"b{i:00}")).ToList();
        var basAlti = v.Kulup("basalti", KulupKademeleri.BasAlti);
        var diger = v.Kulup("diger", "diger");
        var kademesiz = v.Kulup("kademesiz", null);

        for (int i = 0; i < buyukler.Count; i++)
        {
            for (int j = i + 1; j < buyukler.Count; j++)
            {
                v.Unlu(buyukler[i], buyukler[j]);
                if ((i + j) % 4 == 0) v.Unlu(buyukler[i], buyukler[j], buyukler[(j + 1) % buyukler.Count]);
            }
            // Tuzaklar: hedef olmamalı
            v.Unlu(buyukler[i]);                                     // tek büyük kulüp
            v.Unlu(buyukler[i], basAlti, diger, kademesiz);          // diğer kulüpleri büyük değil
            v.Oyuncu(Kademe.Bilinen, 50, buyukler[i], buyukler[(i + 1) % buyukler.Count]);   // ünlü değil
            v.Oyuncu(null, 50, buyukler[i], buyukler[(i + 2) % buyukler.Count]);             // havuz dışı
            v.Oyuncu(Kademe.Unlu, KariyerGecmisi.MinSoruMaci - 1, buyukler[i], buyukler[(i + 3) % buyukler.Count]);   // az maç
        }
        return v;
    }

    public static IEnumerable<object[]> Tohumlar() => Enumerable.Range(0, 40).Select(t => new object[] { t });

    [Theory]
    [MemberData(nameof(Tohumlar))]
    public void Sec_HerTohumda_TumKurallaraUyar(int tohum)
    {
        var veri = ZenginVeri();

        var sonuc = veri.Sec(tohum);

        Assert.NotNull(sonuc.Sorular);
        Assert.Empty(sonuc.Uyarilar);
        var sorular = sonuc.Sorular!;
        Assert.Equal(SoruSayisi, sorular.Count);

        foreach (var s in sorular)
        {
            // İki kulüp de büyük ve hedef oyuncu ikisinde de yeterince oynamış ünlü bir oyuncu
            Assert.Equal(KulupKademeleri.Buyuk, s.KulupA.Kademe);
            Assert.Equal(KulupKademeleri.Buyuk, s.KulupB.Kademe);
            Assert.NotEqual(s.KulupA.Id, s.KulupB.Id);
            Assert.Equal(Kademe.Unlu, veri.Kademeler[s.HedefOyuncuId]);
            var kulupleri = veri.BuyukKulupleri(s.HedefOyuncuId);
            Assert.Contains(s.KulupA.Id, kulupleri);
            Assert.Contains(s.KulupB.Id, kulupleri);

            // Ortak oyuncu sayısı: iki kulüpte de kaydı olan herkes (cevap olarak kabul edilenler)
            var a = veri.Kariyer.Where(k => k.KulupId == s.KulupA.Id).Select(k => k.OyuncuId).ToHashSet();
            var b = veri.Kariyer.Where(k => k.KulupId == s.KulupB.Id).Select(k => k.OyuncuId).ToHashSet();
            Assert.Equal(a.Intersect(b).Count(), s.OrtakOyuncuSayisi);
        }

        // Bir oyunda aynı kulüp iki kez çıkmaz, aynı oyuncu iki soruya hedef olmaz
        var kulupler = sorular.SelectMany(s => new[] { s.KulupA.Id, s.KulupB.Id }).ToList();
        Assert.Equal(kulupler.Count, kulupler.Distinct().Count());
        Assert.Equal(SoruSayisi, sorular.Select(s => s.HedefOyuncuId).Distinct().Count());
    }

    [Fact]
    public void Sec_AyniTohumla_AyniSorulariSecer()
    {
        var veri = ZenginVeri();

        var ilk = veri.Sec(7).Sorular!;
        var ikinci = veri.Sec(7).Sorular!;

        Assert.Equal(ilk.Select(s => (s.KulupA.Id, s.KulupB.Id, s.HedefOyuncuId)), ikinci.Select(s => (s.KulupA.Id, s.KulupB.Id, s.HedefOyuncuId)));
    }

    [Fact]
    public void Sec_GunlerBoyunca_HedefOyuncuVeCiftTekrarEtmez()
    {
        var veri = ZenginVeri();
        var hedefler = new HashSet<string>();
        var ciftGunleri = new Dictionary<(string, string), DateTime>();

        // 8 gün: 40 soru. Veride daha fazla hedef ve çift var, hiçbiri tekrar etmemeli
        for (int gun = 0; gun < 8; gun++)
        {
            var tarih = Bugun.AddDays(gun);
            var sonuc = veri.Sec(gun, tarih);
            Assert.NotNull(sonuc.Sorular);
            Assert.Empty(sonuc.Uyarilar);

            foreach (var s in sonuc.Sorular!)
            {
                Assert.True(hedefler.Add(s.HedefOyuncuId), $"{s.HedefOyuncuId} ikinci kez hedef oldu");

                var cift = Cift(s.KulupA.Id, s.KulupB.Id);
                if (ciftGunleri.TryGetValue(cift, out var son))
                    Assert.True((tarih - son).Days >= CiftTekrarGunu, $"{cift} çifti {(tarih - son).Days} gün sonra tekrar soruldu");
                ciftGunleri[cift] = tarih;

                veri.Gecmis.Add(new Gecmis(s.HedefOyuncuId, s.KulupA.Id, s.KulupB.Id, tarih));
            }
        }
    }

    [Fact]
    public void Sec_CiftSirasiz_TersSiraylaKaydedilenCiftDeTekrarSayilir()
    {
        var v = new TestVerisi();
        var k = Enumerable.Range(0, 10).Select(i => v.Kulup($"b{i}")).ToList();
        // Her kulüp çiftinde bir ünlü; 0-1 çifti dün ters sırayla sorulmuş
        for (int i = 0; i < k.Count; i++)
            for (int j = i + 1; j < k.Count; j++)
                v.Unlu(k[i], k[j]);
        v.Gecmis.Add(new Gecmis("baska-oyuncu", k[1].Id, k[0].Id, Bugun.AddDays(-1)));

        for (int tohum = 0; tohum < 30; tohum++)
        {
            var sorular = v.Sec(tohum).Sorular!;
            Assert.DoesNotContain(sorular, s => Cift(s.KulupA.Id, s.KulupB.Id) == Cift(k[0].Id, k[1].Id));
        }
    }

    [Fact]
    public void Sec_CiftSuresiDolunca_TekrarSorulabilir()
    {
        var v = new TestVerisi();
        var k = Enumerable.Range(0, 10).Select(i => v.Kulup($"b{i}")).ToList();
        // Tam 5 ayrık çift var: hepsi CiftTekrarGunu gün önce sorulmuş, bugün yeniden sorulabilir
        for (int i = 0; i < 5; i++)
        {
            v.Unlu(k[2 * i], k[2 * i + 1]);
            v.Gecmis.Add(new Gecmis("baska-oyuncu", k[2 * i].Id, k[2 * i + 1].Id, Bugun.AddDays(-CiftTekrarGunu)));
        }

        var sonuc = v.Sec(1);

        Assert.NotNull(sonuc.Sorular);
        Assert.Empty(sonuc.Uyarilar);
    }

    [Fact]
    public void Sec_UygunCiftKalmazsa_KuralEsnetilir_EnEskiCiftSecilir()
    {
        var v = new TestVerisi();
        var k = Enumerable.Range(0, 10).Select(i => v.Kulup($"b{i}")).ToList();
        // Tam 5 ayrık çift var ve hepsi son günlerde sorulmuş: kural esnemezse soru kurulamaz
        for (int i = 0; i < 5; i++)
        {
            v.Unlu(k[2 * i], k[2 * i + 1]);
            v.Gecmis.Add(new Gecmis("baska-oyuncu", k[2 * i].Id, k[2 * i + 1].Id, Bugun.AddDays(-1 - i)));
        }

        var sonuc = v.Sec(1);

        Assert.NotNull(sonuc.Sorular);
        Assert.Equal(SoruSayisi, sonuc.Sorular!.Count);
        Assert.Contains(sonuc.Uyarilar, u => u.Contains("esnetildi"));
    }

    [Fact]
    public void Sec_HavuzBitince_EnUzunSuredirHedefOlmayanlarTekrarEder()
    {
        var v = new TestVerisi();
        var k = Enumerable.Range(0, 12).Select(i => v.Kulup($"b{i:00}")).ToList();
        // 6 ayrık çift, her birinde tek hedef; hepsi daha önce hedef olmuş (çiftler başka kulüplerle sorulmuş sayılır)
        var hedefler = new List<string>();
        for (int i = 0; i < 6; i++)
        {
            var id = v.Unlu(k[2 * i], k[2 * i + 1]);
            hedefler.Add(id);
            v.Gecmis.Add(new Gecmis(id, "eski-kulup-a", "eski-kulup-b", Bugun.AddDays(-100 + i)));
        }

        var sonuc = v.Sec(1);

        // En son hedef olan (6.) oyuncu dışarıda kalır, en eski 5 oyuncu tekrar eder
        Assert.NotNull(sonuc.Sorular);
        Assert.Equal(hedefler.Take(5).ToHashSet(), sonuc.Sorular!.Select(s => s.HedefOyuncuId).ToHashSet());
        Assert.Contains(sonuc.Uyarilar, u => u.Contains("daha önce hedef olmuş"));
        Assert.Equal(0, sonuc.KullanilmamisHedefSayisi);
    }

    [Fact]
    public void Sec_KullanilmamisHedefVarken_KullanilmisHedefSecilmez()
    {
        var veri = ZenginVeri();
        // Hedeflerin yarısı daha önce kullanılmış olsun
        var ilkGun = veri.Sec(1).Sorular!;
        foreach (var s in ilkGun)
            veri.Gecmis.Add(new Gecmis(s.HedefOyuncuId, "eski-kulup-a", "eski-kulup-b", Bugun.AddDays(-50)));
        var kullanilmis = ilkGun.Select(s => s.HedefOyuncuId).ToHashSet();

        for (int tohum = 0; tohum < 30; tohum++)
            Assert.DoesNotContain(veri.Sec(tohum).Sorular!, s => kullanilmis.Contains(s.HedefOyuncuId));
    }

    [Fact]
    public void Sec_AyniOyuncuKulupEslesmesiBirdenFazlaGecerse_TekSayilir()
    {
        var v = new TestVerisi();
        var k = Enumerable.Range(0, 10).Select(i => v.Kulup($"b{i}")).ToList();
        for (int i = 0; i < 5; i++)
            v.Unlu(k[2 * i], k[2 * i + 1]);
        // Kulübe iki kez gelmiş (kiralık dönüşü) ama başka büyük kulübü olmayan ünlü: hedef olamaz
        var tekKulup = v.Unlu(k[0], k[0]);

        var sonuc = v.Sec(1);

        Assert.Equal(5, sonuc.HedefSayisi);
        Assert.DoesNotContain(sonuc.Sorular!, s => s.HedefOyuncuId == tekKulup);
    }

    [Fact]
    public void Sec_YeterliHedefYoksa_NullDoner()
    {
        var v = new TestVerisi();
        var k = Enumerable.Range(0, 10).Select(i => v.Kulup($"b{i}")).ToList();
        // Sadece 4 çift kurulabiliyor
        for (int i = 0; i < 4; i++)
            v.Unlu(k[2 * i], k[2 * i + 1]);

        var sonuc = v.Sec(1);

        Assert.Null(sonuc.Sorular);
        Assert.NotEmpty(sonuc.Uyarilar);
    }

    [Fact]
    public void CiftTekrarGunu_YirmiBirGun()
    {
        Assert.Equal(21, CiftTekrarGunu);
        Assert.Equal(5, SoruSayisi);
    }
}
