using System;
using System.Collections.Generic;
using System.Linq;
using ScoutIQ.API.Models;

namespace ScoutIQ.API.Oyunlar
{
    // Kolay Kesişim'in sorularını seçer. Veritabanına dokunmaz: kulüpleri, kariyerleri, oyuncu kademelerini ve önceki
    // günlerin sorularını parametre olarak alır, böylece kurallar gerçek veri olmadan test edilebilir.
    //
    // Sorular oyuncudan başlanarak kurulur: önce ünlü bir "hedef oyuncu" seçilir, gösterilen iki kulüp onun kariyerindeki
    // büyük kulüplerden rastgele seçilir. Hedef oyuncu sadece "bu çiftin en az bir ünlü cevabı var" garantisidir:
    // cevap kontrolü ona bakmaz, iki kulüpte de oynamış her oyuncu doğru cevaptır.
    //   - Hedef olabilmek için oyuncu ünlü olmalı ve en az iki büyük kulüpte yeterince maça çıkmış olmalıdır
    //     (KariyerGecmisi.MinSoruMaci). Aynı oyuncu-kulüp eşleşmesi kariyerde birden fazla geçse de bir kez sayılır.
    //   - Hedef olmuş oyuncu, kullanılmamış uygun hedef kaldıkça tekrar hedef olmaz. Kalmayınca en uzun süredir
    //     hedef olmamış oyuncudan başlanarak tekrar edilir.
    //   - Aynı kulüp çifti CiftTekrarGunu gün geçmeden tekrar sorulmaz (çift sırasızdır). Bu kuralla 5 soru
    //     kurulamazsa o gün için esnetilir: en uzun süredir sorulmamış çiftler seçilir. Soru üretilmeyen gün olmaz.
    //   - Bir oyunda aynı kulüp iki kez çıkmaz, aynı oyuncu iki soruya hedef olmaz.
    public class KolayKesisimSecici
    {
        public const int SoruSayisi = KesisimSoruSecici.SoruSayisi;

        // Aynı kulüp çifti bu kadar gün geçmeden tekrar sorulmaz. Ünlü oyuncusu olan yaklaşık 147 büyük kulüp çifti var
        // ve günde 5 soru soruluyor: çiftler en fazla 29 günde biter, daha uzun bir süre her gece sağlanamaz.
        public const int CiftTekrarGunu = 21;

        // Önceki bir sorunun hedef oyuncusu ve kulüp çifti (kulüplerin sırası önemsizdir)
        public record Gecmis(string OyuncuId, string KulupAId, string KulupBId, DateTime Tarih);

        // OrtakOyuncuSayisi: iki kulüpte de kaydı olan bütün oyuncular (cevap olarak kabul edilenler)
        public record Soru(Kulup KulupA, Kulup KulupB, int OrtakOyuncuSayisi, string HedefOyuncuId);

        // Sorular: 5 soru ya da kurulamadıysa null. Sayılar ve uyarılar günlüğe yazılmak içindir.
        public record SecimSonucu(List<Soru>? Sorular, int HedefSayisi, int KullanilmamisHedefSayisi, int CiftSayisi, List<string> Uyarilar);

        private readonly Random _random;

        public KolayKesisimSecici(Random? random = null)
        {
            _random = random ?? new Random();
        }

        // hedefTarih: soruların yayınlanacağı gün (normalde yarın). 21 günlük çift tekrarı bu güne göre sayılır.
        public SecimSonucu Sec(DateTime hedefTarih, IEnumerable<Kulup> kulupListesi, IEnumerable<KariyerGecmisi> kariyer,
            IReadOnlyDictionary<string, Kademe> kademeler, IEnumerable<Gecmis> gecmis)
        {
            var kulupler = kulupListesi.Where(k => k.Kademe == KulupKademeleri.Buyuk).ToDictionary(k => k.Id);
            var kayitlar = kariyer.Where(k => kulupler.ContainsKey(k.KulupId)).ToList();
            var tumOyuncular = kayitlar.GroupBy(k => k.KulupId).ToDictionary(g => g.Key, g => g.Select(k => k.OyuncuId).ToHashSet());

            // Hedef olabilecek oyuncular ve büyük kulüpleri. Sıralı tutulur ki aynı tohumla (seed) aynı sorular çıksın.
            var hedefler = kayitlar
                .Where(k => k.SoruyaUygun && kademeler.TryGetValue(k.OyuncuId, out var kademe) && kademe == Kademe.Unlu)
                .GroupBy(k => k.OyuncuId)
                .Select(g => (Oyuncu: g.Key, Kulupler: g.Select(k => k.KulupId).Distinct().OrderBy(id => id, StringComparer.Ordinal).ToList()))
                .Where(h => h.Kulupler.Count >= 2)
                .OrderBy(h => h.Oyuncu, StringComparer.Ordinal)
                .ToList();

            var sonHedef = new Dictionary<string, DateTime>();
            var sonCift = new Dictionary<(string, string), DateTime>();
            foreach (var g in gecmis)
            {
                if (!sonHedef.TryGetValue(g.OyuncuId, out var h) || g.Tarih > h) sonHedef[g.OyuncuId] = g.Tarih;
                var cift = Cift(g.KulupAId, g.KulupBId);
                if (!sonCift.TryGetValue(cift, out var c) || g.Tarih > c) sonCift[cift] = g.Tarih;
            }

            var ciftSayisi = hedefler.SelectMany(h => Ciftler(h.Kulupler)).Distinct().Count();
            var kullanilmamis = hedefler.Where(h => !sonHedef.ContainsKey(h.Oyuncu)).ToList();
            var kullanilmis = hedefler.Where(h => sonHedef.ContainsKey(h.Oyuncu)).ToList();
            Karistir(kullanilmamis);
            // En uzun süredir hedef olmamış oyuncu önce; aynı gün hedef olanların sırası rastgele
            Karistir(kullanilmis);
            kullanilmis = kullanilmis.OrderBy(h => sonHedef[h.Oyuncu]).ToList();

            var sorular = new List<Soru>();
            var uyarilar = new List<string>();
            var bugunkuKulupler = new HashSet<string>();
            var bugunkuHedefler = new HashSet<string>();

            bool CiftSorulabilir((string, string) cift) =>
                !sonCift.TryGetValue(cift, out var son) || (hedefTarih - son).Days >= CiftTekrarGunu;

            // Sıradaki hedeflerle soru ekler. ciftKurali false ise çift tekrarı kuralı esnetilir: en eski çift seçilir.
            int Ekle(List<(string Oyuncu, List<string> Kulupler)> adaylar, bool ciftKurali)
            {
                int eklenen = 0;
                foreach (var hedef in adaylar)
                {
                    if (sorular.Count == SoruSayisi) break;
                    if (bugunkuHedefler.Contains(hedef.Oyuncu)) continue;

                    var ciftler = Ciftler(hedef.Kulupler.Where(k => !bugunkuKulupler.Contains(k)).ToList()).ToList();
                    if (ciftKurali) ciftler = ciftler.Where(CiftSorulabilir).ToList();
                    if (ciftler.Count == 0) continue;

                    var secilen = ciftKurali
                        ? ciftler[_random.Next(ciftler.Count)]
                        : ciftler.OrderBy(c => sonCift.TryGetValue(c, out var son) ? son : DateTime.MinValue).First();

                    var (a, b) = (kulupler[secilen.Item1], kulupler[secilen.Item2]);
                    // Hangi kulübün solda görüneceği de rastgele olsun
                    if (_random.Next(2) == 0) (a, b) = (b, a);

                    sorular.Add(new Soru(a, b, tumOyuncular[a.Id].Count(tumOyuncular[b.Id].Contains), hedef.Oyuncu));
                    bugunkuHedefler.Add(hedef.Oyuncu);
                    bugunkuKulupler.Add(a.Id);
                    bugunkuKulupler.Add(b.Id);
                    eklenen++;
                }
                return eklenen;
            }

            Ekle(kullanilmamis, ciftKurali: true);

            int tekrarEden = Ekle(kullanilmis, ciftKurali: true);
            if (tekrarEden > 0)
                uyarilar.Add($"Uygun ve kullanılmamış hedef oyuncu yetmedi: {tekrarEden} soru daha önce hedef olmuş oyuncuyla kuruldu.");

            if (sorular.Count < SoruSayisi)
            {
                int esnetilen = Ekle(kullanilmamis.Concat(kullanilmis).ToList(), ciftKurali: false);
                if (esnetilen > 0)
                    uyarilar.Add($"{CiftTekrarGunu} günlük çift tekrarı kuralı {esnetilen} soru için esnetildi.");
            }

            if (sorular.Count < SoruSayisi)
            {
                uyarilar.Add($"Kesişim (Kolay) için {SoruSayisi} soru kurulamadı: {hedefler.Count} hedef oyuncu, {ciftSayisi} çift var.");
                return new SecimSonucu(null, hedefler.Count, kullanilmamis.Count, ciftSayisi, uyarilar);
            }

            return new SecimSonucu(sorular, hedefler.Count, kullanilmamis.Count, ciftSayisi, uyarilar);
        }

        // Çift sırasızdır: küçük ID her zaman önce gelir, böylece A-B ile B-A aynı çifttir
        public static (string, string) Cift(string a, string b) =>
            string.CompareOrdinal(a, b) <= 0 ? (a, b) : (b, a);

        private static IEnumerable<(string, string)> Ciftler(List<string> kulupIdleri)
        {
            for (int i = 0; i < kulupIdleri.Count; i++)
                for (int j = i + 1; j < kulupIdleri.Count; j++)
                    yield return Cift(kulupIdleri[i], kulupIdleri[j]);
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
