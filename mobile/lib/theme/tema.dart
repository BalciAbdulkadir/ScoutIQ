import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'renkler.dart';

// Uygulamanın teması. Uygulama, testler ve önizlemeler aynı temayı kullanır.
ThemeData uygulamaTemasi() {
  final renkSemasi = ColorScheme.fromSeed(
    seedColor: Renkler.basari,
    brightness: Brightness.dark,
  ).copyWith(
    primary: Renkler.basari,
    onPrimary: Renkler.arkaPlan,
    surface: Renkler.arkaPlan,
    onSurface: Renkler.metin,
    error: Renkler.hata,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: renkSemasi,
    scaffoldBackgroundColor: Renkler.arkaPlan,
    appBarTheme: const AppBarTheme(
      systemOverlayStyle: SystemUiOverlayStyle.light,
      backgroundColor: Renkler.arkaPlan,
      foregroundColor: Renkler.metin,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(color: Renkler.metin, fontSize: 18, fontWeight: FontWeight.w700),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Renkler.yuzeyYuksek,
      contentTextStyle: const TextStyle(color: Renkler.metin),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    dividerTheme: const DividerThemeData(color: Renkler.kenar, thickness: 1, space: 1),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: Renkler.basari),
  );
}
