using ScoutIQ.API.Jobs;
using Supabase.Postgrest.Exceptions;
using static ScoutIQ.API.Jobs.UretimCalismasi;

namespace ScoutIQ.API.Tests;

public class UretimCalismasiTests
{
    private static DateTime Utc(int yil, int ay, int gun, int saat, int dakika = 0) =>
        new(yil, ay, gun, saat, dakika, 0, DateTimeKind.Utc);

    // Veritabanının yerine geçer: Uret çağrılarını kaydeder, "veritabanındaki" oyun tiplerini döndürür
    private sealed class SahteUretici : IOyunUretici
    {
        public HashSet<string> Mevcut { get; set; } = new(BeklenenOyunTipleri);
        public List<DateTime> UretilenTarihler { get; } = new();
        public List<DateTime> KontrolEdilenTarihler { get; } = new();
        public Exception? UretHatasi { get; set; }
        public Exception? KontrolHatasi { get; set; }

        public Task Uret(DateTime hedefTarih)
        {
            UretilenTarihler.Add(hedefTarih);
            return UretHatasi == null ? Task.CompletedTask : Task.FromException(UretHatasi);
        }

        public Task<HashSet<string>> MevcutOyunTipleri(DateTime hedefTarih)
        {
            KontrolEdilenTarihler.Add(hedefTarih);
            return KontrolHatasi == null ? Task.FromResult(Mevcut) : Task.FromException<HashSet<string>>(KontrolHatasi);
        }
    }

    // ---------------- Hedef tarih ----------------

    [Fact]
    public void VarsayilanHedefTarih_TurkiyeSaatiyle18deCalisinca_Yarin()
    {
        // 15.00 UTC = 18.00 Türkiye
        Assert.Equal(new DateTime(2026, 11, 21), VarsayilanHedefTarih(Utc(2026, 11, 20, 15)));
        // 17.00 UTC = 20.00 Türkiye
        Assert.Equal(new DateTime(2026, 11, 21), VarsayilanHedefTarih(Utc(2026, 11, 20, 17)));
    }

    [Fact]
    public void VarsayilanHedefTarih_GeceYarisindanHemenOnce_Yarin()
    {
        // 20.59 UTC = 23.59 Türkiye: Türkiye'de hâlâ 20 Kasım
        Assert.Equal(new DateTime(2026, 11, 21), VarsayilanHedefTarih(Utc(2026, 11, 20, 20, 59)));
    }

    [Fact]
    public void VarsayilanHedefTarih_UtcIleTurkiyeTarihiFarkliyken_TurkiyeyeGoreYarin()
    {
        // 21.30 UTC = 00.30 Türkiye: UTC'de hâlâ 20 Kasım, Türkiye'de 21 Kasım. Yarın 22 Kasım'dır.
        Assert.Equal(new DateTime(2026, 11, 21), TurkiyeBugun(Utc(2026, 11, 20, 21, 30)));
        Assert.Equal(new DateTime(2026, 11, 22), VarsayilanHedefTarih(Utc(2026, 11, 20, 21, 30)));
    }

    [Fact]
    public void VarsayilanHedefTarih_YilSonu_YeniYilaGecer()
    {
        // 31 Aralık 18.00 Türkiye -> 1 Ocak; 31 Aralık 21.00 UTC = 1 Ocak 00.00 Türkiye -> 2 Ocak
        Assert.Equal(new DateTime(2027, 1, 1), VarsayilanHedefTarih(Utc(2026, 12, 31, 15)));
        Assert.Equal(new DateTime(2027, 1, 2), VarsayilanHedefTarih(Utc(2026, 12, 31, 21)));
    }

    [Fact]
    public void VarsayilanHedefTarih_MakineninSaatDiliminiKullanmaz()
    {
        // Kind belirtilmemiş bir zaman da UTC sayılır (Cloud Run makineleri UTC'dedir, yerel makine olmayabilir)
        var belirsiz = new DateTime(2026, 11, 20, 21, 30, 0, DateTimeKind.Unspecified);
        Assert.Equal(new DateTime(2026, 11, 22), VarsayilanHedefTarih(belirsiz));
    }

    [Fact]
    public void TurkiyeSaatDilimi_Cozulebilir()
    {
        // Container'da saat dilimi verisi yoksa bu satır hata verir (Dockerfile'da tzdata kurulur)
        Assert.Equal(TimeSpan.FromHours(3), TurkiyeSaatDilimi.GetUtcOffset(Utc(2026, 11, 20, 12)));
    }

    // ---------------- Elle verilen tarih ----------------

    [Theory]
    [InlineData("--tarih 2026-11-20")]
    [InlineData("--tarih=2026-11-20")]
    [InlineData("--kesisim-onizleme --tarih 2026-11-20")]
    public void ElleVerilenTarih_Okunur(string satir)
    {
        Assert.Equal(new DateTime(2026, 11, 20), ElleVerilenTarih(satir.Split(' ')));
    }

    [Fact]
    public void ElleVerilenTarih_YoksaNull_HedefYarin()
    {
        Assert.Null(ElleVerilenTarih(Array.Empty<string>()));
        Assert.Null(ElleVerilenTarih(new[] { "--top10-onizleme" }));
        Assert.Equal(new DateTime(2026, 11, 21), HedefTarih(Array.Empty<string>(), Utc(2026, 11, 20, 15)));
    }

    [Fact]
    public void ElleVerilenTarih_VarsayilaninYerineGecer()
    {
        // 18.00'de çalışsa bile elle verilen gün (ör. bugünün eksiğini tamamlamak için bugün) kullanılır
        Assert.Equal(new DateTime(2026, 11, 20), HedefTarih(new[] { "--tarih", "2026-11-20" }, Utc(2026, 11, 20, 15)));
    }

    [Theory]
    [InlineData("--tarih")]
    [InlineData("--tarih 20.11.2026")]
    [InlineData("--tarih 2026-13-01")]
    [InlineData("--tarih=")]
    public void ElleVerilenTarih_Gecersizse_Hata(string satir)
    {
        Assert.Throws<ArgumentException>(() => ElleVerilenTarih(satir.Split(' ')));
    }

    // ---------------- Çıkış kodu ----------------

    [Fact]
    public void BeklenenOyunTipleri_OnBirOyun()
    {
        Assert.Equal(
            new[]
            {
                "kesisim_kolay", "kesisim_orta", "kesisim_zor",
                "bonservis_kolay", "bonservis_orta", "bonservis_zor",
                "izgara_kolay", "izgara_orta", "izgara_zor",
                "bingo", "top10"
            },
            BeklenenOyunTipleri);
    }

    [Fact]
    public async Task Calistir_HepsiVarsa_Basarili()
    {
        var uretici = new SahteUretici();

        var kod = await Calistir(Array.Empty<string>(), Utc(2026, 11, 20, 15), uretici);

        Assert.Equal(BasariliCikis, kod);
        Assert.Equal(new[] { new DateTime(2026, 11, 21) }, uretici.UretilenTarihler);
        Assert.Equal(new[] { new DateTime(2026, 11, 21) }, uretici.KontrolEdilenTarihler);
    }

    [Fact]
    public async Task Calistir_EksikOyunVarsa_Basarisiz()
    {
        var uretici = new SahteUretici();
        uretici.Mevcut.Remove("izgara_zor");
        uretici.Mevcut.Remove("top10");

        var kod = await Calistir(Array.Empty<string>(), Utc(2026, 11, 20, 17), uretici);

        Assert.Equal(BasarisizCikis, kod);
        Assert.Equal(new[] { "izgara_zor", "top10" }, EksikOyunlar(uretici.Mevcut));
    }

    [Fact]
    public async Task Calistir_HicOyunYoksa_Basarisiz()
    {
        var uretici = new SahteUretici { Mevcut = new() };

        Assert.Equal(BasarisizCikis, await Calistir(Array.Empty<string>(), Utc(2026, 11, 20, 15), uretici));
    }

    [Fact]
    public async Task Calistir_UretimHataVerseDeOyunlarTamsa_Basarili()
    {
        // Ör. 20.00 çalışması: oyunların hepsi 18.00'de üretilmiş, bu çalışmada bir şey ters gitse de gün tamamdır
        var uretici = new SahteUretici { UretHatasi = new InvalidOperationException("bağlantı koptu") };

        Assert.Equal(BasariliCikis, await Calistir(Array.Empty<string>(), Utc(2026, 11, 20, 17), uretici));
    }

    [Fact]
    public async Task Calistir_UretimHataVerirVeOyunEksikse_Basarisiz()
    {
        var uretici = new SahteUretici { UretHatasi = new InvalidOperationException("bağlantı koptu") };
        uretici.Mevcut.Remove("bingo");

        Assert.Equal(BasarisizCikis, await Calistir(Array.Empty<string>(), Utc(2026, 11, 20, 15), uretici));
    }

    [Fact]
    public async Task Calistir_KontrolYapilamazsa_Basarisiz()
    {
        var uretici = new SahteUretici { KontrolHatasi = new InvalidOperationException("anahtar yanlış") };

        Assert.Equal(BasarisizCikis, await Calistir(Array.Empty<string>(), Utc(2026, 11, 20, 15), uretici));
    }

    [Fact]
    public async Task Calistir_ElleVerilenTarihIcinUretirVeKontrolEder()
    {
        var uretici = new SahteUretici();

        var kod = await Calistir(new[] { "--tarih", "2026-11-20" }, Utc(2026, 11, 20, 21, 30), uretici);

        Assert.Equal(BasariliCikis, kod);
        Assert.Equal(new[] { new DateTime(2026, 11, 20) }, uretici.UretilenTarihler);
        Assert.Equal(new[] { new DateTime(2026, 11, 20) }, uretici.KontrolEdilenTarihler);
    }

    [Fact]
    public async Task Calistir_TarihGecersizse_UretmedenBasarisiz()
    {
        var uretici = new SahteUretici();

        var kod = await Calistir(new[] { "--tarih", "yarin" }, Utc(2026, 11, 20, 15), uretici);

        Assert.Equal(BasarisizCikis, kod);
        Assert.Empty(uretici.UretilenTarihler);
    }

    // ---------------- Tekillik ----------------

    [Fact]
    public void TekillikIhlali_23505ZatenVarSayilir()
    {
        var ex = new PostgrestException(
            "{\"code\":\"23505\",\"details\":\"Key (oyun_tipi, tarih)=(top10, 2026-11-21) already exists.\"," +
            "\"hint\":null,\"message\":\"duplicate key value violates unique constraint \\\"gunluk_oyunlar_oyun_tipi_tarih_key\\\"\"}");

        Assert.True(TekillikIhlali(ex));
    }

    [Fact]
    public void TekillikIhlali_BaskaHatalarSayilmaz()
    {
        // 23503: yabancı anahtar hatası; 23514: kısıt (check) hatası
        Assert.False(TekillikIhlali(new PostgrestException("{\"code\":\"23503\",\"message\":\"violates foreign key constraint\"}")));
        Assert.False(TekillikIhlali(new PostgrestException("{\"code\":\"23514\",\"message\":\"violates check constraint\"}")));
        Assert.False(TekillikIhlali(new InvalidOperationException("23505")));
    }
}
