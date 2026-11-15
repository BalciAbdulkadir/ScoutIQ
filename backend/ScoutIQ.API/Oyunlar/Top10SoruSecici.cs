using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using ScoutIQ.API.Models;

namespace ScoutIQ.API.Oyunlar
{
    // Top 10 oyununun (Mod 5) günlük sorusunu seçer. Veritabanına dokunmaz: transferleri, oyuncuları, Ballon d'Or
    // sıralamalarını ve önceki günlerin sorularını parametre olarak alır, böylece kurallar gerçek veri olmadan test edilebilir.
    // Kurallar: kurallar/scoutiq-top10-kurallar.md (ürün sahibinin kararlarıyla; CLAUDE.md Mod 5).
    //
    // Soru = şablon + değişken. Şablonlar:
    //   Transfer ekseni: T1 kulübün en pahalı 10 transferi, T2 kulübün en pahalı 10 satışı, T3 ligin en pahalı 10 transferi,
    //   T4 en pahalı 10 [ülke]li oyuncu, T5 sezonun en pahalı 10 transferi, T6 iki kulüp arasındaki en pahalı 10 transfer,
    //   T7 en çok kulüp değiştiren 10 oyuncu.
    //   Ballon d'Or ekseni: B1 bir yılın Ballon d'Or sıralamasında ilk 10.
    // Üretim kuralları:
    //   - En az 10 farklı oyuncu olmalı; bir oyuncu listede bir kez yer alır (en yüksek kaydıyla).
    //   - 10. ve 11. oyuncunun değeri eşitse soru üretilmez. İlk 10'daki eşitlikte transferlerde eski tarihli üstte.
    //   - 10 oyuncunun en az MinTaninanSayisi'i ünlü ya da bilinen olmalı.
    //   - Transferlerde sadece bonservisli (bedelli) transferler sayılır, kiralık ve bedelsiz sayılmaz.
    //     Veri BaslangicYili'ndan itibaren güvenilir olduğu için bu tarihten önceki transferler sayılmaz ve başlıkta yazar.
    //   - Kulüp içeren şablonlarda sadece büyük ve baş altı kulüpler kullanılır.
    //   - Aynı şablon + değişken TekrarGunu gün içinde tekrar sorulmaz.
    //   - Aynı eksenden art arda iki gün soru sorulmaz; diğer eksende uygun soru yoksa bu kural uygulanmaz.
    //   - Hiçbir şablonla geçerli soru kurulamazsa null döner, boş ya da kurala uymayan soru üretilmez.
    public class Top10SoruSecici
    {
        public const int ListeBoyu = 10;
        public const int MinTaninanSayisi = 6;
        public const int TekrarGunu = 180;
        public const int BaslangicYili = 2000;

        public const string TransferEkseni = "transfer";
        public const string BallonDorEkseni = "ballon_dor";

        // Bedelli bir transfer. Kulüpler Transfermarkt ID'siyle.
        public record Transfer(string OyuncuId, string? EskiKulupTmId, string? YeniKulupTmId, DateTime? Tarih, string? Sezon, long Bedel);

        public record OyuncuBilgisi(string Isim, string? Uyruk);

        // OyuncuId: oyuncular tablosundaki karşılığı; veritabanında olmayan oyuncuda null
        public record BallonDorSatiri(int Yil, int Sira, string? OyuncuId, decimal? Puan, decimal? Yuzde);

        public record KulupSayisi(string OyuncuId, int Sayi);

        public record Gecmis(string Sablon, string Anahtar, string Eksen, DateTime Tarih);

        public record Veri(
            List<Kulup> Kulupler,
            List<Transfer> Transferler,
            IReadOnlyDictionary<string, OyuncuBilgisi> Oyuncular,
            List<BallonDorSatiri> BallonDor,
            List<KulupSayisi> KulupSayilari);

        // Deger: ekranda gösterilen değer ("222 M€", "1055 puan")
        public record Satir(int Sira, string OyuncuId, string Deger);

        public record Soru(string Sablon, string Anahtar, string Eksen, string Baslik, string? AltBaslik, List<Satir> Satirlar);

        public record SecimSonucu(Soru? Soru, int DenenenSayisi, List<string> Uyarilar);

        // Listedeki bir aday: sıralama değeri, eşitlikte ikincil ölçüt (transferde tarih) ve ekranda yazan değer
        private record Kayit(string OyuncuId, double Deger, DateTime IkincilOlcut, string DegerMetni);

        private record Aday(string Sablon, string Anahtar, string Eksen, Func<(string Baslik, string? AltBaslik, List<Kayit> Kayitlar)?> Hesapla);

        // Kulübün başlıklardaki iyelik hali (Transfermarkt ID -> "Galatasaray'ın"). Listede olmayan kulüp: "X kulübünün".
        public static readonly IReadOnlyDictionary<string, string> KulupIyelik = new Dictionary<string, string>
        {
            ["141"] = "Galatasaray'ın", ["36"] = "Fenerbahçe'nin", ["114"] = "Beşiktaş'ın",
            ["281"] = "Manchester City'nin", ["985"] = "Manchester United'ın", ["31"] = "Liverpool'un",
            ["11"] = "Arsenal'in", ["631"] = "Chelsea'nin", ["148"] = "Tottenham'ın",
            ["418"] = "Real Madrid'in", ["131"] = "Barcelona'nın", ["13"] = "Atlético Madrid'in",
            ["506"] = "Juventus'un", ["46"] = "Inter'in", ["5"] = "Milan'ın",
            ["27"] = "Bayern Münih'in", ["16"] = "Borussia Dortmund'un", ["583"] = "PSG'nin",
            ["449"] = "Trabzonspor'un", ["6890"] = "Başakşehir'in",
            ["762"] = "Newcastle'ın", ["405"] = "Aston Villa'nın", ["379"] = "West Ham'in",
            ["368"] = "Sevilla'nın", ["621"] = "Athletic Bilbao'nun", ["150"] = "Real Betis'in", ["1049"] = "Valencia'nın",
            ["6195"] = "Napoli'nin", ["12"] = "Roma'nın", ["398"] = "Lazio'nun", ["800"] = "Atalanta'nın", ["430"] = "Fiorentina'nın",
            ["15"] = "Leverkusen'in", ["23826"] = "RB Leipzig'in", ["24"] = "Eintracht Frankfurt'un", ["79"] = "Stuttgart'ın",
            ["244"] = "Marsilya'nın", ["162"] = "Monaco'nun", ["1041"] = "Lyon'un", ["1082"] = "Lille'in",
        };

        // Ligin başlıklardaki iyelik hali (BingoSoruSecici.Ligler ile aynı ligler)
        public static readonly IReadOnlyDictionary<string, string> LigIyelik = new Dictionary<string, string>
        {
            ["TR1"] = "Süper Lig'in", ["GB1"] = "Premier Lig'in", ["ES1"] = "La Liga'nın",
            ["IT1"] = "Serie A'nın", ["L1"] = "Bundesliga'nın", ["FR1"] = "Ligue 1'in",
        };

        // Uyruk (Transfermarkt'taki İngilizce ülke adı) -> başlıktaki sıfat ("En pahalı 10 Brezilyalı oyuncu")
        public static readonly IReadOnlyDictionary<string, string> UlkeSifatlari = new Dictionary<string, string>
        {
            ["Türkiye"] = "Türk", ["Spain"] = "İspanyol", ["England"] = "İngiliz", ["France"] = "Fransız",
            ["Brazil"] = "Brezilyalı", ["Italy"] = "İtalyan", ["Germany"] = "Alman", ["Argentina"] = "Arjantinli",
            ["Portugal"] = "Portekizli", ["Netherlands"] = "Hollandalı", ["Belgium"] = "Belçikalı", ["Croatia"] = "Hırvat",
            ["Switzerland"] = "İsviçreli", ["Uruguay"] = "Uruguaylı", ["Colombia"] = "Kolombiyalı", ["Senegal"] = "Senegalli",
            ["Morocco"] = "Faslı", ["Serbia"] = "Sırp", ["Denmark"] = "Danimarkalı", ["Norway"] = "Norveçli",
            ["Nigeria"] = "Nijeryalı", ["Cote d'Ivoire"] = "Fildişili", ["Japan"] = "Japon", ["Poland"] = "Polonyalı",
            ["Ghana"] = "Ganalı", ["Mexico"] = "Meksikalı", ["United States"] = "Amerikalı", ["Sweden"] = "İsveçli",
            ["Austria"] = "Avusturyalı", ["Scotland"] = "İskoç", ["Wales"] = "Galli", ["Ukraine"] = "Ukraynalı",
            ["Russia"] = "Rus", ["Czech Republic"] = "Çek", ["Algeria"] = "Cezayirli", ["Cameroon"] = "Kamerunlu",
            ["Egypt"] = "Mısırlı", ["Chile"] = "Şilili", ["Greece"] = "Yunan", ["Korea, South"] = "Güney Koreli",
        };

        private readonly Random _random;

        public Top10SoruSecici(Random? random = null)
        {
            _random = random ?? new Random();
        }

        public SecimSonucu Sec(DateTime bugun, Veri veri, IReadOnlyDictionary<string, Kademe> kademeler, IEnumerable<Gecmis> gecmisListesi)
        {
            var gecmis = gecmisListesi.ToList();
            var son = gecmis.Where(g => g.Tarih.Date < bugun.Date).OrderByDescending(g => g.Tarih).FirstOrDefault();
            var yakinda = gecmis.Where(g => (bugun.Date - g.Tarih.Date).TotalDays < TekrarGunu)
                .Select(g => (g.Sablon, g.Anahtar)).ToHashSet();

            var adaylar = Adaylar(bugun, veri).Where(a => !yakinda.Contains((a.Sablon, a.Anahtar))).ToList();
            Karistir(adaylar);
            // Dünkü eksenden olmayanlar önce: diğer eksende uygun soru yoksa dünkü eksen de denenir
            adaylar = adaylar.OrderBy(a => son != null && a.Eksen == son.Eksen ? 1 : 0).ToList();

            var uyarilar = new List<string>();
            int denenen = 0;
            foreach (var aday in adaylar)
            {
                denenen++;
                var liste = aday.Hesapla();
                if (liste == null) continue;
                var satirlar = Dogrula(liste.Value.Kayitlar, kademeler);
                if (satirlar == null) continue;

                if (son != null && aday.Eksen == son.Eksen && adaylar.Any(a => a.Eksen != son.Eksen))
                    uyarilar.Add($"Dünkü eksenden ({son.Eksen}) farklı eksende geçerli soru kurulamadı; aynı eksenden soru seçildi.");
                return new SecimSonucu(new Soru(aday.Sablon, aday.Anahtar, aday.Eksen, liste.Value.Baslik, liste.Value.AltBaslik, satirlar),
                    denenen, uyarilar);
            }

            uyarilar.Add($"Top 10 için geçerli soru kurulamadı ({denenen} şablon ve değişken denendi).");
            return new SecimSonucu(null, denenen, uyarilar);
        }

        // Listeyi kurallara göre kontrol eder: en az 10 oyuncu, 10. ile 11. eşit değil, en az 6 tanınan oyuncu
        private static List<Satir>? Dogrula(List<Kayit> kayitlar, IReadOnlyDictionary<string, Kademe> kademeler)
        {
            var sirali = kayitlar
                .OrderByDescending(k => k.Deger)
                .ThenBy(k => k.IkincilOlcut)
                .ThenBy(k => k.OyuncuId, StringComparer.Ordinal)
                .ToList();
            if (sirali.Count < ListeBoyu) return null;
            if (sirali.Count > ListeBoyu && sirali[ListeBoyu].Deger == sirali[ListeBoyu - 1].Deger) return null;

            var ilk10 = sirali.Take(ListeBoyu).ToList();
            int taninan = ilk10.Count(k => kademeler.TryGetValue(k.OyuncuId, out var kademe) && kademe is Kademe.Unlu or Kademe.Bilinen);
            if (taninan < MinTaninanSayisi) return null;

            return ilk10.Select((k, i) => new Satir(i + 1, k.OyuncuId, k.DegerMetni)).ToList();
        }

        // Bütün şablon + değişken adayları. Listeler sadece denenince hesaplanır.
        private static List<Aday> Adaylar(DateTime bugun, Veri veri)
        {
            var adaylar = new List<Aday>();
            var transferler = veri.Transferler
                .Where(t => t.Bedel > 0 && t.Tarih.HasValue && t.Tarih.Value.Year >= BaslangicYili && veri.Oyuncular.ContainsKey(t.OyuncuId))
                .ToList();
            var donem = $"{BaslangicYili}'den bugüne · {Tarihi(bugun)} itibarıyla";

            var kulupler = veri.Kulupler
                .Where(k => k.Kademe is KulupKademeleri.Buyuk or KulupKademeleri.BasAlti && KesisimSoruSecici.Kulupler.ContainsKey(k.TransfermarktId))
                .OrderBy(k => k.TransfermarktId, StringComparer.Ordinal)
                .ToList();
            string Iyelik(Kulup k) => KulupIyelik.TryGetValue(k.TransfermarktId, out var i) ? i : $"{KesisimSoruSecici.Kulupler[k.TransfermarktId]} kulübünün";
            string Ad(Kulup k) => KesisimSoruSecici.Kulupler[k.TransfermarktId];

            foreach (var k in kulupler)
            {
                adaylar.Add(new Aday("T1", k.TransfermarktId, TransferEkseni,
                    () => ($"{Iyelik(k)} en pahalı 10 transferi", donem, TransferListesi(transferler.Where(t => t.YeniKulupTmId == k.TransfermarktId)))));
                adaylar.Add(new Aday("T2", k.TransfermarktId, TransferEkseni,
                    () => ($"{Iyelik(k)} en pahalı 10 satışı", donem, TransferListesi(transferler.Where(t => t.EskiKulupTmId == k.TransfermarktId)))));
            }

            foreach (var (kod, iyelik) in LigIyelik)
            {
                var ligKulupleri = veri.Kulupler.Where(k => k.Lig == kod).Select(k => k.TransfermarktId).ToHashSet();
                adaylar.Add(new Aday("T3", kod, TransferEkseni,
                    () => ($"{iyelik} en pahalı 10 transferi", donem,
                        TransferListesi(transferler.Where(t => t.YeniKulupTmId != null && ligKulupleri.Contains(t.YeniKulupTmId))))));
            }

            foreach (var (ulke, sifat) in UlkeSifatlari)
            {
                adaylar.Add(new Aday("T4", ulke, TransferEkseni,
                    () => ($"En pahalı 10 {sifat} oyuncu", $"Oyuncunun en yüksek bonservisi · {donem}",
                        TransferListesi(transferler.Where(t => veri.Oyuncular[t.OyuncuId].Uyruk == ulke)))));
            }

            foreach (var sezon in transferler.Select(t => t.Sezon).Where(s => SezonYili(s) is >= BaslangicYili).Distinct().OrderBy(s => s))
            {
                var sezonAdi = SezonAdi(sezon!);
                adaylar.Add(new Aday("T5", sezon!, TransferEkseni,
                    () => ($"{sezonAdi} sezonunun en pahalı 10 transferi", null, TransferListesi(transferler.Where(t => t.Sezon == sezon)))));
            }

            for (int i = 0; i < kulupler.Count; i++)
            {
                for (int j = i + 1; j < kulupler.Count; j++)
                {
                    var (a, b) = (kulupler[i], kulupler[j]);
                    var ikili = transferler.Where(t =>
                        (t.EskiKulupTmId == a.TransfermarktId && t.YeniKulupTmId == b.TransfermarktId) ||
                        (t.EskiKulupTmId == b.TransfermarktId && t.YeniKulupTmId == a.TransfermarktId)).ToList();
                    // Aday sayısını boşuna büyütmesin: 10 farklı oyuncusu olmayan çift hiç denenmez
                    if (ikili.Select(t => t.OyuncuId).Distinct().Count() < ListeBoyu) continue;
                    adaylar.Add(new Aday("T6", $"{a.TransfermarktId}-{b.TransfermarktId}", TransferEkseni,
                        () => ($"{Ad(a)} ile {Ad(b)} arasındaki en pahalı 10 transfer", donem, TransferListesi(ikili))));
                }
            }

            if (veri.KulupSayilari.Count > 0)
            {
                adaylar.Add(new Aday("T7", "hepsi", TransferEkseni,
                    () => ("En çok kulüp değiştiren 10 oyuncu", $"Kariyerindeki farklı kulüp sayısı · {Tarihi(bugun)} itibarıyla",
                        veri.KulupSayilari
                            .Where(k => veri.Oyuncular.ContainsKey(k.OyuncuId))
                            .Select(k => new Kayit(k.OyuncuId, k.Sayi, DateTime.MinValue, $"{k.Sayi} kulüp"))
                            .ToList())));
            }

            foreach (var yil in veri.BallonDor.Select(b => b.Yil).Distinct().OrderBy(y => y))
            {
                adaylar.Add(new Aday("B1", yil.ToString(CultureInfo.InvariantCulture), BallonDorEkseni,
                    () => BallonDorListesi(yil, veri.BallonDor.Where(b => b.Yil == yil).ToList())));
            }

            return adaylar;
        }

        // Transferlerden oyuncu başına en yüksek bedelli kayıt; eşit bedelde eski tarihli kayıt
        private static List<Kayit> TransferListesi(IEnumerable<Transfer> transferler) => transferler
            .GroupBy(t => t.OyuncuId)
            .Select(g => g.OrderByDescending(t => t.Bedel).ThenBy(t => t.Tarih).First())
            .Select(t => new Kayit(t.OyuncuId, t.Bedel, t.Tarih ?? DateTime.MaxValue, Milyon(t.Bedel)))
            .ToList();

        // Bir yılın Ballon d'Or sıralamasında ilk 10. Sıra eşitliği (10. ve 11. aynı sırada) Dogrula'da yakalanır.
        // İlk 10'daki bir oyuncu veritabanında yoksa (bulunamaz) soru üretilmez.
        private static (string, string?, List<Kayit>)? BallonDorListesi(int yil, List<BallonDorSatiri> satirlar)
        {
            var ilkler = satirlar.Where(s => s.Sira <= ListeBoyu).ToList();
            if (ilkler.Any(s => s.OyuncuId == null)) return null;
            bool fifa = satirlar.All(s => s.Puan == null && s.Yuzde != null);
            var kayitlar = satirlar
                .Where(s => s.OyuncuId != null)
                .GroupBy(s => s.OyuncuId!)
                .Select(g => g.OrderBy(s => s.Sira).First())
                .Select(s => new Kayit(s.OyuncuId!, -s.Sira, DateTime.MinValue,
                    s.Puan != null ? $"{s.Puan.Value.ToString("0.##", CultureInfo.InvariantCulture)} puan"
                    : s.Yuzde != null ? $"%{s.Yuzde.Value.ToString("0.##", CultureInfo.GetCultureInfo("tr-TR"))}"
                    : $"{s.Sira}."))
                .ToList();
            var ad = fifa ? "FIFA Ballon d'Or" : "Ballon d'Or";
            return ($"{yil} {ad} sıralamasında ilk 10", fifa ? "Oy yüzdesine göre" : "Aldığı puana göre", kayitlar);
        }

        // "18/19" -> 2018; çözülemezse null
        public static int? SezonYili(string? sezon)
        {
            if (sezon == null || sezon.Length < 2 || !int.TryParse(sezon[..2], out var iki)) return null;
            return iki >= 50 ? 1900 + iki : 2000 + iki;
        }

        // "18/19" -> "2018/19"
        public static string SezonAdi(string sezon) =>
            SezonYili(sezon) is int yil && sezon.Contains('/') ? $"{yil}/{sezon[(sezon.IndexOf('/') + 1)..]}" : sezon;

        // 222000000 -> "222 M€", 7500000 -> "7,5 M€", 850000 -> "0,85 M€"
        public static string Milyon(long euro)
        {
            var milyon = euro / 1_000_000m;
            var bicim = milyon >= 1 ? "0.#" : "0.##";
            return $"{milyon.ToString(bicim, CultureInfo.GetCultureInfo("tr-TR"))} M€";
        }

        private static string Tarihi(DateTime tarih) =>
            tarih.ToString("MMMM yyyy", CultureInfo.GetCultureInfo("tr-TR"));

        private void Karistir<T>(List<T> liste)
        {
            for (int i = liste.Count - 1; i > 0; i--)
            {
                int j = _random.Next(i + 1);
                (liste[i], liste[j]) = (liste[j], liste[i]);
            }
        }
    }
}
