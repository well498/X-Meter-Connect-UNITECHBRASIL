import 'package:flutter/material.dart';

import 'calc.dart';

/// Identidade visual UNITECH (tema escuro de instrumento): azul tecnológico,
/// prata, verde (aprovado), amarelo (alerta) e vermelho (falha).
class XColors {
  static const bg = Color(0xFF061430);
  static const bgTop = Color(0xFF0A2149);
  static const card = Color(0xFF0D2247);
  static const cardHi = Color(0xFF12305E);
  static const border = Color(0xFF1E3D6E);
  static const blue = Color(0xFF1E88E5);
  static const cyan = Color(0xFF38BDF8);
  static const silver = Color(0xFFC3CCD8);

  /// Texto principal (claro) e secundário.
  static const blueDark = Color(0xFFF2F6FC);
  static const gray = Color(0xFF9DB0CC);
  static const surface = bg;

  static const ok = Color(0xFF22C55E);
  static const okText = Color(0xFF4ADE80);
  static const warn = Color(0xFFF5B800);
  static const fail = Color(0xFFEF4444);
  static const demo = Color(0xFFA855F7);
  static const invalid = Color(0xFFF97316);

  /// Cores das séries na comparação de disparos.
  static const series = [cyan, Color(0xFFF59E0B), Color(0xFFA78BFA), Color(0xFF34D399)];

  static Color status(MeasureStatus s) => switch (s) {
        MeasureStatus.approved => ok,
        MeasureStatus.alert => warn,
        MeasureStatus.failed => fail,
        MeasureStatus.invalid => invalid,
        MeasureStatus.unknown => gray,
      };

  /// Texto legível sobre a cor do status (preto sobre amarelo).
  static Color onStatus(MeasureStatus s) => s == MeasureStatus.alert ? Colors.black : Colors.white;
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: XColors.blue,
    brightness: Brightness.dark,
    primary: XColors.blue,
    onPrimary: Colors.white,
    secondary: XColors.cyan,
    surface: XColors.card,
    onSurface: XColors.blueDark,
    error: XColors.fail,
  );
  const radius = BorderRadius.all(Radius.circular(16));
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: XColors.bg,
    appBarTheme: const AppBarTheme(
      backgroundColor: XColors.bgTop,
      foregroundColor: Colors.white,
      centerTitle: false,
      elevation: 0,
    ),
    cardTheme: const CardThemeData(
      elevation: 0,
      color: XColors.card,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: XColors.border)),
    ),
    dividerColor: XColors.border,
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide(color: XColors.border)),
      filled: true,
      fillColor: Color(0xFF0A1C3C),
      labelStyle: TextStyle(color: XColors.gray),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 52),
        foregroundColor: XColors.blueDark,
        side: const BorderSide(color: XColors.border),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Color(0xFF071735),
      indicatorColor: Color(0x331E88E5),
      height: 72,
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: Color(0xFF071735),
      indicatorColor: Color(0x331E88E5),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: XColors.cardHi,
      contentTextStyle: TextStyle(color: Colors.white),
      behavior: SnackBarBehavior.floating,
    ),
    dialogTheme: const DialogThemeData(backgroundColor: XColors.card),
  );
}
