using System;
using System.Collections.Generic;
using System.Linq;

namespace ScoutIQ.API.Oyunlar
{
    // Oyuncunun soru havuzundaki kademesi (data_miner/kademeler.py). Sıra önemlidir: önce gelen daha bilinir.
    // Havuz dışındaki oyuncuların ('cevap' ya da boş) kademesi yoktur: soru üretmezler, sadece cevap olarak kabul edilirler.
    public enum Kademe { Unlu, Bilinen, Diger }

    // Her oyunun üç modu vardır, kullanıcı günde birini seçip oynar. Her mod ayrı bir günlük oyundur.
    public enum Zorluk { Kolay, Orta, Zor }

    // Modlara göre soruların kademe dağılımı ve ortak yardımcılar
    public static class ZorlukDagilimi
    {
        // Kolay: hep ünlü. Orta: yarısı ünlü, yarısı bilinen. Zor: %40 ünlü, %30 bilinen, %30 diğer.
        public static readonly IReadOnlyDictionary<Zorluk, IReadOnlyDictionary<Kademe, int>> Yuzdeler =
            new Dictionary<Zorluk, IReadOnlyDictionary<Kademe, int>>
            {
                [Zorluk.Kolay] = new Dictionary<Kademe, int> { [Kademe.Unlu] = 100 },
                [Zorluk.Orta] = new Dictionary<Kademe, int> { [Kademe.Unlu] = 50, [Kademe.Bilinen] = 50 },
                [Zorluk.Zor] = new Dictionary<Kademe, int> { [Kademe.Unlu] = 40, [Kademe.Bilinen] = 30, [Kademe.Diger] = 30 },
            };

        // "adet" soruyu kademelere böler. Tam bölünmeyen kısım daha bilinen kademeye yuvarlanır (buçuk yukarı),
        // kalan en zor kademeye kalır. Örnek: 9 hücre, zor -> 4 ünlü, 3 bilinen, 2 diğer; 5 soru, orta -> 3 ünlü, 2 bilinen.
        public static Dictionary<Kademe, int> Dagit(Zorluk zorluk, int adet)
        {
            var yuzdeler = Yuzdeler[zorluk].OrderBy(y => y.Key).ToList();
            var sonuc = new Dictionary<Kademe, int>();
            int kalan = adet;

            for (int i = 0; i < yuzdeler.Count; i++)
            {
                int pay = i == yuzdeler.Count - 1
                    ? kalan
                    : Math.Min(kalan, (yuzdeler[i].Value * adet + 50) / 100);
                sonuc[yuzdeler[i].Key] = pay;
                kalan -= pay;
            }

            return sonuc;
        }

        // Veritabanındaki kademe metni ('unlu', 'bilinen', 'diger', 'cevap' ya da null). Elle düzeltme doluysa o geçerlidir.
        // Havuz dışındaysa null döner.
        public static Kademe? Coz(string? kademe, string? kademeOverride) => (kademeOverride ?? kademe) switch
        {
            "unlu" => Kademe.Unlu,
            "bilinen" => Kademe.Bilinen,
            "diger" => Kademe.Diger,
            _ => null
        };

        // Bir sorunun kademesi, cevaplarından en bilineninin kademesidir. Havuzdan hiç cevabı yoksa null.
        public static Kademe? EnBilinen(IEnumerable<string> oyuncuIdleri, IReadOnlyDictionary<string, Kademe> kademeler)
        {
            Kademe? enIyi = null;
            foreach (var id in oyuncuIdleri)
            {
                if (kademeler.TryGetValue(id, out var k) && (enIyi == null || k < enIyi))
                {
                    enIyi = k;
                    if (k == Kademe.Unlu) break;
                }
            }
            return enIyi;
        }

        // İstenen kademede soru kalmadıysa yerine kullanılabilecekler: önce kendisi, sonra daha bilinenler.
        // Diğer yerine bilinen, o da yoksa ünlü kullanılır; mod hiçbir zaman istenenden zorlaşmaz.
        public static IReadOnlyList<Kademe> YedekSirasi(Kademe istenen) => istenen switch
        {
            Kademe.Unlu => new[] { Kademe.Unlu },
            Kademe.Bilinen => new[] { Kademe.Bilinen, Kademe.Unlu },
            _ => new[] { Kademe.Diger, Kademe.Bilinen, Kademe.Unlu }
        };

        // Veritabanındaki oyun tipi: kesisim_kolay, bonservis_orta, izgara_zor ...
        public static string OyunTipi(string oyun, Zorluk zorluk) => $"{oyun}_{zorluk.ToString().ToLowerInvariant()}";

        public static string Metin(Kademe kademe) => kademe switch
        {
            Kademe.Unlu => "unlu",
            Kademe.Bilinen => "bilinen",
            _ => "diger"
        };
    }
}
