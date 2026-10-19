import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'game_screen.dart'; // İleride Kesişim'e gitmek için

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  // Oyun listesini burada tanımlıyoruz (MVP'deki 5 oyun)
  final List<Map<String, dynamic>> games = const [
    {'title': 'Kesişim', 'icon': Icons.sync_alt, 'status': 'Oyna', 'color': Colors.greenAccent},
    {'title': 'Bonservis', 'icon': Icons.attach_money, 'status': 'Oyna', 'color': Colors.blueAccent},
    {'title': 'Kariyer Yolu', 'icon': Icons.route, 'status': 'Yakında', 'color': Colors.grey},
    {'title': 'Kimlik', 'icon': Icons.person_search, 'status': 'Yakında', 'color': Colors.grey},
    {'title': '9\'lu Izgara', 'icon': Icons.grid_3x3, 'status': 'Yakında', 'color': Colors.grey},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // İstediğin o koyu yeşil (Gece çimi) arka plan
      backgroundColor: const Color(0xFF0A1C12),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'FUTBOL IQ',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 24,
            letterSpacing: 2,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white54),
            onPressed: () async {
              await AuthService().signOut();
            },
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              'Oynamak istediğin modu seç',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2, // Yan yana 2 kart
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 0.85, // Kartların boy/en oranı (biraz diktörtgen)
                ),
                itemCount: games.length,
                itemBuilder: (context, index) {
                  final game = games[index];
                  final isPlayable = game['status'] == 'Oyna';
                  final Color gameColor = game['color'] as Color;

                  return GestureDetector(
                    onTap: () {
                      if (game['title'] == 'Kesişim') {
                        // Kesişim'e tıklanırsa oyun ekranına yolla
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const GameScreen()),
                        );
                      } else if (!isPlayable) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Bu mod henüz aktif değil!')),
                        );
                      }
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF132B1E), // Kart arka planı (Biraz daha açık yeşil)
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isPlayable ? gameColor.withValues(alpha: 0.5) : Colors.transparent,
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            game['icon'],
                            size: 48,
                            color: gameColor,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            game['title'],
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            decoration: BoxDecoration(
                              color: isPlayable ? gameColor.withValues(alpha: 0.2) : Colors.white10,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              game['status'],
                              style: TextStyle(
                                color: isPlayable ? gameColor : Colors.white54,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
