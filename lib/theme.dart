import 'package:flutter/material.dart';

import 'calc.dart';

/// Identidade visual UNITECH: azul tecnológico, prata/cinza,
/// verde (aprovado), amarelo (alerta) e vermelho (falha).
class XColors {
  static const blue = Color(0xFF0B57A4);
  static const blueDark = Color(0xFF06345F);
  static const silver = Color(0xFFB8C2CC);
  static const gray = Color(0xFF5F6B76);
  static const surface = Color(0xFFF2F5F8);
  static const ok = Color(0xFF2E7D32);
  static const warn = Color(0xFFF9A825);
  static const fail = Color(0xFFC62828);
  static const demo = Color(0xFF8E24AA);

  static Color status(MeasureStatus s) => switch (s) {
        MeasureStatus.approved => ok,
        MeasureStatus.alert => warn,
        MeasureStatus.failed => fail,
        MeasureStatus.unknown => gray,
      };

  /// Texto legível sobre a cor do status (preto sobre amarelo).
  static Color onStatus(MeasureStatus s) =>
      s == MeasureStatus.alert ? Colors.black : Colors.white;
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: XColors.blue,
    primary: XColors.blue,
    secondary: XColors.gray,
    surface: Colors.white,
    error: XColors.fail,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: XColors.surface,
    appBarTheme: const AppBarTheme(
      backgroundColor: XColors.blueDark,
      foregroundColor: Colors.white,
      centerTitle: false,
    ),
    cardTheme: const CardThemeData(
      elevation: 0,
      color: Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        side: BorderSide(color: Color(0xFFDDE3E9)),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      filled: true,
      fillColor: Colors.white,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 52),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
  );
}
