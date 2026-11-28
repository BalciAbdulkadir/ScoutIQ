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
        // Desteye ek oyuncu olarak girebilen (üst sıralardaki) bilinen oyuncular
        public HashSet<string> EkBilinenler { get; } = new();
        private int _oyuncuNo;

        public Kategori Kategori(KategoriTipi tip, string anahtar, bool basAlti = false)
        {
            var k = new Kategori(tip, anahtar, $"{tip} {anahtar}", BasAlti: basAlti);
            Kategoriler[k] = (new HashSet<string>(), new HashSet<string>());
            return k;
        }

        // Verilen kategorilerin hepsine uyan "adet" kadar yeni oyuncu ekler. kademe null: havuz dışı.
        // oynadi false: kategoride kaydı var ama yeterince maça çıkmamış (sadece cevap olarak kabul edilir).
        // Bilinen oyuncular üst sıralardadır (ek oyuncu olabilir); altSira true ise değildir.
        public void OyuncuEkle(int adet, Kademe? kademe, bool oynadi, params Kategori[] kategoriler) =>
            OyuncuEkle(adet, kademe, oynadi, false, kategoriler);

        public void OyuncuEkle(int adet, Kademe? kademe, bool oynadi, bool altSira, params Kategori[] kategoriler)
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
                if (kademe == Kademe.Bilinen && !altSira) EkBilinenler.Add(id);
            }
        }

        public List<Aday> Adaylar() => Kategoriler.Select(k => new Aday(k.Key, k.Value.Oyuncular, k.Value.Oynayanlar)).ToList();

        public BingoKarti? Sec(int tohum) => new BingoSoruSecici(new Random(tohum)).Sec(Adaylar(), Kademeler, EkBilinenler);
    }

    // Her tipten fazlasıyla kategori (9 büyük, 4 baş altı kulüp); her kategoride her kademeden oyuncu,
    // bazıları iki kategoriye birden uyar
    private static TestVerisi ZenginVeri()
    {
        var v = new TestVerisi();
        var kategoriler = new List<Kategori>();
        for (int i = 0; i < 9; i++) kategoriler.Add(v.Kategori(KategoriTipi.Kulup, $"k{i}"));
        for (int i = 0; i < 4; i++) kategoriler.Add(v.Kategori(KategoriTipi.Kulup, $"basalti{i}", basAlti: true));
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
            // Tuzaklar: havuz dışı oyuncu, yeterince maça çıkmamış ünlü oyuncu ve alt sıralardaki bilinen oyuncu desteye girmemeli
            v.OyuncuEkle(2, null, true, kategoriler[i]);
            v.OyuncuEkle(1, Kademe.Unlu, false, kategoriler[i]);
            v.OyuncuEkle(3, Kademe.Bilinen, true, true, kategoriler[i]);
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

        // Kulüpler: en fazla MaxBasAltiKulup baş altı kulüp, kalanı büyük kulüp
        Assert.True(kart.Hucreler.Count(h => h.BasAlti) <= MaxBasAltiKulup, "Kartta fazla baş altı kulüp var");

        // Deste: 32 farklı havuz oyuncusu, sadece ünlü ve üst sıralardaki bilinen; az bilinen (diğer) oyuncu yok
        Assert.Equal(DesteBoyutu, kart.Deste.Count);
        Assert.Equal(DesteBoyutu, kart.Deste.Distinct().Count());
        Assert.All(kart.Deste, o => Assert.True(veri.Kademeler.ContainsKey(o), $"Havuz dışı oyuncu destede: {o}"));
        Assert.All(kart.Deste, o => Assert.NotEqual(Kademe.Diger, veri.Kademeler[o]));
        Assert.All(kart.Deste.Where(o => veri.Kademeler[o] == Kademe.Bilinen),
            o => Assert.True(veri.EkBilinenler.Contains(o), $"Alt sıralardaki bilinen oyuncu destede: {o}"));

        // Deste ünlü ağırlıklı: en az MinUnluSayisi (26) ünlü
        Assert.True(kart.Deste.Count(o => veri.Kademeler[o] == Kademe.Unlu) >= MinUnluSayisi, "Destede yeterli ünlü yok");

        // Eşleşmeler doğru: oyuncunun uyduğu bütün kutular, sadece onlar
        for (int i = 0; i < DesteBoyutu; i++)
        {
            var beklenen = Enumerable.Range(0, HucreSayisi).Where(h => veri.Kategoriler[kart.Hucreler[h]].Oyuncular.Contains(kart.Deste[i]));
            Assert.Equal(beklenen, kart.Eslesmeler[i]);
        }

        // Kutuya uymayan oyuncu az: tam UymayanSayisi kadar
        Assert.Equal(UymayanSayisi, kart.Eslesmeler.Count(e => e.Length == 0));

        // Ek oyuncular kutulara dengeli dağılır: her kutuya destede en az 2 oyuncu uyar
        for (int h = 0; h < HucreSayisi; h++)
            Assert.True(kart.Eslesmeler.Count(e => e.Contains(h)) >= 2, $"{h}. kutuya destede 2'den az oyuncu uyuyor");

        // Kart doldurulabilir: her kutuya desteden ayrı bir oyuncu atanabilir, sadece ünlü oyuncularla bile
        Assert.True(TamEslesmeVar(kart), "Kart desteden doldurulamıyor");
        Assert.True(TamEslesmeVar(kart, o => veri.Kademeler[kart.Deste[o]] == Kademe.Unlu), "Kart ünlü oyuncularla doldurulamıyor");
    }

    // Kutular ile oyuncular arasında herkese ayrı oyuncu düşen bir eşleşme var mı (artırımlı yol)
    private static bool TamEslesmeVar(BingoKarti kart, Func<int, bool>? oyuncuFiltresi = null)
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
        for (int o = 0; o < kart.Deste.Count; o++)
            if (oyuncuFiltresi == null || oyuncuFiltresi(o)) Yerlestir(o, new HashSet<int>());
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
    public void Sec_BilinenOyuncuYoksa_DesteUnlulerdenKurulur()
    {
        var veri = ZenginVeri();
        // Üst sıralarda bilinen oyuncu kalmasın: ek oyuncuların eksiği ünlülerden tamamlanır
        veri.EkBilinenler.Clear();

        var kart = veri.Sec(1);

        Assert.NotNull(kart);
        Assert.All(kart!.Deste, o => Assert.Equal(Kademe.Unlu, veri.Kademeler[o]));
    }

    [Fact]
    public void Sec_UnluOyuncuYoksa_NullDoner()
    {
        var veri = ZenginVeri();
        // Ünlü oyuncu kalmasın: kartı dolduran 12 oyuncunun hepsi ünlü olmalı
        foreach (var id in veri.Kademeler.Where(k => k.Value == Kademe.Unlu).Select(k => k.Key).ToList())
            veri.Kademeler.Remove(id);

        Assert.Null(veri.Sec(1));
    }

    [Fact]
    public void Sec_UnluOyuncusuOlmayanKategori_KartaGirmez()
    {
        var veri = ZenginVeri();
        // Sadece bilinen ve az bilinen oyuncuların oynadığı bir kulüp: hiçbir tohumda karta girmemeli
        var gizli = veri.Kategori(KategoriTipi.Kulup, "unlusuz");
        veri.OyuncuEkle(20, Kademe.Bilinen, true, gizli);
        veri.OyuncuEkle(20, Kademe.Diger, true, gizli);

        for (int tohum = 0; tohum < 40; tohum++)
            Assert.DoesNotContain(gizli, veri.Sec(tohum)!.Hucreler);
    }

    [Fact]
    public void Sec_BasAltiKulup_BazenCikar_AmaEnFazlaBirTane()
    {
        var veri = ZenginVeri();

        var sayilar = Enumerable.Range(0, 40).Select(t => veri.Sec(t)!.Hucreler.Count(h => h.BasAlti)).ToList();

        Assert.Contains(sayilar, s => s == 0);
        Assert.Contains(sayilar, s => s == MaxBasAltiKulup);
        Assert.All(sayilar, s => Assert.True(s <= MaxBasAltiKulup));
    }

    [Fact]
    public void Sec_BuyukKulupYetmezse_NullDoner()
    {
        var veri = ZenginVeri();
        // 2 büyük kulüp kalsın: kart en az 3 büyük kulüp ister (4 kulübün en fazla 1'i baş altı)
        foreach (var k in veri.Kategoriler.Keys.Where(k => k.Tip == KategoriTipi.Kulup && !k.BasAlti).Skip(2).ToList())
            veri.Kategoriler.Remove(k);

        Assert.Null(veri.Sec(1));
    }

    [Fact]
    public void KartDagilimi_OnIkiKutu()
    {
        Assert.Equal(12, HucreSayisi);
        Assert.Equal(HucreSayisi, KartDagilimi.Values.Sum());
        Assert.Equal(32, DesteBoyutu);
        Assert.Equal(26, MinUnluSayisi);
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

    [Fact]
    public void Sec_KalabalikKategori_EkOyunculariToplamaz()
    {
        // Lig kategorilerinden biri 200 ünlüyle çok kalabalık; diğer kategorilerde 4 ünlü + 2 bilinen.
        // Ek oyuncular rastgele seçilseydi çoğu o lige düşerdi; dengeli dağıtımda o kutuya en fazla 4 oyuncu uyar.
        var v = new TestVerisi();
        var kalabalik = v.Kategori(KategoriTipi.Lig, "kalabalik");
        var digerleri = new List<Kategori> { v.Kategori(KategoriTipi.Lig, "lig") };
        // Kartın istediğinden birer fazla kategori: karta girmeyenlerin oyuncuları kutuya uymayan oyuncu olur
        foreach (var (tip, adet) in KartDagilimi.Where(k => k.Key != KategoriTipi.Lig))
            for (int i = 0; i <= adet; i++) digerleri.Add(v.Kategori(tip, $"{tip}{i}"));
        v.OyuncuEkle(200, Kademe.Unlu, true, kalabalik);
        foreach (var k in digerleri)
        {
            v.OyuncuEkle(4, Kademe.Unlu, true, k);
            v.OyuncuEkle(2, Kademe.Bilinen, true, k);
        }

        for (int tohum = 0; tohum < 30; tohum++)
        {
            var kart = v.Sec(tohum);
            Assert.NotNull(kart);
            int h = kart!.Hucreler.IndexOf(kalabalik);
            Assert.True(h >= 0, "Kalabalık lig kartta yok");
            int uyan = kart.Eslesmeler.Count(e => e.Contains(h));
            Assert.True(uyan <= 4, $"Tohum {tohum}: kalabalık lig kutusuna destede {uyan} oyuncu uyuyor");
        }
    }
}
