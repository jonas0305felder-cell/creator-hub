import 'package:flutter/material.dart';

/// Farben, Abstände und Rundungen der App an einer Stelle.
class AppColors {
  AppColors._();

  /// Grundfarbe der App (Knöpfe, Akzente), solange kein Account aktiv ist.
  static const Color brand = Color(0xFF6C4CF1);

  /// Farben, aus denen jeder Account seine feste Farbe wählt.
  static const List<Color> accountPalette = [
    Color(0xFF6C4CF1),
    Color(0xFFE5484D),
    Color(0xFFF76B15),
    Color(0xFFFFB224),
    Color(0xFF30A46C),
    Color(0xFF12A594),
    Color(0xFF0091FF),
    Color(0xFF3E63DD),
    Color(0xFFD6409F),
    Color(0xFF8D8D8D),
  ];

  static const Color positive = Color(0xFF2B9A66);
  static const Color negative = Color(0xFFD93D42);
  static const Color warning = Color(0xFFB7791F);

  /// Farben der Ideen-Status.
  static const Map<String, Color> status = {
    'idea': Color(0xFF8D8D8D),
    'in_progress': Color(0xFF0091FF),
    'ready': Color(0xFF30A46C),
    'published': Color(0xFF6C4CF1),
    'discarded': Color(0xFFBDBDBD),
  };
}

/// Einheitliche Abstände.
class AppSpacing {
  AppSpacing._();
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Rundung von Karten und Eingabefeldern.
  static const double radius = 14;
}

/// Baut das Material-Design-Thema aus der Grundfarbe.
ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.brand, brightness: brightness);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radius)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.radius)),
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.l, vertical: AppSpacing.m),
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(48, 48))),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48))),
    appBarTheme: AppBarTheme(backgroundColor: scheme.surface, scrolledUnderElevation: 0),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

/// Wandelt `#RRGGBB` in eine Farbe um (ungültige Werte: Grundfarbe).
Color colorFromHex(String? hex) {
  if (hex == null || hex.length != 7 || !hex.startsWith('#')) return AppColors.brand;
  final value = int.tryParse(hex.substring(1), radix: 16);
  return value == null ? AppColors.brand : Color(0xFF000000 | value);
}

/// Wandelt eine Farbe in `#RRGGBB` um.
String colorToHex(Color color) {
  final value = color.toARGB32() & 0xFFFFFF;
  return '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// Gut lesbare Schriftfarbe (schwarz oder weiß) auf einer Hintergrundfarbe.
Color onColor(Color background) => background.computeLuminance() > 0.5 ? Colors.black : Colors.white;
