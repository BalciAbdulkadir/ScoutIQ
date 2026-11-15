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

            try
            {
                await UretBingoOyunlari(bugun, kademeler);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Bingo: hata oluştu: {ex.Message}");
            }

            try
            {
                await UretTop10Oyunu(bugun, kademeler);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Top 10: hata oluştu: {ex.Message}");
            }
        }

        // ---------------- Top 10 ----------------

        // Top 10'un zorluk modu yoktur: günde tek soru (oyun_tipi 'top10'). Cevap listesi soru verisine yazılmaz,
        // uygulamaya kapalı top10_cevaplari tablosunda tutulur (029_top10.sql).
        private const string Top10OyunTipi = "top10";

        private async Task UretTop10Oyunu(DateTime tarih, Dictionary<string, Kademe> kademeler)
        {
            if (await OyunVarMi(Top10OyunTipi, tarih))
            {
                Console.WriteLine($"top10: {tarih:yyyy-MM-dd} için oyun zaten var, atlanıyor.");
                return;
            }

            var veri = await Top10VerisiniOku();
            var soru = await Top10SorusunuSec(tarih, veri, kademeler);
            if (soru == null)
            {
                // Kurallara uyan soru yoksa boş ya da kurala uymayan soru yayınlanmaz
                Console.WriteLine("HATA: Top 10 için kurallara uyan soru kurulamadı, bugün Top 10 yayınlanmadı.");
                return;
            }

            var oyun = (await _supabaseClient.From<GunlukOyun>().Insert(new GunlukOyun
            {
                OyunTipi = Top10OyunTipi,
                Tarih = tarih,
                SoruVerisi = Top10SoruVerisi(soru, veri)
            })).Models.First();

            // Cevaplar yazılamazsa oyun cevapsız kalır: silinir, bir sonraki çalıştırmada yeniden üretilir
            try
            {
                await _supabaseClient.From<Top10Cevabi>().Insert(soru.Satirlar.Select(s => new Top10Cevabi
                {
                    OyunId = oyun.Id,
                    Sira = s.Sira,
                    OyuncuId = s.OyuncuId,
                    OyuncuIsim = veri.Oyuncular[s.OyuncuId].Isim,
                    Deger = s.Deger
                }).ToList());
                await _supabaseClient.From<Top10SorusuKaydi>().Insert(new Top10SorusuKaydi
                {
                    OyunId = oyun.Id,
                    Tarih = tarih,
                    Sablon = soru.Sablon,
                    Anahtar = soru.Anahtar,
                    Eksen = soru.Eksen
                });
            }
            catch
            {
                await _supabaseClient.From<GunlukOyun>().Where(g => g.Id == oyun.Id).Delete();
                throw;
            }

            Console.WriteLine($"Başarılı: top10 için {tarih:yyyy-MM-dd} tarihli soru eklendi.");
            Top10Yaz(soru, veri, kademeler);
        }

        // Veritabanına yazmadan bugünün Top 10 sorusunu seçip ekrana basar:
        // dotnet run -- --top10-onizleme
        public async Task Top10Onizleme()
        {
            var kademeler = await KademeleriOku();
            var veri = await Top10VerisiniOku();
            DateTime bugun = TimeZoneInfo.ConvertTimeFromUtc(DateTime.UtcNow, TurkiyeSaatDilimi).Date;
            Console.WriteLine("\nTop 10 önizleme (veritabanına yazılmadı):");
            var soru = await Top10SorusunuSec(bugun, veri, kademeler);
            if (soru != null) Top10Yaz(soru, veri, kademeler);
        }

        private async Task<Top10SoruSecici.Soru?> Top10SorusunuSec(DateTime tarih, Top10SoruSecici.Veri veri, Dictionary<string, Kademe> kademeler)
        {
            // Tekrar ve çeşitlilik kuralları için son TekrarGunu günün soruları
            var baslangic = tarih.AddDays(-Top10SoruSecici.TekrarGunu).ToString("yyyy-MM-dd");
            var gecmis = new List<Top10SoruSecici.Gecmis>();
            try
            {
                gecmis = (await HepsiniOku<Top10SorusuKaydi>("oyun_id, tarih, sablon, anahtar, eksen", g => g.OyunId,
                        s => s.Filter("tarih", Operator.GreaterThanOrEqual, baslangic)))
                    .Select(g => new Top10SoruSecici.Gecmis(g.Sablon, g.Anahtar, g.Eksen, g.Tarih.Date))
                    .ToList();
            }
            catch (Exception ex)
            {
                // Tablo yoksa (029 çalıştırılmamışsa) önizleme yine çalışır; oyun üretimi cevapları yazarken durur
                Console.WriteLine($"Uyarı: Önceki Top 10 soruları okunamadı (029_top10.sql çalıştırıldı mı?): {ex.Message}");
            }

            var sonuc = new Top10SoruSecici().Sec(tarih, veri, kademeler, gecmis);
            Console.WriteLine($"Top 10: {veri.Transferler.Count} bedelli transfer, {veri.BallonDor.Count} Ballon d'Or satırı, " +
                              $"son {Top10SoruSecici.TekrarGunu} günde {gecmis.Count} soru; {sonuc.DenenenSayisi} aday denendi.");
            foreach (var uyari in sonuc.Uyarilar)
            {
                Console.WriteLine($"Uyarı: {uyari}");
            }
            return sonuc.Soru;
        }

        private async Task<Top10SoruSecici.Veri> Top10VerisiniOku()
        {
            var kulupler = await KulupleriOku();

            // Kiralık ve bedelsiz transferler sayılmaz: sadece bedelli transferler okunur
            var transferler = (await HepsiniOku<TransferKaydi>("id, oyuncu_id, eski_kulup_tm_id, yeni_kulup_tm_id, tarih, sezon, tip, bedel",
                    t => t.Id, s => s.Filter("tip", Operator.Equals, "transfer").Filter("bedel", Operator.GreaterThan, "0")))
                .Select(t => new Top10SoruSecici.Transfer(t.OyuncuId, t.EskiKulupTmId, t.YeniKulupTmId, t.Tarih, t.Sezon, t.Bedel ?? 0))
                .ToList();

            var oyuncular = (await HepsiniOku<Oyuncu>("id, isim, uyruk", o => o.Id))
                .ToDictionary(o => o.Id, o => new Top10SoruSecici.OyuncuBilgisi(o.Isim, o.Uyruk));

            // Ballon d'Or ve kulüp sayıları yoksa (028/029 çalıştırılmamışsa) o şablonlar atlanır, diğerleri üretilir
            var ballonDor = new List<Top10SoruSecici.BallonDorSatiri>();
            try
            {
                ballonDor = (await HepsiniOku<BallonDorSiralamasi>("id, yil, sira, oyuncu_id, puan, yuzde", b => b.Id.ToString()))
                    .Select(b => new Top10SoruSecici.BallonDorSatiri(b.Yil, b.Sira, b.OyuncuId, b.Puan, b.Yuzde))
                    .ToList();
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Uyarı: Ballon d'Or sıralamaları okunamadı (028_ballon_dor.sql çalıştırıldı mı?): {ex.Message}");
            }

            var kulupSayilari = new List<Top10SoruSecici.KulupSayisi>();
            try
            {
                var cevap = await _supabaseClient.Rpc("top10_kulup_sayilari", new Dictionary<string, object> { ["p_adet"] = 30 });
                using var json = System.Text.Json.JsonDocument.Parse(cevap.Content ?? "[]");
                kulupSayilari = json.RootElement.EnumerateArray()
                    .Select(j => new Top10SoruSecici.KulupSayisi(j.GetProperty("oyuncu_id").GetString()!, j.GetProperty("kulup_sayisi").GetInt32()))
                    .ToList();
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Uyarı: Kulüp sayıları okunamadı (029_top10.sql çalıştırıldı mı?): {ex.Message}");
            }

            return new Top10SoruSecici.Veri(kulupler, transferler, oyuncular, ballonDor, kulupSayilari);
        }

        // Uygulama başlığı ve her satırın bayrağını gösterir; oyuncular ve değerler soru verisinde yoktur
        private static object Top10SoruVerisi(Top10SoruSecici.Soru soru, Top10SoruSecici.Veri veri) => new
        {
            sablon = soru.Sablon,
            baslik = soru.Baslik,
            alt_baslik = soru.AltBaslik,
            satirlar = soru.Satirlar.Select(s =>
            {
                var ulke = veri.Oyuncular[s.OyuncuId].Uyruk;
                return new { sira = s.Sira, ulke, bayrak = ulke == null ? null : Logolar.Bayrak(ulke) };
            }).ToList()
        };

        private static void Top10Yaz(Top10SoruSecici.Soru soru, Top10SoruSecici.Veri veri, Dictionary<string, Kademe> kademeler)
        {
            Console.WriteLine($"   [{soru.Sablon}] {soru.Baslik}" + (soru.AltBaslik == null ? "" : $" ({soru.AltBaslik})"));
            foreach (var s in soru.Satirlar)
            {
                var oyuncu = veri.Oyuncular[s.OyuncuId];
                var kademe = kademeler.TryGetValue(s.OyuncuId, out var k) ? ZorlukDagilimi.Metin(k) : "havuz dışı";
                Console.WriteLine($"   {s.Sira,2}. {oyuncu.Isim} ({oyuncu.Uyruk}, {kademe}) - {s.Deger}");
            }
        }

        // ---------------- Bingo ----------------

        // Bingo'nun zorluk modu yoktur: günde tek kart (oyun_tipi 'bingo')
        private async Task UretBingoOyunlari(DateTime tarih, Dictionary<string, Kademe> kademeler)
        {
            if (await OyunVarMi(BingoSoruSecici.OyunTipi, tarih))
            {
                Console.WriteLine($"bingo: {tarih:yyyy-MM-dd} için oyun zaten var, atlanıyor.");
                return;
            }

            var adaylar = await BingoAdaylari();
            var kart = new BingoSoruSecici().Sec(adaylar, kademeler, await BingoEkBilinenleri(kademeler));
            if (kart == null)
            {
                Console.WriteLine("Uyarı: Bingo için kurallara uyan kart kurulamadı.");
                return;
            }

            var soruVerisi = await BingoSoruVerisi(kart);
            var oyun = (await _supabaseClient.From<GunlukOyun>().Insert(new GunlukOyun
            {
                OyunTipi = BingoSoruSecici.OyunTipi,
                Tarih = tarih,
                SoruVerisi = soruVerisi
            })).Models.First();

            // Eşleşmeler yazılamazsa oyun cevapsız kalır: silinir, bir sonraki çalıştırmada yeniden üretilir
            try
            {
                await _supabaseClient.From<BingoEslesmesi>().Insert(kart.Eslesmeler
                    .Select((h, i) => new BingoEslesmesi { OyunId = oyun.Id, Sira = i + 1, Hucreler = h })
                    .ToList());
            }
            catch
            {
                await _supabaseClient.From<GunlukOyun>().Where(g => g.Id == oyun.Id).Delete();
                throw;
            }

            Console.WriteLine($"Başarılı: {oyun.OyunTipi} için {tarih:yyyy-MM-dd} tarihli kart eklendi.");
            BingoKartiniYaz(kart, kademeler);
        }

        // Veritabanına yazmadan bir Bingo kartı seçip ekrana basar:
        // dotnet run -- --bingo-onizleme
        public async Task BingoOnizleme()
        {
            var kademeler = await KademeleriOku();
            var adaylar = await BingoAdaylari();
            var ekBilinenler = await BingoEkBilinenleri(kademeler);
            Console.WriteLine("\nBingo önizleme (veritabanına yazılmadı):");
            var kart = new BingoSoruSecici().Sec(adaylar, kademeler, ekBilinenler);
            if (kart == null)
                Console.WriteLine("   Kurallara uyan kart kurulamadı.");
            else
                BingoKartiniYaz(kart, kademeler);
        }

        // Desteye ek oyuncu olarak girebilen bilinen oyuncular: bilinirlik sırasında ilk EkOyuncuSiraSiniri oyuncunun
        // içinde olup kademesi bilinen olanlar. Kademesi elle değiştirilmiş oyuncular da sırasına göre değerlendirilir.
        private async Task<HashSet<string>> BingoEkBilinenleri(Dictionary<string, Kademe> kademeler)
        {
            var skorlar = await HepsiniOku<Oyuncu>("id, bilinirlik", o => o.Id,
                s => s.Filter("bilinirlik", Operator.GreaterThanOrEqual, "0")); // skoru olanlar: soru havuzu
            var ekBilinenler = skorlar
                .OrderByDescending(o => o.Bilinirlik).ThenBy(o => o.Id, StringComparer.Ordinal)
                .Take(BingoSoruSecici.EkOyuncuSiraSiniri)
                .Where(o => kademeler.TryGetValue(o.Id, out var k) && k == Kademe.Bilinen)
                .Select(o => o.Id)
                .ToHashSet();
            Console.WriteLine($"Bingo ek oyuncuları: ünlüler ve ilk {BingoSoruSecici.EkOyuncuSiraSiniri} sıradaki {ekBilinenler.Count} bilinen oyuncu.");
            return ekBilinenler;
        }

        // Bütün kategoriler, kendilerine uyan oyuncularla. Kulüp ve ligde oyuncu, kulüpte yeterince maça çıkmışsa
        // kartı kurarken kullanılır (KariyerGecmisi.SoruyaUygun); cevap olarak bütün kayıtlar kabul edilir.
        private async Task<List<BingoSoruSecici.Aday>> BingoAdaylari()
        {
            var kulupler = await KulupleriOku();
            var kariyer = await HepsiniOku<KariyerGecmisi>("id, oyuncu_id, kulup_id, mac_sayisi", k => k.Id);
            var milliKariyer = await TumMilliTakimKariyeri();

            var adaylar = new List<BingoSoruSecici.Aday>();
            var kulupKayitlari = kariyer.GroupBy(k => k.KulupId).ToDictionary(g => g.Key, g => g.ToList());
            (HashSet<string>, HashSet<string>) Oyunculari(IEnumerable<KariyerGecmisi> kayitlar) =>
                (kayitlar.Select(k => k.OyuncuId).ToHashSet(), kayitlar.Where(k => k.SoruyaUygun).Select(k => k.OyuncuId).ToHashSet());

            // Büyük ve baş altı kulüpler; kartta baş altı kulüp sayısı sınırlıdır (BingoSoruSecici.MaxBasAltiKulup)
            foreach (var kulup in kulupler.Where(k => KesisimSoruSecici.Kulupler.ContainsKey(k.TransfermarktId)
                         && KulupKademeleri.BingodaCikar(k.Kademe) && kulupKayitlari.ContainsKey(k.Id)))
            {
                var (hepsi, oynayanlar) = Oyunculari(kulupKayitlari[kulup.Id]);
                adaylar.Add(new(new(BingoSoruSecici.KategoriTipi.Kulup, kulup.TransfermarktId,
                    KesisimSoruSecici.Kulupler[kulup.TransfermarktId], kulup.Id, kulup.LogoUrl,
                    BasAlti: kulup.Kademe == KulupKademeleri.BasAlti), hepsi, oynayanlar));
            }

            foreach (var (kod, isim) in BingoSoruSecici.Ligler)
            {
                var ligKulupleri = kulupler.Where(k => k.Lig == kod).Select(k => k.Id).ToHashSet();
                var (hepsi, oynayanlar) = Oyunculari(kariyer.Where(k => ligKulupleri.Contains(k.KulupId)));
                adaylar.Add(new(new(BingoSoruSecici.KategoriTipi.Lig, kod, isim, LogoUrl: Logolar.Lig(kod)), hepsi, oynayanlar));
            }

            foreach (var g in milliKariyer.GroupBy(m => m.MilliTakimTmId).Where(g => IzgaraSoruSecici.OrtaMilliTakimlar.ContainsKey(g.Key)))
            {
                var oyuncular = g.Select(m => m.OyuncuId).ToHashSet();
                adaylar.Add(new(new(BingoSoruSecici.KategoriTipi.Milli, g.Key, IzgaraSoruSecici.OrtaMilliTakimlar[g.Key],
                    LogoUrl: Logolar.Bayrak(g.First().MilliTakimIsim)), oyuncular, oyuncular));
            }

            foreach (var (anahtar, (isim, basliklar)) in BingoSoruSecici.Basarilar)
            {
                var oyuncular = new HashSet<string>();
                foreach (var baslik in basliklar)
                {
                    // Bir başlıkta en fazla birkaç yüz oyuncu var; tek istek yeterli, sınıra yaklaşılırsa uyarılır
                    var satirlar = (await _supabaseClient.From<OyuncuBasarisi>()
                        .Select("oyuncu_id, baslik")
                        .Filter("baslik", Operator.Equals, baslik)
                        .Limit(SayfaBoyutu)
                        .Get()).Models;
                    if (satirlar.Count >= SayfaBoyutu)
                        Console.WriteLine($"Uyarı: '{baslik}' başlığında {SayfaBoyutu} satırdan fazlası olabilir, bir kısmı okunmadı.");
                    oyuncular.UnionWith(satirlar.Select(s => s.OyuncuId));
                }
                adaylar.Add(new(new(BingoSoruSecici.KategoriTipi.Basari, anahtar, isim, LogoUrl: Logolar.Basari(anahtar)), oyuncular, oyuncular));
            }

            Console.WriteLine($"Bingo kategorileri: {adaylar.GroupBy(a => a.Kategori.Tip).Select(g => $"{g.Count()} {g.Key}").Aggregate((a, b) => $"{a}, {b}")}.");
            return adaylar;
        }

        // Uygulama kutuları ve desteyi gösterir. Hangi oyuncunun hangi kutuya uyduğu soru verisinde yoktur.
        private async Task<object> BingoSoruVerisi(BingoSoruSecici.BingoKarti kart)
        {
            var idler = kart.Deste.Cast<object>().ToList();
            var oyuncular = (await _supabaseClient.From<Oyuncu>()
                    .Select("id, isim, foto_url")
                    .Filter("id", Operator.In, idler)
                    .Get()).Models
                .ToDictionary(o => o.Id);

            return new
            {
                hucreler = kart.Hucreler.Select(h => new
                {
                    tip = h.Tip switch
                    {
                        BingoSoruSecici.KategoriTipi.Kulup => "kulup",
                        BingoSoruSecici.KategoriTipi.Milli => "milli",
                        BingoSoruSecici.KategoriTipi.Lig => "lig",
                        _ => "basari"
                    },
                    anahtar = h.Anahtar,
                    isim = h.Isim,
                    id = h.KulupId,
                    logo = h.LogoUrl
                }).ToList(),
                oyuncular = kart.Deste.Select(id => new
                {
                    id,
                    isim = oyuncular[id].Isim,
                    foto = oyuncular[id].FotoUrl
                }).ToList()
            };
        }

        private static void BingoKartiniYaz(BingoSoruSecici.BingoKarti kart, Dictionary<string, Kademe> kademeler)
        {
            for (int s = 0; s < BingoSoruSecici.SatirSayisi; s++)
            {
                var satir = Enumerable.Range(0, BingoSoruSecici.SutunSayisi).Select(t => $"{kart.Hucreler[s * BingoSoruSecici.SutunSayisi + t].Isim,-24}");
                Console.WriteLine($"   {string.Join("", satir)}");
            }
            var sayilar = kart.Deste.GroupBy(o => kademeler[o]).OrderBy(g => g.Key).Select(g => $"{g.Count()} {ZorlukDagilimi.Metin(g.Key)}");
            Console.WriteLine($"   Deste: {string.Join(", ", sayilar)}; oyuncu başına uyduğu kutu: {string.Join(" ", kart.Eslesmeler.Select(e => e.Length))}");
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
                // Kolay mod oyuncudan başlanarak kurulur (KolayKesisimSecici). Kurulamazsa eski mantığa düşülür:
                // soru üretilmeyen gün olmasın.
                if (zorluk == Zorluk.Kolay && await UretKolayKesisim(tarih, veri, kademeler)) continue;

                var sorular = KesisimSorulariniSec(zorluk, veri, kademeler);
                if (sorular == null) continue;

                await OyunEkle("kesisim", zorluk, tarih,
                    sorular.Select(s => KesisimSoruVerisi(s.KulupA, s.KulupB, s.Kademe)).ToList());
                KesisimSorulariniYaz(sorular);
            }
        }

        private static object KesisimSoruVerisi(Kulup kulupA, Kulup kulupB, Kademe kademe) => new
        {
            kulup_a = kulupA.Isim,
            kulup_b = kulupB.Isim,
            kulup_a_id = kulupA.Id,
            kulup_b_id = kulupB.Id,
            kulup_a_logo = kulupA.LogoUrl,
            kulup_b_logo = kulupB.LogoUrl,
            kademe = ZorlukDagilimi.Metin(kademe),
            // Sorunun kendi kademesi: ünlü soru kolay, bilinen orta, diğer zor
            zorluk = kademe switch { Kademe.Unlu => "kolay", Kademe.Bilinen => "orta", _ => "zor" }
        };

        // Kolay Kesişim'i hedef oyunculardan kurup ekler. Oyun eklendiyse true; geçmiş okunamadıysa ya da
        // 5 soru kurulamadıysa false döner.
        private async Task<bool> UretKolayKesisim(DateTime tarih, KesisimVerisi veri, Dictionary<string, Kademe> kademeler)
        {
            var sorular = await KolayKesisimSorulariniSec(tarih, veri, kademeler);
            if (sorular == null) return false;

            // Hedef oyuncu cevabı ele verir: soru verisine yazılmaz, uygulamaya kapalı kesisim_hedefleri tablosunda tutulur
            var oyun = await OyunEkle("kesisim", Zorluk.Kolay, tarih,
                sorular.Select(s => KesisimSoruVerisi(s.KulupA, s.KulupB, Kademe.Unlu)).ToList());

            // Hedefler yazılamazsa tekrar kuralları bu oyunu göremez: oyun silinir, bir sonraki çalıştırmada yeniden üretilir
            try
            {
                await _supabaseClient.From<KesisimHedefi>().Insert(sorular.Select((s, i) =>
                {
                    var (a, b) = KolayKesisimSecici.Cift(s.KulupA.Id, s.KulupB.Id);
                    return new KesisimHedefi { OyunId = oyun.Id, Sira = i + 1, Tarih = tarih, OyuncuId = s.HedefOyuncuId, KulupAId = a, KulupBId = b };
                }).ToList());
            }
            catch
            {
                await _supabaseClient.From<GunlukOyun>().Where(g => g.Id == oyun.Id).Delete();
                throw;
            }

            await KolayKesisimSorulariniYaz(sorular);
            return true;
        }

        private async Task<List<KolayKesisimSecici.Soru>?> KolayKesisimSorulariniSec(
            DateTime tarih, KesisimVerisi veri, Dictionary<string, Kademe> kademeler)
        {
            List<KolayKesisimSecici.Gecmis> gecmis;
            try
            {
                gecmis = (await HepsiniOku<KesisimHedefi>("id, oyuncu_id, kulup_a_id, kulup_b_id, tarih", h => h.Id.ToString()))
                    .Select(h => new KolayKesisimSecici.Gecmis(h.OyuncuId, h.KulupAId, h.KulupBId, h.Tarih.Date))
                    .ToList();
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Uyarı: Kesişim hedefleri okunamadı (027_kesisim_hedefleri.sql çalıştırıldı mı?), kolay mod eski mantıkla kurulacak: {ex.Message}");
                return null;
            }

            var sonuc = new KolayKesisimSecici().Sec(tarih, veri.Kulupler, veri.Kariyer, kademeler, gecmis);
            Console.WriteLine($"Kesişim (Kolay): {sonuc.HedefSayisi} hedef oyuncu ({sonuc.KullanilmamisHedefSayisi} kullanılmamış), {sonuc.CiftSayisi} büyük kulüp çifti.");
            foreach (var uyari in sonuc.Uyarilar)
            {
                Console.WriteLine($"Uyarı: {uyari}");
            }
            return sonuc.Sorular;
        }

        private async Task KolayKesisimSorulariniYaz(List<KolayKesisimSecici.Soru> sorular)
        {
            var idler = sorular.Select(s => s.HedefOyuncuId).Cast<object>().ToList();
            var isimler = (await _supabaseClient.From<Oyuncu>().Select("id, isim").Filter("id", Operator.In, idler).Get()).Models
                .ToDictionary(o => o.Id, o => o.Isim);
            for (int i = 0; i < sorular.Count; i++)
            {
                var s = sorular[i];
                Console.WriteLine($"   {i + 1}. {s.KulupA.Isim} x {s.KulupB.Isim} ({s.OrtakOyuncuSayisi} ortak oyuncu, hedef: {isimler.GetValueOrDefault(s.HedefOyuncuId, "?")})");
            }
        }

        // Veritabanına yazmadan her moddan bir soru seti seçip ekrana basar:
        // dotnet run -- --kesisim-onizleme
        public async Task KesisimOnizleme()
        {
            var kademeler = await KademeleriOku();
            var veri = await KesisimVerisiniOku(ayrintili: true);
            DateTime bugun = TimeZoneInfo.ConvertTimeFromUtc(DateTime.UtcNow, TurkiyeSaatDilimi).Date;
            foreach (var zorluk in Enum.GetValues<Zorluk>())
            {
                Console.WriteLine($"\nKesişim ({zorluk}) önizleme (veritabanına yazılmadı):");
                if (zorluk == Zorluk.Kolay)
                {
                    var kolay = await KolayKesisimSorulariniSec(bugun, veri, kademeler);
                    if (kolay != null)
                    {
                        await KolayKesisimSorulariniYaz(kolay);
                        continue;
                    }
                }
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

        private async Task<GunlukOyun> OyunEkle(string oyun, Zorluk zorluk, DateTime tarih, object soruVerisi)
        {
            var eklenen = (await _supabaseClient.From<GunlukOyun>().Insert(new GunlukOyun
            {
                OyunTipi = ZorlukDagilimi.OyunTipi(oyun, zorluk),
                Tarih = tarih,
                SoruVerisi = soruVerisi
            })).Models.First();
            Console.WriteLine($"Başarılı: {ZorlukDagilimi.OyunTipi(oyun, zorluk)} için {tarih:yyyy-MM-dd} tarihli oyun eklendi.");
            return eklenen;
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
            (await _supabaseClient.From<Kulup>().Select("id, isim, lig, transfermarkt_id, logo_url, kademe").Get()).Models;

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
