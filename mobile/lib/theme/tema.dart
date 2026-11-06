import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'renkler.dart';
import 'yazi.dart';

// Uygulamanın teması. Uygulama, testler ve önizlemeler aynı temayı kullanır.
ThemeData uygulamaTemasi() {
  final renkSemasi = ColorScheme.fromSeed(
    seedColor: Renkler.arkaPlan,
    brightness: Brightness.dark,
  ).copyWith(
    primary: Renkler.vurgu,
    onPrimary: Renkler.arkaPlan,
    secondary: Renkler.metin,
    onSecondary: Renkler.arkaPlan,
    surface: Renkler.arkaPlan,
    onSurface: Renkler.metin,
    surfaceContainerLow: Renkler.yuzey,
    surfaceContainer: Renkler.yuzey,
    surfaceContainerHigh: Renkler.yuzeyYuksek,
    outline: Renkler.kenar,
    outlineVariant: Renkler.kenar,
    error: Renkler.hata,
  );

  final butonYazisi = Yazi.baslik(17, kalinlik: FontWeight.w900, renk: Renkler.arkaPlan);
  final keskinKose = RoundedRectangleBorder(borderRadius: BorderRadius.circular(6));

  return ThemeData(
    useMaterial3: true,
    colorScheme: renkSemasi,
    fontFamily: Yazi.govdeAilesi,
    scaffoldBackgroundColor: Renkler.arkaPlan,
    canvasColor: Renkler.arkaPlan,
    appBarTheme: AppBarTheme(
      systemOverlayStyle: SystemUiOverlayStyle.light,
      backgroundColor: Renkler.arkaPlan,
      foregroundColor: Renkler.metin,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: Yazi.baslik(24, kalinlik: FontWeight.w900),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Renkler.vurgu,
        foregroundColor: Renkler.arkaPlan,
        disabledBackgroundColor: Renkler.yuzey,
        disabledForegroundColor: Renkler.metinSoluk,
        textStyle: butonYazisi,
        shape: keskinKose,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Renkler.vurgu,
        textStyle: const TextStyle(fontFamily: Yazi.govdeAilesi, fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Renkler.yuzey,
      modalBackgroundColor: Renkler.yuzey,
      dragHandleColor: Renkler.kenar,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Renkler.yuzey,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Renkler.kenar, width: 1.5),
      ),
      titleTextStyle: Yazi.baslik(22, kalinlik: FontWeight.w900),
      contentTextStyle: const TextStyle(fontFamily: Yazi.govdeAilesi, color: Renkler.metinIkincil, fontSize: 15, height: 1.4),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Renkler.yuzeyYuksek,
      contentTextStyle: const TextStyle(fontFamily: Yazi.govdeAilesi, color: Renkler.metin),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: Renkler.kenar),
      ),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: Renkler.vurgu,
      selectionColor: Color(0x55F3D36B),
      selectionHandleColor: Renkler.vurgu,
    ),
    dividerTheme: const DividerThemeData(color: Renkler.kenar, thickness: 1, space: 1),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: Renkler.vurgu),
  );
}
