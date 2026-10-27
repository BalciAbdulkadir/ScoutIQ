using System;
using System.Collections.Generic;
using System.Linq;
using ScoutIQ.API.Models;

namespace ScoutIQ.API.Oyunlar
{
    // Kesişim oyununun 5 sorusunu seçer. Veritabanına dokunmaz: kulüpleri ve kariyer geçmişini parametre olarak alır,
    // böylece kurallar gerçek veri olmadan test edilebilir.
    public class KesisimSoruSecici
    {
        public enum Zorluk { Kolay, Orta, Zor }

        // Kesişim soruları kolaydan zora sıralanır: 2 kolay, 2 orta-zor, 1 zor
        public static readonly IReadOnlyList<Zorluk> SoruSirasi = new[] { Zorluk.Kolay, Zorluk.Kolay, Zorluk.Orta, Zorluk.Orta, Zorluk.Zor };

        // Kolay sorularda iki kulüp de bu listeden olur. Transfermarkt ID'si ile eşleştirilir, isimler değişebilir.
        public static readonly IReadOnlyDictionary<string, string> BuyukKulupler = new Dictionary<string, string>
        {
            // Türkiye: 3 büyükler
            ["141"] = "Galatasaray", ["36"] = "Fenerbahçe", ["114"] = "Beşiktaş",
            // İngiltere: Big Six
            ["281"] = "Manchester City", ["985"] = "Manchester United", ["31"] = "Liverpool",
            ["11"] = "Arsenal", ["631"] = "Chelsea", ["148"] = "Tottenham",
            // İspanya
            ["418"] = "Real Madrid", ["131"] = "Barcelona", ["13"] = "Atlético Madrid",
            // İtalya
            ["506"] = "Juventus", ["46"] = "Inter", ["5"] = "Milan",
            // Almanya
            ["27"] = "Bayern Münih", ["16"] = "Borussia Dortmund",
            // Fransa
            ["583"] = "PSG",
        };

        // Orta-zor sorularda en az bir kulüp bu listeden olur, diğeri bu listeden ya da büyük kulüplerden.
        public static readonly IReadOnlyDictionary<string, string> BasAltiKulupler = new Dictionary<string, string>
        {
            // İngiltere
            ["762"] = "Newcastle", ["405"] = "Aston Villa", ["379"] = "West Ham",
            // İspanya
            ["368"] = "Sevilla", ["1050"] = "Villarreal", ["681"] = "Real Sociedad",
            ["621"] = "Athletic Bilbao", ["150"] = "Real Betis", ["1049"] = "Valencia",
            // İtalya
            ["6195"] = "Napoli", ["12"] = "Roma", ["398"] = "Lazio", ["800"] = "Atalanta", ["430"] = "Fiorentina",
            // Almanya
            ["15"] = "Leverkusen", ["23826"] = "RB Leipzig", ["24"] = "Eintracht Frankfurt", ["79"] = "Stuttgart",
            // Fransa
            ["244"] = "Marsilya", ["162"] = "Monaco", ["1041"] = "Lyon", ["1082"] = "Lille",
            // Türkiye
            ["449"] = "Trabzonspor", ["6890"] = "Başakşehir",
        };

        // Kolay: iki kulüp de büyük. Orta-zor: baş altı kulüp içerir, farklı liglerden, en az 2 ortak oyuncu.
        // Zor: geri kalan farklı lig çiftleri. Aynı ligden çiftler (büyükler hariç) sorulmaz:
        // transferler çoğunlukla lig içinde olduğu için aksi halde sorular hep aynı ligden çıkıyor.
        public const int OrtaMinOrtakOyuncu = 2;

        public record KulupCifti(Kulup KulupA, Kulup KulupB, int OrtakOyuncuSayisi);
        public record KesisimSorusu(KulupCifti Cift, Zorluk Zorluk);

        // Sorular: 5 soru ya da yeterli çift yoksa null. Havuzlar ve uyarılar günlüğe yazılmak içindir.
        public record SecimSonucu(
            List<KesisimSorusu>? Sorular,
            IReadOnlyDictionary<Zorluk, int> HavuzBoyutlari,
            List<string> Uyarilar);

        private readonly Random _random;

        public KesisimSoruSecici(Random? random = null)
        {
            _random = random ?? new Random();
        }

        // Tüm kulüp çiftlerinin ortak oyuncu sayısını hesaplar ve her zorluktan rastgele çift seçer.
        // Sadece en az bir ortak oyuncusu olan çiftler soru olabilir. Bir oyunda aynı kulüp iki kez çıkmaz.
        // Ligi olmayan kulüpler (efsanelerin eski kulüpleri) soru olmaz; cevap kontrolü yine tüm kariyere bakar.
        public SecimSonucu Sec(IEnumerable<Kulup> kulupListesi, IEnumerable<KariyerGecmisi> kariyer)
        {
            var kulupler = kulupListesi.Where(k => k.Lig != null).ToDictionary(k => k.Id);
            var uyarilar = new List<string>();

            var buyukKulupIdleri = ListedekiKulupIdleri(BuyukKulupler, kulupler.Values);
            var basAltiKulupIdleri = ListedekiKulupIdleri(BasAltiKulupler, kulupler.Values);

            var kulupOyunculari = kariyer
                .Where(k => kulupler.ContainsKey(k.KulupId))
                .GroupBy(k => k.KulupId)
                .ToDictionary(g => g.Key, g => g.Select(k => k.OyuncuId).ToHashSet());

            var havuzlar = new Dictionary<Zorluk, List<KulupCifti>>
            {
                [Zorluk.Kolay] = new(),
                [Zorluk.Orta] = new(),
                [Zorluk.Zor] = new()
            };

            // Sıralı gezilir ki aynı tohumla (seed) aynı sonuç çıksın
            var kulupIdleri = kulupOyunculari.Keys.OrderBy(id => id, StringComparer.Ordinal).ToList();
            for (int i = 0; i < kulupIdleri.Count; i++)
            {
                for (int j = i + 1; j < kulupIdleri.Count; j++)
                {
                    int ortak = OrtakSayisi(kulupOyunculari[kulupIdleri[i]], kulupOyunculari[kulupIdleri[j]]);
                    if (ortak == 0) continue;

                    var cift = new KulupCifti(kulupler[kulupIdleri[i]], kulupler[kulupIdleri[j]], ortak);
                    var zorluk = ZorlukBelirle(cift, buyukKulupIdleri, basAltiKulupIdleri);
                    if (zorluk != null) havuzlar[zorluk.Value].Add(cift);
                }
            }

            var havuzBoyutlari = havuzlar.ToDictionary(h => h.Key, h => h.Value.Count);

            foreach (var havuz in havuzlar.Values)
            {
                Karistir(havuz);
            }

            var sorular = new List<KesisimSorusu>();
            var kullanilanKulupler = new HashSet<string>();

            foreach (var istenen in SoruSirasi)
            {
                KulupCifti? secilen = null;

                // İstenen zorlukta uygun çift kalmadıysa en yakın zorluktan alınır
                foreach (var zorluk in YedekSirasi(istenen))
                {
                    secilen = havuzlar[zorluk].FirstOrDefault(c =>
                        !kullanilanKulupler.Contains(c.KulupA.Id) && !kullanilanKulupler.Contains(c.KulupB.Id));

                    if (secilen != null)
                    {
                        if (zorluk != istenen)
                        {
                            uyarilar.Add($"{istenen} çift kalmadı, yerine {zorluk} çift kullanıldı.");
                        }
                        break;
                    }
                }

                if (secilen == null)
                {
                    uyarilar.Add($"Kesişim için 5 eşleşme bulunamadı. Bulunan: {sorular.Count} (Veritabanında yeterli kariyer verisi yok)");
                    return new SecimSonucu(null, havuzBoyutlari, uyarilar);
                }

                kullanilanKulupler.Add(secilen.KulupA.Id);
                kullanilanKulupler.Add(secilen.KulupB.Id);

                // Hangi kulübün solda görüneceği de rastgele olsun
                if (_random.Next(2) == 0)
                {
                    secilen = secilen with { KulupA = secilen.KulupB, KulupB = secilen.KulupA };
                }

                sorular.Add(new KesisimSorusu(secilen, istenen));
            }

            return new SecimSonucu(sorular, havuzBoyutlari, uyarilar);
        }

        // Çiftin hangi zorlukta sorulacağını döndürür, hiç sorulmayacaksa null
        public static Zorluk? ZorlukBelirle(KulupCifti cift, IReadOnlySet<string> buyukler, IReadOnlySet<string> basAltilar)
        {
            string a = cift.KulupA.Id, b = cift.KulupB.Id;

            if (buyukler.Contains(a) && buyukler.Contains(b)) return Zorluk.Kolay;
            if (cift.KulupA.Lig == cift.KulupB.Lig) return null;

            bool basAltiVar = basAltilar.Contains(a) || basAltilar.Contains(b);
            bool ikisiDeUstSeviye = (buyukler.Contains(a) || basAltilar.Contains(a)) && (buyukler.Contains(b) || basAltilar.Contains(b));
            if (basAltiVar && ikisiDeUstSeviye && cift.OrtakOyuncuSayisi >= OrtaMinOrtakOyuncu) return Zorluk.Orta;

            return Zorluk.Zor;
        }

        // Orta-zor yerine zor çift kullanılmaz: orta-zor soruda en az 2 ortak oyuncu şartı korunur
        public static IReadOnlyList<Zorluk> YedekSirasi(Zorluk istenen) => istenen switch
        {
            Zorluk.Kolay => new[] { Zorluk.Kolay, Zorluk.Orta },
            Zorluk.Orta => new[] { Zorluk.Orta, Zorluk.Kolay },
            _ => new[] { Zorluk.Zor, Zorluk.Orta, Zorluk.Kolay }
        };

        // Listedeki Transfermarkt ID'lerine denk gelen kulüplerin veritabanı ID'lerini döndürür
        public static HashSet<string> ListedekiKulupIdleri(IReadOnlyDictionary<string, string> liste, IEnumerable<Kulup> kulupler)
        {
            return kulupler.Where(k => liste.ContainsKey(k.TransfermarktId)).Select(k => k.Id).ToHashSet();
        }

        private static int OrtakSayisi(HashSet<string> a, HashSet<string> b)
        {
            var (kucuk, buyuk) = a.Count <= b.Count ? (a, b) : (b, a);
            return kucuk.Count(buyuk.Contains);
        }

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
