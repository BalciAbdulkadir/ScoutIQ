using Coravel.Invocable;
using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Supabase;
using ScoutIQ.API.Models;
using ScoutIQ.API.Oyunlar;
using System.Linq;
using static Supabase.Postgrest.Constants;

namespace ScoutIQ.API.Jobs
{
    public class DailyQuestionJob : IInvocable
    {
        // Oyun günleri Türkiye saatine göre başlar ve biter
        public static readonly TimeZoneInfo TurkiyeSaatDilimi = TimeZoneInfo.FindSystemTimeZoneById("Europe/Istanbul");

        private const int SayfaBoyutu = 1000; // Supabase tek istekte en fazla 1000 satır döndürür

        private readonly Client _supabaseClient;

        public DailyQuestionJob(Client supabaseClient)
        {
            _supabaseClient = supabaseClient;
        }

        public async Task Invoke()
        {
            DateTime bugun = TimeZoneInfo.ConvertTimeFromUtc(DateTime.UtcNow, TurkiyeSaatDilimi).Date;
            Console.WriteLine($"[{DateTime.Now}] CRON TETİKLENDİ: {bugun:yyyy-MM-dd} için Hub oyunları hazırlanıyor...");

            // Oyunlar ayrı ayrı denenir: birinde hata olursa diğeri yine üretilir
            try
            {
                await UretKesisimOyunlari(bugun);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Kesişim: hata oluştu: {ex.Message}");
            }

            try
            {
                await UretBonservisOyunlari(bugun);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Bonservis: hata oluştu: {ex.Message}");
            }

            try
            {
                await UretIzgaraOyunlari(bugun);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Izgara: hata oluştu: {ex.Message}");
            }
        }

        // Her zorluk ayrı bir oyundur: izgara_kolay, izgara_orta, izgara_zor
        public static string IzgaraOyunTipi(IzgaraSoruSecici.Zorluk zorluk) => $"izgara_{zorluk.ToString().ToLowerInvariant()}";

        private async Task UretIzgaraOyunlari(DateTime tarih)
        {
            var eksikler = new List<IzgaraSoruSecici.Zorluk>();
            foreach (var zorluk in Enum.GetValues<IzgaraSoruSecici.Zorluk>())
            {
                if (await OyunVarMi(IzgaraOyunTipi(zorluk), tarih))
                    Console.WriteLine($"Izgara ({zorluk}): {tarih:yyyy-MM-dd} için oyun zaten var, atlanıyor.");
                else
                    eksikler.Add(zorluk);
            }
            if (eksikler.Count == 0) return;

            var veri = await IzgaraVerisiniOku();
            foreach (var zorluk in eksikler)
            {
                var izgara = new IzgaraSoruSecici().Sec(zorluk, veri.Kulupler, veri.Kariyer, veri.MilliKariyer);
                if (izgara == null)
                {
                    Console.WriteLine($"Uyarı: Izgara ({zorluk}) için kurallara uyan tahta kurulamadı.");
                    continue;
                }

                await _supabaseClient.From<GunlukOyun>().Insert(new GunlukOyun
                {
                    OyunTipi = IzgaraOyunTipi(zorluk),
                    Tarih = tarih,
                    SoruVerisi = IzgaraSoruVerisi(izgara)
                });
                Console.WriteLine($"Başarılı: Izgara ({zorluk}) için {tarih:yyyy-MM-dd} tarihli tahta eklendi.");
                IzgarayiYaz(izgara);
            }
        }

        // Veritabanına yazmadan her zorluktan bir tahta seçip ekrana basar:
        // dotnet run -- --izgara-onizleme
        public async Task IzgaraOnizleme()
        {
            var veri = await IzgaraVerisiniOku(ayrintili: true);
            foreach (var zorluk in Enum.GetValues<IzgaraSoruSecici.Zorluk>())
            {
                var izgara = new IzgaraSoruSecici().Sec(zorluk, veri.Kulupler, veri.Kariyer, veri.MilliKariyer);
                Console.WriteLine($"\nIzgara ({zorluk}) önizleme (veritabanına yazılmadı):");
                if (izgara == null)
                    Console.WriteLine("   Kurallara uyan tahta kurulamadı.");
                else
                    IzgarayiYaz(izgara);
            }
        }

        private record IzgaraVerisi(List<Kulup> Kulupler, List<KariyerGecmisi> Kariyer, List<MilliTakimKariyeri> MilliKariyer);

        private async Task<IzgaraVerisi> IzgaraVerisiniOku(bool ayrintili = false)
        {
            var kulupler = (await _supabaseClient.From<Kulup>().Select("id, isim, lig, transfermarkt_id, logo_url").Get()).Models;
            KulupListesiniKontrolEt(IzgaraSoruSecici.Kulupler, "Izgara", kulupler, ayrintili);

            var kulupIdleri = KesisimSoruSecici.ListedekiKulupIdleri(IzgaraSoruSecici.Kulupler, kulupler);
            var kariyer = await KulupKariyerleri(kulupIdleri);
            var milliKariyer = await TumMilliTakimKariyeri();

            Console.WriteLine($"Izgara verisi: {kulupIdleri.Count} kulüpte {kariyer.Count} kariyer kaydı, {milliKariyer.Count} milli takım kaydı.");
            return new IzgaraVerisi(kulupler, kariyer, milliKariyer);
        }

        // Uygulama başlıkları gösterir; cevap sayıları sunucuda, oyuncu birden fazla boş hücreye uyuyorsa
        // hangisine yerleşeceğini seçmek için kullanılır. Cevapların kendisi tahtada yoktur.
        private static object IzgaraSoruVerisi(IzgaraSoruSecici.Izgara izgara)
        {
            object Baslik(IzgaraSoruSecici.Baslik b) => new
            {
                tip = b.Tip == IzgaraSoruSecici.BaslikTipi.Kulup ? "kulup" : "milli",
                id = b.KulupId,
                tm_id = b.TmId,
                isim = b.Isim,
                logo = b.LogoUrl
            };

            return new
            {
                satirlar = izgara.Satirlar.Select(Baslik).ToList(),
                sutunlar = izgara.Sutunlar.Select(Baslik).ToList(),
                cevap_sayilari = izgara.CevapSayilari
            };
        }

        private static void IzgarayiYaz(IzgaraSoruSecici.Izgara izgara)
        {
            Console.WriteLine($"   {"",-22}" + string.Join("", izgara.Sutunlar.Select(s => $"{s.Isim,-22}")));
            for (int s = 0; s < IzgaraSoruSecici.Boyut; s++)
            {
                var sayilar = Enumerable.Range(0, IzgaraSoruSecici.Boyut)
                    .Select(t => $"{izgara.CevapSayilari[s * IzgaraSoruSecici.Boyut + t] + " cevap",-22}");
                Console.WriteLine($"   {izgara.Satirlar[s].Isim,-22}" + string.Join("", sayilar));
            }
        }

        private async Task<List<MilliTakimKariyeri>> TumMilliTakimKariyeri()
        {
            var tumu = new List<MilliTakimKariyeri>();

            for (int bas = 0; ; bas += SayfaBoyutu)
            {
                var sayfa = await _supabaseClient.From<MilliTakimKariyeri>()
                    .Select("oyuncu_id, milli_takim_tm_id, milli_takim_isim")
                    .Order("oyuncu_id", Ordering.Ascending)
                    .Order("milli_takim_tm_id", Ordering.Ascending)
                    .Range(bas, bas + SayfaBoyutu - 1)
                    .Get();

                tumu.AddRange(sayfa.Models);
                if (sayfa.Models.Count < SayfaBoyutu) break;
            }

            return tumu;
        }

        private async Task<bool> OyunVarMi(string oyunTipi, DateTime tarih)
        {
            var response = await _supabaseClient.From<GunlukOyun>()
                .Select("id")
                .Filter("oyun_tipi", Operator.Equals, oyunTipi)
                .Filter("tarih", Operator.Equals, tarih.ToString("yyyy-MM-dd"))
                .Get();

            return response.Models.Count > 0;
        }

        private async Task UretKesisimOyunlari(DateTime tarih)
        {
            if (await OyunVarMi("kesisim", tarih))
            {
                Console.WriteLine($"Kesişim: {tarih:yyyy-MM-dd} için oyun zaten var, atlanıyor.");
                return;
            }

            var sorular = await KesisimSorulariniSec();
            if (sorular == null) return;

            var yeniOyun = new GunlukOyun
            {
                OyunTipi = "kesisim",
                Tarih = tarih,
                SoruVerisi = sorular.Select(s => new
                {
                    kulup_a = s.Cift.KulupA.Isim,
                    kulup_b = s.Cift.KulupB.Isim,
                    kulup_a_id = s.Cift.KulupA.Id,
                    kulup_b_id = s.Cift.KulupB.Id,
                    kulup_a_logo = s.Cift.KulupA.LogoUrl,
                    kulup_b_logo = s.Cift.KulupB.LogoUrl,
                    zorluk = s.Zorluk.ToString().ToLowerInvariant()
                }).ToList()
            };

            await _supabaseClient.From<GunlukOyun>().Insert(yeniOyun);
            Console.WriteLine($"Başarılı: Kesişim için {tarih:yyyy-MM-dd} tarihli 5 soruluk set eklendi.");
            foreach (var soru in sorular)
            {
                Console.WriteLine($"   [{soru.Zorluk}] {soru.Cift.KulupA.Isim} x {soru.Cift.KulupB.Isim} ({soru.Cift.OrtakOyuncuSayisi} ortak oyuncu)");
            }
        }

        // Veritabanına yazmadan bir soru seti seçip ekrana basar. Zorluk eşiklerini ayarlarken kullanılır:
        // dotnet run -- --kesisim-onizleme
        public async Task KesisimOnizleme()
        {
            var sorular = await KesisimSorulariniSec(ayrintili: true);
            if (sorular == null) return;

            Console.WriteLine("Önizleme (veritabanına yazılmadı):");
            for (int i = 0; i < sorular.Count; i++)
            {
                var soru = sorular[i];
                Console.WriteLine($"   {i + 1}. [{soru.Zorluk}] {soru.Cift.KulupA.Isim} x {soru.Cift.KulupB.Isim} ({soru.Cift.OrtakOyuncuSayisi} ortak oyuncu)");
            }
        }

        // Kulüpleri ve kariyer geçmişini veritabanından çeker, seçimi KesisimSoruSecici'ye bırakır
        private async Task<List<KesisimSoruSecici.KesisimSorusu>?> KesisimSorulariniSec(bool ayrintili = false)
        {
            var kuluplerResponse = await _supabaseClient.From<Kulup>().Select("id, isim, lig, transfermarkt_id, logo_url").Get();
            var kulupler = kuluplerResponse.Models;

            if (kulupler.Count < 2)
            {
                Console.WriteLine("Uyarı: Kesişim için veritabanında yeterli kulüp yok.");
                return null;
            }

            KulupListesiniKontrolEt(KesisimSoruSecici.BuyukKulupler, "büyük", kulupler, ayrintili);
            KulupListesiniKontrolEt(KesisimSoruSecici.BasAltiKulupler, "baş altı", kulupler, ayrintili);

            var sonuc = new KesisimSoruSecici().Sec(kulupler, await TumKariyerGecmisi());

            var havuz = sonuc.HavuzBoyutlari;
            Console.WriteLine($"Kesişim havuzları: {havuz[KesisimSoruSecici.Zorluk.Kolay]} kolay, {havuz[KesisimSoruSecici.Zorluk.Orta]} orta-zor, {havuz[KesisimSoruSecici.Zorluk.Zor]} zor çift.");
            foreach (var uyari in sonuc.Uyarilar)
            {
                Console.WriteLine($"Uyarı: {uyari}");
            }

            return sonuc.Sorular;
        }

        private async Task UretBonservisOyunlari(DateTime tarih)
        {
            if (await OyunVarMi("bonservis", tarih))
            {
                Console.WriteLine($"Bonservis: {tarih:yyyy-MM-dd} için oyun zaten var, atlanıyor.");
                return;
            }

            var sorular = await BonservisSorulariniSec();
            if (sorular == null) return;

            // Toplam bonservisler de kaydedilir: cevaptan sonra ekranda gösterilir
            var yeniOyun = new GunlukOyun
            {
                OyunTipi = "bonservis",
                Tarih = tarih,
                SoruVerisi = sorular.Select(s => new
                {
                    oyuncu_a = s.Sol.Isim,
                    oyuncu_b = s.Sag.Isim,
                    oyuncu_a_id = s.Sol.Id,
                    oyuncu_b_id = s.Sag.Id,
                    oyuncu_a_bonservis = s.Sol.ToplamBonservis,
                    oyuncu_b_bonservis = s.Sag.ToplamBonservis,
                    oyuncu_a_foto = s.Sol.FotoUrl,
                    oyuncu_b_foto = s.Sag.FotoUrl
                }).ToList()
            };

            await _supabaseClient.From<GunlukOyun>().Insert(yeniOyun);
            Console.WriteLine($"Başarılı: Bonservis için {tarih:yyyy-MM-dd} tarihli 5 soruluk set eklendi.");
            BonservisSorulariniYaz(sorular);
        }

        // Veritabanına yazmadan bir Bonservis soru seti seçip ekrana basar:
        // dotnet run -- --bonservis-onizleme
        public async Task BonservisOnizleme()
        {
            var sorular = await BonservisSorulariniSec(ayrintili: true);
            if (sorular == null) return;

            Console.WriteLine("Önizleme (veritabanına yazılmadı):");
            BonservisSorulariniYaz(sorular);
        }

        private static void BonservisSorulariniYaz(List<BonservisSoruSecici.BonservisSorusu> sorular)
        {
            for (int i = 0; i < sorular.Count; i++)
            {
                var s = sorular[i];
                Console.WriteLine($"   {i + 1}. {s.Sol.Isim} ({Milyon(s.Sol.ToplamBonservis)}) x {s.Sag.Isim} ({Milyon(s.Sag.ToplamBonservis)}) -> doğru: {s.Dogru.Isim}");
            }
        }

        private static string Milyon(long euro) => $"{euro / 1_000_000.0:0.#} M€";

        // Listedeki kulüplerde güncel sezonda oynayan, toplam bonservisi yeterli oyuncuları çeker,
        // seçimi BonservisSoruSecici'ye bırakır
        private async Task<List<BonservisSoruSecici.BonservisSorusu>?> BonservisSorulariniSec(bool ayrintili = false)
        {
            var kulupler = (await _supabaseClient.From<Kulup>().Select("id, isim, lig, transfermarkt_id").Get()).Models;
            KulupListesiniKontrolEt(BonservisSoruSecici.Kulupler, "Bonservis", kulupler, ayrintili);

            var kulupIdleri = KesisimSoruSecici.ListedekiKulupIdleri(BonservisSoruSecici.Kulupler, kulupler);
            var kariyer = await KulupKariyerleri(kulupIdleri);
            if (kariyer.Count == 0)
            {
                Console.WriteLine("Uyarı: Bonservis kulüpleri için kariyer verisi yok.");
                return null;
            }

            // Güncel sezon: bu kulüpler için veritabanındaki en son sezon
            int guncelSezon = kariyer.Max(k => k.BitisYili ?? 0);
            var guncelOyuncular = kariyer.Where(k => k.BitisYili == guncelSezon).Select(k => k.OyuncuId).ToHashSet();

            var adaylar = (await PahaliOyuncular())
                .Where(o => guncelOyuncular.Contains(o.Id))
                .Select(o => new BonservisSoruSecici.Aday(o.Id, o.Isim, o.ToplamBonservis, o.FotoUrl))
                .ToList();

            Console.WriteLine($"Bonservis havuzu: {guncelSezon}/{guncelSezon + 1} sezonunda {guncelOyuncular.Count} oyuncu, " +
                              $"toplam bonservisi {Milyon(BonservisSoruSecici.MinToplamBonservis)} üstünde olan {adaylar.Count} oyuncu.");

            var sorular = new BonservisSoruSecici().Sec(adaylar);
            if (sorular == null)
            {
                Console.WriteLine("Uyarı: Bonservis için kurallara uyan 5 soruluk zincir kurulamadı.");
            }
            return sorular;
        }

        // Verilen kulüplerin kariyer kayıtları (oyuncu, kulüp, son sezon)
        private async Task<List<KariyerGecmisi>> KulupKariyerleri(HashSet<string> kulupIdleri)
        {
            var tumu = new List<KariyerGecmisi>();
            var filtre = kulupIdleri.Cast<object>().ToList();

            for (int bas = 0; ; bas += SayfaBoyutu)
            {
                var sayfa = await _supabaseClient.From<KariyerGecmisi>()
                    .Select("oyuncu_id, kulup_id, bitis_yili")
                    .Filter("kulup_id", Operator.In, filtre)
                    .Order("oyuncu_id", Ordering.Ascending)
                    .Order("kulup_id", Ordering.Ascending)
                    .Range(bas, bas + SayfaBoyutu - 1)
                    .Get();

                tumu.AddRange(sayfa.Models);
                if (sayfa.Models.Count < SayfaBoyutu) break;
            }

            return tumu;
        }

        // Toplam bonservisi alt sınırın üzerindeki tüm oyuncular
        private async Task<List<Oyuncu>> PahaliOyuncular()
        {
            var tumu = new List<Oyuncu>();

            for (int bas = 0; ; bas += SayfaBoyutu)
            {
                var sayfa = await _supabaseClient.From<Oyuncu>()
                    .Select("id, isim, toplam_bonservis, foto_url")
                    .Filter("toplam_bonservis", Operator.GreaterThan, BonservisSoruSecici.MinToplamBonservis.ToString())
                    .Order("id", Ordering.Ascending)
                    .Range(bas, bas + SayfaBoyutu - 1)
                    .Get();

                tumu.AddRange(sayfa.Models);
                if (sayfa.Models.Count < SayfaBoyutu) break;
            }

            return tumu;
        }

        private async Task<List<KariyerGecmisi>> TumKariyerGecmisi()
        {
            var tumu = new List<KariyerGecmisi>();

            // Sayfalar arasında satır kaymasın diye benzersiz (oyuncu_id, kulup_id) sırasıyla okunur
            for (int bas = 0; ; bas += SayfaBoyutu)
            {
                var sayfa = await _supabaseClient.From<KariyerGecmisi>()
                    .Select("oyuncu_id, kulup_id")
                    .Order("oyuncu_id", Ordering.Ascending)
                    .Order("kulup_id", Ordering.Ascending)
                    .Range(bas, bas + SayfaBoyutu - 1)
                    .Get();

                tumu.AddRange(sayfa.Models);
                if (sayfa.Models.Count < SayfaBoyutu) break;
            }

            return tumu;
        }

        // Listedeki kulüplerin veritabanında olup olmadığını kontrol eder; ayrıntılı modda eşleşmeleri listeler
        private static void KulupListesiniKontrolEt(IReadOnlyDictionary<string, string> liste, string listeAdi, List<Kulup> kulupler, bool ayrintili)
        {
            var bulunanlar = kulupler.Where(k => liste.ContainsKey(k.TransfermarktId)).ToList();

            var bulunamayanlar = liste.Keys.Except(bulunanlar.Select(k => k.TransfermarktId)).Select(id => liste[id]).ToList();
            if (bulunamayanlar.Count > 0)
            {
                Console.WriteLine($"Uyarı: Veritabanında bulunamayan {listeAdi} kulüpler: {string.Join(", ", bulunamayanlar)}");
            }

            if (ayrintili)
            {
                // Listedeki ID'lerin doğru kulübe denk geldiğini gözle kontrol etmek için
                Console.WriteLine($"{char.ToUpper(listeAdi[0])}{listeAdi[1..]} kulüpler (Transfermarkt ID -> veritabanındaki isim):");
                foreach (var kulup in bulunanlar.OrderBy(k => k.Lig).ThenBy(k => k.Isim))
                {
                    Console.WriteLine($"   {kulup.TransfermarktId,-6} {liste[kulup.TransfermarktId],-20} -> {kulup.Isim} ({kulup.Lig})");
                }
            }
        }
    }
}
