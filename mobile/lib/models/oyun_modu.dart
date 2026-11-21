import 'package:flutter/material.dart';
import '../theme/renkler.dart';
import '../widgets/tebesir.dart';

enum OyunDurumu { aktif, hazirlaniyor, yakinda }

class OyunModu {
  final String? tip; // Supabase'deki oyun_tipi değeri. Veritabanında henüz karşılığı olmayan modlar için null.
  final String baslik;
  final String aciklama;
  final IconData ikon;
  final TebesirCizimi? cizim; // Ana menüdeki tebeşir çizimi; boşsa ikon kullanılır
  final Color renk;
  final OyunDurumu durum;
  final int? maksimumSkor;
  // Doluysa mod birden fazla ayrı günlük oyundan oluşur: kolay, orta ve zor (ör. kesisim_kolay, kesisim_orta, kesisim_zor)
  final List<String>? altTipler;
  // Zorluk seçim sayfasında her zorluğun altında yazan açıklama, altTipler ile aynı sırada
  final List<String>? zorlukAciklamalari;
  // Oyun başlarken seçilebilen süreler
  final List<OyunSuresi> sureSecenekleri;
  // Oyuna ilk dokunuşta gösterilen kurallar
  final OyunOnizlemesi? onizleme;

  const OyunModu({
    this.tip,
    required this.baslik,
    required this.aciklama,
    required this.ikon,
    this.cizim,
    required this.renk,
    required this.durum,
    this.maksimumSkor,
    this.altTipler,
    this.zorlukAciklamalari,
    this.sureSecenekleri = OyunSuresi.values,
    this.onizleme,
  });

  // Bu modun veritabanındaki günlük oyun tipleri
  List<String> get oyunTipleri => altTipler ?? [?tip];

  // Zorluk seçilerek oynanan mod. Bu modlarda günde yalnızca bir zorluk oynanır.
  bool get zorluklu => altTipler != null;
}

// Oyun başlamadan gösterilen önizleme: oyunun ne olduğu, kuralları ve puanlaması
class OyunOnizlemesi {
  final String ozet;
  final List<String> kurallar;
  final String puanlama;

  const OyunOnizlemesi({required this.ozet, required this.kurallar, required this.puanlama});
}

// Zorluklu oyunlarda altTipler sırasıyla zorlukların adı
const zorlukAdlari = ['Kolay', 'Orta', 'Zor'];

// Kesişim ve Bonservis'te zorluk, soruların oyuncu kademesinden gelir (backend: Oyunlar/Zorluk.cs)
const _oyuncuZorluklari = [
  'Sadece ünlü oyuncular',
  'Yarısı ünlü, yarısı bilinen oyuncular',
  'Ünlü, bilinen ve az bilinen oyuncular',
];

// Oyun başlarken seçilen süre. Oyunların çoğunda dört seçenek de vardır; Bingo'da 30 saniye yoktur, Top 10 süresizdir.
enum OyunSuresi {
  suresiz(null, 'Süresiz'),
  saniye30(30, '30 sn'),
  saniye60(60, '60 sn'),
  saniye90(90, '90 sn');

  final int? saniye; // null: süre sınırı yok
  final String ad;

  const OyunSuresi(this.saniye, this.ad);
}

// Hub'da gösterilen modlar: Kesişim, Bonservis, Izgara, Bingo ve Top 10.
const List<OyunModu> oyunModlari = [
  OyunModu(
    tip: 'kesisim',
    baslik: 'Kesişim',
    aciklama: 'İki kulübün ortak oyuncusunu bul.',
    ikon: Icons.join_inner,
    cizim: TebesirCizimi.kesisim,
    renk: Renkler.kesisim,
    durum: OyunDurumu.aktif,
    maksimumSkor: 10,
    altTipler: ['kesisim_kolay', 'kesisim_orta', 'kesisim_zor'],
    zorlukAciklamalari: _oyuncuZorluklari,
    onizleme: OyunOnizlemesi(
      ozet: 'Ekranda iki kulüp var. Kariyerinde bu iki kulübün ikisinde de forma giymiş bir oyuncu bul.',
      kurallar: [
        '5 soru var. Her soruda oyuncunun adını yaz ve listeden seç.',
        'Birden fazla doğru cevap olabilir, herhangi biri kabul edilir.',
        'Her soruda tek hakkın var. Doğru da bilsen yanlış da, sıradaki soruya geçilir.',
        'Zorluk, sorulardaki oyuncuların ne kadar tanındığına göre değişir.',
      ],
      puanlama: 'Puanı sadece 5/5 yapan alır: 100 puan, zorluk (×1/×1.5/×2) ve süre (×1/×1.25/×1.5) çarpar, '
          "kalan süreye göre %20'ye kadar hız bonusu. Süresiz oyun puansızdır.",
    ),
  ),
  OyunModu(
    tip: 'bonservis',
    baslik: 'Bonservis',
    aciklama: 'Toplam bonservis daha mı az, daha mı fazla?',
    ikon: Icons.euro,
    cizim: TebesirCizimi.bonservis,
    renk: Renkler.bonservis,
    durum: OyunDurumu.aktif,
    maksimumSkor: 10, // 5 soru, her doğru 2 (skor; liderlik puanı değil)
    altTipler: ['bonservis_kolay', 'bonservis_orta', 'bonservis_zor'],
    zorlukAciklamalari: _oyuncuZorluklari,
    onizleme: OyunOnizlemesi(
      ozet: 'İki oyuncunun kariyerleri boyunca hakkında ödenen toplam bonservisi karşılaştır.',
      kurallar: [
        'Üstteki oyuncunun toplam bonservisi açıkça yazar.',
        'Alttaki oyuncunun toplamı ondan daha fazla mı, daha az mı? Tahminini yap.',
        '5 soru var. Yanlış tahminde oyun bitmez, sıradaki soruya geçilir.',
        'Zorluk, sorulardaki oyuncuların ne kadar tanındığına göre değişir.',
      ],
      puanlama: 'Puanı sadece 5/5 yapan alır: 100 puan, zorluk (×1/×1.5/×2) ve süre (×1/×1.25/×1.5) çarpar, '
          "kalan süreye göre %20'ye kadar hız bonusu. Süresiz oyun puansızdır.",
    ),
  ),
  OyunModu(
    tip: 'izgara',
    baslik: 'Izgara',
    aciklama: 'Satır ve sütundaki takımlara uyan oyuncuları bul.',
    ikon: Icons.grid_view_rounded,
    cizim: TebesirCizimi.izgara,
    renk: Renkler.izgara,
    durum: OyunDurumu.aktif,
    maksimumSkor: 9,
    // Her zorluk ayrı bir tahta; kullanıcı günde bunlardan yalnızca birini seçip oynar
    altTipler: ['izgara_kolay', 'izgara_orta', 'izgara_zor'],
    // Zorluk açıklamaları IzgaraZorlugu'nda
    onizleme: OyunOnizlemesi(
      ozet: '3x3 tahtada her kutu bir satır ve bir sütun başlığının kesiştiği yerdir. '
          'Kutuya, iki başlığa da uyan bir oyuncu gerekir.',
      kurallar: [
        'Oyuncunun adını yaz ve listeden seç. Kutu seçmene gerek yok, doğru oyuncu uyduğu kutuya kendisi yerleşir.',
        'Başlıklar kulüp ya da milli takım olabilir. Orta ve Zor tahtada milli takımlar da gelir.',
        'Tahmin hakkın sınırsız. Aynı oyuncuyu iki kez kullanamazsın.',
        'Oyun dokuz kutu dolunca, pes edince ya da süre bitince sona erer.',
      ],
      puanlama: 'Puanı sadece 9 kutuyu dolduran alır: 100 puan, zorluk (×1/×1.5/×2) ve süre (×1/×1.25/×1.5) çarpar, '
          "kalan süreye göre %20'ye kadar hız bonusu. Süresiz oyun puansızdır.",
    ),
  ),
  OyunModu(
    tip: 'bingo',
    baslik: 'Bingo',
    aciklama: 'Gelen oyuncuyu uyduğu kutuya koy, kartı doldur.',
    ikon: Icons.apps_rounded,
    cizim: TebesirCizimi.bingo,
    renk: Renkler.bingo,
    durum: OyunDurumu.aktif,
    maksimumSkor: 12,
    // Zorluk modu yoktur: 12 kutulu tek kart, destede ünlü ve bilinen oyuncular. Kart her zaman doldurulabilir.
    sureSecenekleri: [OyunSuresi.suresiz, OyunSuresi.saniye60, OyunSuresi.saniye90],
    onizleme: OyunOnizlemesi(
      ozet: '12 kutulu bir kart var: kulüpler, milli takımlar, ligler ve başarılar. '
          'Desteden oyuncular sırayla gelir, her birini uyduğu kutuya koy.',
      kurallar: [
        'Gelen oyuncuyu kariyerine uyan kutuya dokunarak yerleştir. Uyan kutu yoksa pas geç.',
        'Yanlış kutuya dokunursan oyuncu gitmez, ceza da yok. Başka kutu deneyebilirsin.',
        'Pas sınırsız. Pas geçtiğin oyuncu sırası gelince tekrar gelir; kutuya yerleşen oyuncu bir daha gelmez.',
        'Arada hiçbir kutuya uymayan oyuncular da gelir, onları pas geç. Kart her zaman tamamen doldurulabilir.',
        'Zorluk modu yok, herkes aynı kartı oynar. Oyun kart dolunca, pes edince ya da süre bitince sona erer.',
      ],
      puanlama: 'Puanı sadece 12 kutuyu dolduran alır: 150 puan, süre çarpar (60 sn ×1.25, 90 sn ×1), '
          "kalan süreye göre %20'ye kadar hız bonusu. Süresiz oyun puansızdır.",
    ),
  ),
  OyunModu(
    tip: 'top10',
    baslik: 'Top 10',
    aciklama: 'Listedeki 10 oyuncuyu bul.',
    ikon: Icons.format_list_numbered_rounded,
    cizim: TebesirCizimi.top10,
    renk: Renkler.top10,
    durum: OyunDurumu.aktif,
    maksimumSkor: 10,
    // Zorluk modu ve süre yoktur: günde tek liste
    sureSecenekleri: [OyunSuresi.suresiz],
    onizleme: OyunOnizlemesi(
      ozet: 'Ekranda bir liste başlığı var, ör. "Galatasaray\'ın en pahalı 10 transferi". Listedeki 10 oyuncuyu bul.',
      kurallar: [
        'Oyuncunun adını yaz ve listeden seç. Sırayı bilmen gerekmez, bulduğun oyuncu kendi sırasına yerleşir.',
        'Her satırda ipucu olarak oyuncunun uyruğunun bayrağı açık.',
        '3 canın var. Listede olmayan oyuncu bir can götürür; daha önce denediğin oyuncu sayılmaz, can da götürmez.',
        'Zorluk modu ve süre yok, herkes aynı listeyi oynar. Oyun 10 oyuncu bulununca, canların bitince ya da pes edince sona erer.',
      ],
      puanlama: '10 oyuncunun hepsini bulursan 150 puan. Süresi yok ama her zaman puanlıdır.',
    ),
  ),
];
