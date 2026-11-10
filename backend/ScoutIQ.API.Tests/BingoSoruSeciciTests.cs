using ScoutIQ.API.Oyunlar;
using static ScoutIQ.API.Oyunlar.BingoSoruSecici;

namespace ScoutIQ.API.Tests;

public class BingoSoruSeciciTests
{
    // Testler için küçük bir futbol dünyası: kategoriler ve onlara uyan oyuncular
    private sealed class TestVerisi
    {
        public Dictionary<Kategori, (HashSet<string> Oyuncular, HashSet<string> Oynayanlar)> Kategoriler { get; } = new();
        public Dictionary<string, Kademe> Kademeler { get; } = new();
        private int _oyuncuNo;

        public Kategori Kategori(KategoriTipi tip, string anahtar)
        {
            var k = new Kategori(tip, anahtar, $"{tip} {anahtar}");
            Kategoriler[k] = (new HashSet<string>(), new HashSet<string>());
            return k;
        }

        // Verilen kategorilerin hepsine uyan "adet" kadar yeni oyuncu ekler. kademe null: havuz dışı.
        // oynadi false: kategoride kaydı var ama maça çıkmamış (sadece cevap olarak kabul edilir).
        public void OyuncuEkle(int adet, Kademe? kademe, bool oynadi, params Kategori[] kategoriler)
        {
            for (int i = 0; i < adet; i++)
            {
                var id = $"oyuncu-{++_oyuncuNo}";
                foreach (var k in kategoriler)
                {
                    Kategoriler[k].Oyuncular.Add(id);
                    if (oynadi) Kategoriler[k].Oynayanlar.Add(id);
                }
                if (kademe != null) Kademeler[id] = kademe.Value;
            }
        }

        public List<Aday> Adaylar() => Kategoriler.Select(k => new Aday(k.Key, k.Value.Oyuncular, k.Value.Oynayanlar)).ToList();

        public BingoKarti? Sec(int tohum) => new BingoSoruSecici(new Random(tohum)).Sec(Adaylar(), Kademeler);
    }

    // Her tipten fazlasıyla kategori; her kategoride her kademeden oyuncu, bazıları iki kategoriye birden uyar
    private static TestVerisi ZenginVeri()
    {
        var v = new TestVerisi();
        var kategoriler = new List<Kategori>();
        for (int i = 0; i < 9; i++) kategoriler.Add(v.Kategori(KategoriTipi.Kulup, $"k{i}"));
        for (int i = 0; i < 6; i++) kategoriler.Add(v.Kategori(KategoriTipi.Milli, $"m{i}"));
        for (int i = 0; i < 3; i++) kategoriler.Add(v.Kategori(KategoriTipi.Lig, $"l{i}"));
        for (int i = 0; i < 6; i++) kategoriler.Add(v.Kategori(KategoriTipi.Basari, $"b{i}"));

        for (int i = 0; i < kategoriler.Count; i++)
        {
            foreach (var kademe in Enum.GetValues<Kademe>())
            {
                v.OyuncuEkle(3, kademe, true, kategoriler[i]);
                v.OyuncuEkle(1, kademe, true, kategoriler[i], kategoriler[(i + 5) % kategoriler.Count]);
            }
            // Tuzaklar: havuz dışı oyuncu ve maça çıkmamış ünlü oyuncu desteye girmemeli
            v.OyuncuEkle(2, null, true, kategoriler[i]);
            v.OyuncuEkle(1, Kademe.Unlu, false, kategoriler[i]);
        }
        return v;
    }

    public static IEnumerable<object[]> Tohumlar() => Enumerable.Range(0, 60).Select(t => new object[] { t });

    [Theory]
    [MemberData(nameof(Tohumlar))]
    public void Sec_HerTohumda_TumKurallaraUyar(int tohum)
    {
        var veri = ZenginVeri();

        var kart = veri.Sec(tohum);

        Assert.NotNull(kart);
        Assert.Equal(HucreSayisi, kart!.Hucreler.Count);
        Assert.Equal(HucreSayisi, kart.Hucreler.Distinct().Count());
        foreach (var (tip, adet) in KartDagilimi)
            Assert.Equal(adet, kart.Hucreler.Count(h => h.Tip == tip));

        // Deste: 32 farklı havuz oyuncusu, sadece ünlü ve bilinen; az bilinen (diğer) oyuncu yok
        Assert.Equal(DesteBoyutu, kart.Deste.Count);
        Assert.Equal(DesteBoyutu, kart.Deste.Distinct().Count());
        Assert.All(kart.Deste, o => Assert.True(veri.Kademeler.ContainsKey(o), $"Havuz dışı oyuncu destede: {o}"));
        Assert.All(kart.Deste, o => Assert.NotEqual(Kademe.Diger, veri.Kademeler[o]));

        // Eşleşmeler doğru: oyuncunun uyduğu bütün kutular, sadece onlar
        for (int i = 0; i < DesteBoyutu; i++)
        {
            var beklenen = Enumerable.Range(0, HucreSayisi).Where(h => veri.Kategoriler[kart.Hucreler[h]].Oyuncular.Contains(kart.Deste[i]));
            Assert.Equal(beklenen, kart.Eslesmeler[i]);
        }

        // Kutuya uymayan oyuncu az: tam UymayanSayisi kadar
        Assert.Equal(UymayanSayisi, kart.Eslesmeler.Count(e => e.Length == 0));

        // Kart doldurulabilir: her kutuya desteden ayrı bir oyuncu atanabilir
        Assert.True(TamEslesmeVar(kart), "Kart desteden doldurulamıyor");
    }

    // Kutular ile oyuncular arasında herkese ayrı oyuncu düşen bir eşleşme var mı (artırımlı yol)
    private static bool TamEslesmeVar(BingoKarti kart)
    {
        var kutununOyuncusu = new int?[HucreSayisi];
        bool Yerlestir(int oyuncu, HashSet<int> gezilen)
        {
            foreach (var h in kart.Eslesmeler[oyuncu])
            {
                if (!gezilen.Add(h)) continue;
                if (kutununOyuncusu[h] == null || Yerlestir(kutununOyuncusu[h]!.Value, gezilen))
                {
                    kutununOyuncusu[h] = oyuncu;
                    return true;
                }
            }
            return false;
        }
        for (int o = 0; o < kart.Deste.Count; o++) Yerlestir(o, new HashSet<int>());
        return kutununOyuncusu.All(o => o != null);
    }

    [Fact]
    public void Sec_AyniTohumla_AyniKartiSecer()
    {
        var veri = ZenginVeri();

        var ilk = veri.Sec(42)!;
        var ikinci = veri.Sec(42)!;

        Assert.Equal(ilk.Hucreler, ikinci.Hucreler);
        Assert.Equal(ilk.Deste, ikinci.Deste);
    }

    [Fact]
    public void Sec_FarkliTohumlarla_FarkliKartlarSecer()
    {
        var veri = ZenginVeri();

        var kartlar = Enumerable.Range(0, 20)
            .Select(t => string.Join("|", veri.Sec(t)!.Hucreler.Select(h => h.Anahtar)))
            .ToHashSet();

        Assert.True(kartlar.Count > 1, "Her gün aynı kart seçiliyor");
    }

    [Fact]
    public void Sec_MacaCikmayanOyuncu_DesteyeGirmez_AmaEslesmedeSayilir()
    {
        var veri = ZenginVeri();
        var oynamayanlar = veri.Kategoriler.Values.SelectMany(k => k.Oyuncular.Except(k.Oynayanlar)).ToHashSet();

        for (int tohum = 0; tohum < 20; tohum++)
            Assert.DoesNotContain(veri.Sec(tohum)!.Deste, oynamayanlar.Contains);
    }

    [Fact]
    public void Sec_YeterliKategoriYoksa_NullDoner()
    {
        var veri = ZenginVeri();
        // Lig kategorilerinden biri kalsın: kart 2 lig ister
        foreach (var k in veri.Kategoriler.Keys.Where(k => k.Tip == KategoriTipi.Lig).Skip(1).ToList())
            veri.Kategoriler.Remove(k);

        Assert.Null(veri.Sec(1));
    }

    [Fact]
    public void Sec_BilinenOyuncuYetmezse_NullDoner()
    {
        var veri = ZenginVeri();
        // Bilinen oyuncu kalmasın: kartı dolduran oyuncuların 6'sı bilinen olmalı
        foreach (var id in veri.Kademeler.Where(k => k.Value == Kademe.Bilinen).Select(k => k.Key).ToList())
            veri.Kademeler.Remove(id);

        Assert.Null(veri.Sec(1));
    }

    [Fact]
    public void Sec_SadeceAzBilinenOyuncusuOlanKategori_KartaGirmez()
    {
        var veri = ZenginVeri();
        // Sadece az bilinen (diğer) oyuncuların oynadığı bir kulüp: hiçbir tohumda karta girmemeli
        var gizli = veri.Kategori(KategoriTipi.Kulup, "sadece-diger");
        veri.OyuncuEkle(20, Kademe.Diger, true, gizli);

        for (int tohum = 0; tohum < 40; tohum++)
            Assert.DoesNotContain(gizli, veri.Sec(tohum)!.Hucreler);
    }

    [Fact]
    public void KartDagilimi_OnIkiKutu()
    {
        Assert.Equal(12, HucreSayisi);
        Assert.Equal(HucreSayisi, KartDagilimi.Values.Sum());
        Assert.Equal(HucreSayisi, DesteDagilimi.Values.Sum());
        Assert.Equal(32, DesteBoyutu);
    }

    [Fact]
    public void Sec_KutuyaUymayanOyuncuYoksa_NullDoner()
    {
        // Her oyuncu her kategoriye uyar: kutuya uymayan oyuncu bulunamaz
        var v = new TestVerisi();
        var kategoriler = new List<Kategori>();
        foreach (var (tip, adet) in KartDagilimi)
            for (int i = 0; i < adet; i++) kategoriler.Add(v.Kategori(tip, $"{tip}{i}"));
        v.OyuncuEkle(20, Kademe.Unlu, true, kategoriler.ToArray());
        v.OyuncuEkle(20, Kademe.Bilinen, true, kategoriler.ToArray());

        Assert.Null(v.Sec(1));
    }
}
