using Coravel.Invocable;
using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Supabase;
using ScoutIQ.API.Models;
using ScoutIQ.API.Oyunlar;
using System.Linq;
using static Supabase.Postgrest.Constants;
using Supabase.Postgrest.Interfaces;
using Supabase.Postgrest.Models;

namespace ScoutIQ.API.Jobs
{
    // Her gece her oyunun üç modunu (kolay, orta, zor) ayrı günlük oyun olarak üretir: kesisim_kolay, bonservis_orta,
    // izgara_zor ... Kullanıcı her oyunda günde bunlardan yalnızca birini oynar (019_zorluk_modlari.sql).
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

            Dictionary<string, Kademe> kademeler;
            try
            {
                kademeler = await KademeleriOku();
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Oyuncu kademeleri okunamadı, oyun üretilmedi: {ex.Message}");
                return;
            }

            // Oyunlar ayrı ayrı denenir: birinde hata olursa diğeri yine üretilir
            try
            {
                await UretKesisimOyunlari(bugun, kademeler);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Kesişim: hata oluştu: {ex.Message}");
            }

            try
            {
                await UretBonservisOyunlari(bugun, kademeler);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Bonservis: hata oluştu: {ex.Message}");
            }

            try
            {
                await UretIzgaraOyunlari(bugun, kademeler);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Izgara: hata oluştu: {ex.Message}");
            }
        }

        // Soru havuzundaki oyuncuların kademeleri: oyuncu id -> kademe. Elle düzeltme (kademe_override) doluysa o geçerlidir.
        // Elle düzeltmeler havuz dışındaki oyuncuları da havuza alabildiği için bütün oyuncular okunur.
        private async Task<Dictionary<string, Kademe>> KademeleriOku()
        {
            var kademeler = new Dictionary<string, Kademe>();
            foreach (var o in await HepsiniOku<Oyuncu>("id, kademe, kademe_override", o => o.Id))
            {
                var kademe = ZorlukDagilimi.Coz(o.Kademe, o.KademeOverride);
                if (kademe != null) kademeler[o.Id] = kademe.Value;
            }

            var sayilar = kademeler.Values.GroupBy(k => k).ToDictionary(g => g.Key, g => g.Count());
            Console.WriteLine($"Kademeler: {sayilar.GetValueOrDefault(Kademe.Unlu)} ünlü, {sayilar.GetValueOrDefault(Kademe.Bilinen)} bilinen, " +
                              $"{sayilar.GetValueOrDefault(Kademe.Diger)} diğer oyuncu.");
            if (kademeler.Count == 0)
            {
                throw new InvalidOperationException("Hiçbir oyuncunun kademesi yok (data_miner/kademeler.py çalıştırılmamış).");
            }
            return kademeler;
        }

        // ---------------- Izgara ----------------

        private async Task UretIzgaraOyunlari(DateTime tarih, Dictionary<string, Kademe> kademeler)
        {
            var eksikler = await EksikModlar("izgara", tarih);
            if (eksikler.Count == 0) return;

            var veri = await IzgaraVerisiniOku();
            foreach (var zorluk in eksikler)
            {
                var izgara = new IzgaraSoruSecici().Sec(zorluk, veri.Kulupler, veri.Kariyer, veri.MilliKariyer, kademeler);
                if (izgara == null)
                {
                    Console.WriteLine($"Uyarı: Izgara ({zorluk}) için kurallara uyan tahta kurulamadı.");
                    continue;
                }

                await OyunEkle("izgara", zorluk, tarih, IzgaraSoruVerisi(izgara));
                IzgarayiYaz(izgara);
            }
        }

        // Veritabanına yazmadan her moddan bir tahta seçip ekrana basar:
        // dotnet run -- --izgara-onizleme
        public async Task IzgaraOnizleme()
        {
            var kademeler = await KademeleriOku();
            var veri = await IzgaraVerisiniOku(ayrintili: true);
            foreach (var zorluk in Enum.GetValues<Zorluk>())
            {
                var izgara = new IzgaraSoruSecici().Sec(zorluk, veri.Kulupler, veri.Kariyer, veri.MilliKariyer, kademeler);
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
            var kulupler = await KulupleriOku();
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
                cevap_sayilari = izgara.CevapSayilari,
                hucre_kademeleri = izgara.HucreKademeleri.Select(ZorlukDagilimi.Metin).ToList()
            };
        }

        private static void IzgarayiYaz(IzgaraSoruSecici.Izgara izgara)
        {
            Console.WriteLine($"   {"",-22}" + string.Join("", izgara.Sutunlar.Select(s => $"{s.Isim,-26}")));
            for (int s = 0; s < IzgaraSoruSecici.Boyut; s++)
            {
                var hucreler = Enumerable.Range(0, IzgaraSoruSecici.Boyut).Select(t =>
                {
                    int i = s * IzgaraSoruSecici.Boyut + t;
                    return $"{$"{izgara.CevapSayilari[i]} cevap, {ZorlukDagilimi.Metin(izgara.HucreKademeleri[i])}",-26}";
                });
                Console.WriteLine($"   {izgara.Satirlar[s].Isim,-22}" + string.Join("", hucreler));
            }
        }

        // ---------------- Kesişim ----------------

        private async Task UretKesisimOyunlari(DateTime tarih, Dictionary<string, Kademe> kademeler)
        {
            var eksikler = await EksikModlar("kesisim", tarih);
            if (eksikler.Count == 0) return;

            var veri = await KesisimVerisiniOku();
            foreach (var zorluk in eksikler)
            {
                var sorular = KesisimSorulariniSec(zorluk, veri, kademeler);
                if (sorular == null) continue;

                await OyunEkle("kesisim", zorluk, tarih, sorular.Select(s => new
                {
                    kulup_a = s.KulupA.Isim,
                    kulup_b = s.KulupB.Isim,
                    kulup_a_id = s.KulupA.Id,
                    kulup_b_id = s.KulupB.Id,
                    kulup_a_logo = s.KulupA.LogoUrl,
                    kulup_b_logo = s.KulupB.LogoUrl,
                    kademe = ZorlukDagilimi.Metin(s.Kademe),
                    // Uygulamadaki soru etiketi: ünlü soru kolay, bilinen orta, diğer zor görünür
                    zorluk = s.Kademe switch { Kademe.Unlu => "kolay", Kademe.Bilinen => "orta", _ => "zor" }
                }).ToList());
                KesisimSorulariniYaz(sorular);
            }
        }

        // Veritabanına yazmadan her moddan bir soru seti seçip ekrana basar:
        // dotnet run -- --kesisim-onizleme
        public async Task KesisimOnizleme()
        {
            var kademeler = await KademeleriOku();
            var veri = await KesisimVerisiniOku(ayrintili: true);
            foreach (var zorluk in Enum.GetValues<Zorluk>())
            {
                Console.WriteLine($"\nKesişim ({zorluk}) önizleme (veritabanına yazılmadı):");
                var sorular = KesisimSorulariniSec(zorluk, veri, kademeler);
                if (sorular != null) KesisimSorulariniYaz(sorular);
            }
        }

        private record KesisimVerisi(List<Kulup> Kulupler, List<KariyerGecmisi> Kariyer);

        private async Task<KesisimVerisi> KesisimVerisiniOku(bool ayrintili = false)
        {
            var kulupler = await KulupleriOku();
            KulupListesiniKontrolEt(KesisimSoruSecici.BuyukKulupler, "büyük", kulupler, ayrintili);
            KulupListesiniKontrolEt(KesisimSoruSecici.BasAltiKulupler, "baş altı", kulupler, ayrintili);

            var kariyer = await KulupKariyerleri(KesisimSoruSecici.ListedekiKulupIdleri(KesisimSoruSecici.Kulupler, kulupler));
            return new KesisimVerisi(kulupler, kariyer);
        }

        private static List<KesisimSoruSecici.KesisimSorusu>? KesisimSorulariniSec(
            Zorluk zorluk, KesisimVerisi veri, Dictionary<string, Kademe> kademeler)
        {
            var sonuc = new KesisimSoruSecici().Sec(zorluk, veri.Kulupler, veri.Kariyer, kademeler);

            var havuz = sonuc.HavuzBoyutlari;
            Console.WriteLine($"Kesişim ({zorluk}) havuzları: {havuz[Kademe.Unlu]} ünlü, {havuz[Kademe.Bilinen]} bilinen, {havuz[Kademe.Diger]} diğer çift.");
            foreach (var uyari in sonuc.Uyarilar)
            {
                Console.WriteLine($"Uyarı: {uyari}");
            }

            return sonuc.Sorular;
        }

        private static void KesisimSorulariniYaz(List<KesisimSoruSecici.KesisimSorusu> sorular)
        {
            for (int i = 0; i < sorular.Count; i++)
            {
                var s = sorular[i];
                Console.WriteLine($"   {i + 1}. [{ZorlukDagilimi.Metin(s.Kademe)}] {s.KulupA.Isim} x {s.KulupB.Isim} ({s.OrtakOyuncuSayisi} ortak oyuncu)");
            }
        }

        // ---------------- Bonservis ----------------

        private async Task UretBonservisOyunlari(DateTime tarih, Dictionary<string, Kademe> kademeler)
        {
            var eksikler = await EksikModlar("bonservis", tarih);
            if (eksikler.Count == 0) return;

            var adaylar = await BonservisAdaylari(kademeler);
            if (adaylar == null) return;

            foreach (var zorluk in eksikler)
            {
                var sorular = new BonservisSoruSecici().Sec(zorluk, adaylar);
                if (sorular == null)
                {
                    Console.WriteLine($"Uyarı: Bonservis ({zorluk}) için kurallara uyan 5 soruluk set kurulamadı.");
                    continue;
                }

                // Toplam bonservisler de kaydedilir: cevaptan sonra ekranda gösterilir
                await OyunEkle("bonservis", zorluk, tarih, sorular.Select(s => new
                {
                    oyuncu_a = s.Sol.Isim,
                    oyuncu_b = s.Sag.Isim,
                    oyuncu_a_id = s.Sol.Id,
                    oyuncu_b_id = s.Sag.Id,
                    oyuncu_a_bonservis = s.Sol.ToplamBonservis,
                    oyuncu_b_bonservis = s.Sag.ToplamBonservis,
                    oyuncu_a_foto = s.Sol.FotoUrl,
                    oyuncu_b_foto = s.Sag.FotoUrl,
                    oyuncu_a_kademe = ZorlukDagilimi.Metin(s.Sol.Kademe),
                    oyuncu_b_kademe = ZorlukDagilimi.Metin(s.Sag.Kademe)
                }).ToList());
                BonservisSorulariniYaz(sorular);
            }
        }

        // Veritabanına yazmadan her moddan bir Bonservis soru seti seçip ekrana basar:
        // dotnet run -- --bonservis-onizleme
        public async Task BonservisOnizleme()
        {
            var kademeler = await KademeleriOku();
            var adaylar = await BonservisAdaylari(kademeler, ayrintili: true);
            if (adaylar == null) return;

            foreach (var zorluk in Enum.GetValues<Zorluk>())
            {
                Console.WriteLine($"\nBonservis ({zorluk}) önizleme (veritabanına yazılmadı):");
                var sorular = new BonservisSoruSecici().Sec(zorluk, adaylar);
                if (sorular == null)
                    Console.WriteLine("   Kurallara uyan 5 soruluk set kurulamadı.");
                else
                    BonservisSorulariniYaz(sorular);
            }
        }

        private static void BonservisSorulariniYaz(List<BonservisSoruSecici.BonservisSorusu> sorular)
        {
            string Oyuncu(BonservisSoruSecici.Aday a) => $"{a.Isim} ({Milyon(a.ToplamBonservis)}, {ZorlukDagilimi.Metin(a.Kademe)})";

            for (int i = 0; i < sorular.Count; i++)
            {
                var s = sorular[i];
                Console.WriteLine($"   {i + 1}. {Oyuncu(s.Sol)} x {Oyuncu(s.Sag)} -> doğru: {s.Dogru.Isim}");
            }
        }

        private static string Milyon(long euro) => $"{euro / 1_000_000.0:0.#} M€";

        // Listedeki kulüplerde güncel sezonda oynayan, toplam bonservisi yeterli ve soru havuzunda olan oyuncular
        private async Task<List<BonservisSoruSecici.Aday>?> BonservisAdaylari(Dictionary<string, Kademe> kademeler, bool ayrintili = false)
        {
            var kulupler = await KulupleriOku();
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
                .Where(o => guncelOyuncular.Contains(o.Id) && kademeler.ContainsKey(o.Id))
                .Select(o => new BonservisSoruSecici.Aday(o.Id, o.Isim, o.ToplamBonservis, kademeler[o.Id], o.FotoUrl))
                .ToList();

            var sayilar = adaylar.GroupBy(a => a.Kademe).ToDictionary(g => g.Key, g => g.Count());
            Console.WriteLine($"Bonservis havuzu: {guncelSezon}/{guncelSezon + 1} sezonunda {guncelOyuncular.Count} oyuncu; toplam bonservisi " +
                              $"{Milyon(BonservisSoruSecici.MinToplamBonservis)} üstünde olan {sayilar.GetValueOrDefault(Kademe.Unlu)} ünlü, " +
                              $"{sayilar.GetValueOrDefault(Kademe.Bilinen)} bilinen, {sayilar.GetValueOrDefault(Kademe.Diger)} diğer oyuncu.");
            return adaylar;
        }

        // ---------------- Ortak ----------------

        // Bugün için henüz üretilmemiş modlar
        private async Task<List<Zorluk>> EksikModlar(string oyun, DateTime tarih)
        {
            var eksikler = new List<Zorluk>();
            foreach (var zorluk in Enum.GetValues<Zorluk>())
            {
                if (await OyunVarMi(ZorlukDagilimi.OyunTipi(oyun, zorluk), tarih))
                    Console.WriteLine($"{oyun} ({zorluk}): {tarih:yyyy-MM-dd} için oyun zaten var, atlanıyor.");
                else
                    eksikler.Add(zorluk);
            }
            return eksikler;
        }

        private async Task OyunEkle(string oyun, Zorluk zorluk, DateTime tarih, object soruVerisi)
        {
            await _supabaseClient.From<GunlukOyun>().Insert(new GunlukOyun
            {
                OyunTipi = ZorlukDagilimi.OyunTipi(oyun, zorluk),
                Tarih = tarih,
                SoruVerisi = soruVerisi
            });
            Console.WriteLine($"Başarılı: {ZorlukDagilimi.OyunTipi(oyun, zorluk)} için {tarih:yyyy-MM-dd} tarihli oyun eklendi.");
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

        private async Task<List<Kulup>> KulupleriOku() =>
            (await _supabaseClient.From<Kulup>().Select("id, isim, lig, transfermarkt_id, logo_url").Get()).Models;

        // Tablonun filtreye uyan bütün satırlarını okur. Supabase tek istekte en fazla 1000 satır döndürdüğü için satırlar
        // id sırasıyla, her istekte son okunan id'den sonrası istenerek parça parça okunur. Atlamalı (offset) sayfalama
        // kullanılmaz: PostgREST son sayfada toplam satır sayısını tahminle hesaplayıp gerçekte var olan satırları
        // "yok" sayabiliyor (PGRST103), bu yüzden son sayfadaki kayıtlar kayboluyordu.
        private async Task<List<T>> HepsiniOku<T>(string kolonlar, Func<T, string> idSec,
            Func<IPostgrestTable<T>, IPostgrestTable<T>>? filtre = null) where T : BaseModel, new()
        {
            var tumu = new List<T>();
            string? sonId = null;

            while (true)
            {
                IPostgrestTable<T> sorgu = _supabaseClient.From<T>().Select(kolonlar);
                if (filtre != null) sorgu = filtre(sorgu);
                if (sonId != null) sorgu = sorgu.Filter("id", Operator.GreaterThan, sonId);

                var sayfa = (await sorgu.Order("id", Ordering.Ascending).Limit(SayfaBoyutu).Get()).Models;
                tumu.AddRange(sayfa);
                if (sayfa.Count < SayfaBoyutu) return tumu;
                sonId = idSec(sayfa[^1]);
            }
        }

        private Task<List<MilliTakimKariyeri>> TumMilliTakimKariyeri() =>
            HepsiniOku<MilliTakimKariyeri>("id, oyuncu_id, milli_takim_tm_id, milli_takim_isim", m => m.Id);

        // Verilen kulüplerin kariyer kayıtları (oyuncu, kulüp, son sezon, maç sayısı)
        private Task<List<KariyerGecmisi>> KulupKariyerleri(HashSet<string> kulupIdleri)
        {
            var idler = kulupIdleri.Cast<object>().ToList();
            return HepsiniOku<KariyerGecmisi>("id, oyuncu_id, kulup_id, bitis_yili, mac_sayisi", k => k.Id,
                s => s.Filter("kulup_id", Operator.In, idler));
        }

        // Toplam bonservisi alt sınırın üzerindeki tüm oyuncular
        private Task<List<Oyuncu>> PahaliOyuncular() =>
            HepsiniOku<Oyuncu>("id, isim, toplam_bonservis, foto_url", o => o.Id,
                s => s.Filter("toplam_bonservis", Operator.GreaterThan, BonservisSoruSecici.MinToplamBonservis.ToString()));

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
