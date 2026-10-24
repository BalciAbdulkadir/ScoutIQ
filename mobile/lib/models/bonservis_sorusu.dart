// Bonservis oyunundaki bir oyuncu ve kariyeri boyunca ödenen toplam bonservis (Euro)
class BonservisOyuncusu {
  final String id;
  final String isim;
  final int toplamBonservis;

  const BonservisOyuncusu({required this.id, required this.isim, required this.toplamBonservis});
}

// Bir soru: bedeli görünen referans oyuncu ve bedeli tahmin edilecek rakip
class BonservisSorusu {
  final BonservisOyuncusu referans;
  final BonservisOyuncusu rakip;

  const BonservisSorusu({required this.referans, required this.rakip});

  bool get rakipDahaPahali => rakip.toplamBonservis > referans.toplamBonservis;
  BonservisOyuncusu get pahaliOlan => rakipDahaPahali ? rakip : referans;
}

// Backend'in soru_verisi'ni sorulara çevirir. Her soru bağımsız iki oyuncudur: oyuncu_a (sol) bedeliyle
// gösterilir, oyuncu_b (sağ) için tahmin istenir. Doğru cevabın hangi tarafta olacağını backend rastgele seçer.
List<BonservisSorusu> bonservisSorulariniOku(List<dynamic> soruVerisi) {
  BonservisOyuncusu oyuncu(Map<String, dynamic> soru, String taraf) => BonservisOyuncusu(
        id: soru['oyuncu_${taraf}_id'] as String,
        isim: soru['oyuncu_$taraf'] as String,
        toplamBonservis: (soru['oyuncu_${taraf}_bonservis'] as num).toInt(),
      );

  return [
    for (final ham in soruVerisi)
      BonservisSorusu(referans: oyuncu(ham as Map<String, dynamic>, 'a'), rakip: oyuncu(ham, 'b')),
  ];
}

// 79000000 -> "79 M€", 77400000 -> "77,4 M€"
String bonservisMetni(int euro) {
  final milyon = euro / 1000000;
  final metin = milyon == milyon.roundToDouble() ? milyon.toStringAsFixed(0) : milyon.toStringAsFixed(1);
  return '${metin.replaceAll('.', ',')} M€';
}
