import 'package:flutter/material.dart';

// Oyun ekranlarında oyun yerine gösterilen durum mesajı (oyun yok, bugün oynandı, hata...)
class OyunMesajKarti extends StatelessWidget {
  final IconData ikon;
  final String baslik;
  final String aciklama;

  const OyunMesajKarti({super.key, this.ikon = Icons.sports_score, required this.baslik, required this.aciklama});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(ikon, size: 80, color: Colors.greenAccent),
            const SizedBox(height: 20),
            Text(
              baslik,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 10),
            Text(aciklama, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: Colors.white70)),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent),
              child: const Text('Ana Menüye Dön', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
