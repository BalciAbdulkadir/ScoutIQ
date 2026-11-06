import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../theme/renkler.dart';
import '../theme/yazi.dart';
import '../widgets/logo.dart';
import '../widgets/tebesir.dart';

class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authService = ref.read(authServiceProvider);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: TahtaZemini(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(flex: 3),
                  // Tahtanın ortasındaki orta yuvarlak
                  const Center(child: _OrtaSaha()),
                  const SizedBox(height: 36),
                  const Center(child: FootyLoreLogo(boyut: 52)),
                  const SizedBox(height: 10),
                  Text(
                    'futbol zekanı her gün test et',
                    textAlign: TextAlign.center,
                    style: Yazi.tebesir(20, renk: Renkler.metinIkincil, kalinlik: FontWeight.w400),
                  ),
                  const Spacer(flex: 4),
                  FilledButton.icon(
                    onPressed: () async {
                      try {
                        await authService.signInWithGoogle();
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                        }
                      }
                    },
                    icon: const Icon(Icons.login_rounded),
                    label: const Text('GOOGLE İLE GİRİŞ YAP'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Renkler.metin,
                      foregroundColor: Renkler.arkaPlan,
                      minimumSize: const Size.fromHeight(54),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Her oyun günde bir kez oynanır. Yeni oyunlar her gece 00.00\'da gelir.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Renkler.metinSoluk, fontSize: 12.5, height: 1.4),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Orta saha çizgisi ve orta yuvarlak, tebeşirle
class _OrtaSaha extends StatelessWidget {
  const _OrtaSaha();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      height: 140,
      child: CustomPaint(
        painter: _OrtaSahaCizeri(),
        child: const Center(child: TebesirIkonu(cizim: TebesirCizimi.kesisim, boyut: 40)),
      ),
    );
  }
}

class _OrtaSahaCizeri extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final kalem = Paint()
      ..color = Renkler.kenar
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final merkez = size.center(Offset.zero);
    canvas.drawLine(Offset(0, merkez.dy), Offset(size.width, merkez.dy), kalem);
    canvas.drawCircle(merkez, size.height / 2 - 2, kalem);
  }

  @override
  bool shouldRepaint(_OrtaSahaCizeri eski) => false;
}
