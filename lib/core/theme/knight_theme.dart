import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:knight_rise/core/theme/knight_dimens.dart';
import 'package:knight_rise/core/theme/knight_palette.dart';
import 'package:knight_rise/core/theme/knight_tokens.dart';

/// Font family names, matching pubspec.yaml.
abstract final class KnightFonts {
  static const display = 'Orbitron';
  static const title = 'Rajdhani';
  static const body = 'Inter';
}

/// Builds [ThemeData] for a [KnightPalette].
abstract final class KnightTheme {
  static ThemeData build(KnightPalette p) {
    final scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: p.primary,
      onPrimary: p.onPrimary,
      secondary: p.secondary,
      onSecondary: p.onSurface,
      error: p.error,
      onError: p.onPrimary,
      surface: p.surface,
      onSurface: p.onSurface,
      onSurfaceVariant: p.onSurfaceVariant,
      surfaceContainerHighest: p.surfaceContainerHigh,
      surfaceContainerHigh: p.surfaceContainerHigh,
      surfaceContainer: p.surface,
      surfaceContainerLow: p.surface,
      surfaceContainerLowest: p.background,
      outline: p.outline,
      outlineVariant: p.outline,
      surfaceTint: Colors.transparent,
    );

    final text = textTheme(p);
    final mdShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(KnightRadius.md));

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.background,
      canvasColor: p.background,
      fontFamily: KnightFonts.body,
      textTheme: text,
      extensions: [KnightTokens.fromPalette(p)],
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: p.background,
        foregroundColor: p.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: text.headlineSmall,
        systemOverlayStyle: overlayStyle(p),
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KnightRadius.lg),
          side: BorderSide(color: p.outline),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
          shape: WidgetStatePropertyAll(mdShape),
          textStyle: WidgetStatePropertyAll(text.labelLarge),
          foregroundColor: WidgetStatePropertyAll(p.onPrimary),
          backgroundColor: WidgetStateProperty.resolveWith((s) {
            if (s.contains(WidgetState.disabled)) return p.outline;
            if (s.contains(WidgetState.pressed)) return p.primaryPressed;
            return p.primary;
          }),
          shadowColor: WidgetStatePropertyAll(p.glow),
          elevation: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.pressed) ? 8 : 0),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
          shape: WidgetStatePropertyAll(mdShape),
          textStyle: WidgetStatePropertyAll(text.labelLarge),
          foregroundColor: WidgetStatePropertyAll(p.onSurface),
          side: WidgetStateProperty.resolveWith((s) {
            final active =
                s.contains(WidgetState.hovered) || s.contains(WidgetState.focused) || s.contains(WidgetState.pressed);
            return BorderSide(color: active ? p.primary : p.outlineStrong);
          }),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          shape: WidgetStatePropertyAll(mdShape),
          textStyle: WidgetStatePropertyAll(text.labelLarge),
          foregroundColor: WidgetStatePropertyAll(p.primary),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.primary : p.outlineStrong,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.primary.withValues(alpha: 0.4) : p.surfaceContainerHigh,
        ),
        trackOutlineColor: WidgetStatePropertyAll(p.outline),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: p.primary,
        inactiveTrackColor: p.outline,
        thumbColor: p.primary,
        overlayColor: p.glow,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surface,
        selectedColor: p.primary.withValues(alpha: 0.16),
        side: BorderSide(color: p.outline),
        labelStyle: text.labelSmall,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KnightRadius.sm)),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          side: WidgetStatePropertyAll(BorderSide(color: p.outline)),
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? p.primary.withValues(alpha: 0.16) : Colors.transparent,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? p.primary : p.onSurfaceVariant,
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: p.primary.withValues(alpha: 0.16),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? p.primary : p.onSurfaceVariant),
        ),
        labelTextStyle: WidgetStatePropertyAll(text.labelSmall),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KnightRadius.lg),
          side: BorderSide(color: p.outline),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.surfaceContainerHigh,
        contentTextStyle: text.bodyMedium,
        actionTextColor: p.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KnightRadius.md),
          side: BorderSide(color: p.outline),
        ),
      ),
      dividerTheme: DividerThemeData(color: p.outline, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: p.onSurfaceVariant),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: p.primary, linearTrackColor: p.surfaceContainerHigh),
    );
  }

  /// Type scale from the architecture doc.
  ///
  /// Orbitron and Inter ship as variable fonts, so weight is applied through
  /// [FontVariation] as well as [FontWeight].
  static TextTheme textTheme(KnightPalette p) {
    TextStyle inter(double size, double height, double weight, {double ls = 0}) => TextStyle(
      fontFamily: KnightFonts.body,
      fontSize: size,
      height: height / size,
      fontWeight: _weight(weight),
      fontVariations: [FontVariation.weight(weight)],
      letterSpacing: ls,
      color: p.onSurface,
    );
    TextStyle rajdhani(double size, double height, FontWeight weight, {double ls = 0}) => TextStyle(
      fontFamily: KnightFonts.title,
      fontSize: size,
      height: height / size,
      fontWeight: weight,
      letterSpacing: ls,
      color: p.onSurface,
    );

    return TextTheme(
      displayLarge: displayNumbers(p, 48),
      displayMedium: displayNumbers(p, 36),
      displaySmall: displayNumbers(p, 24),
      headlineLarge: rajdhani(32, 38, FontWeight.w700, ls: 0.5),
      headlineMedium: rajdhani(28, 34, FontWeight.w700, ls: 0.5),
      headlineSmall: rajdhani(24, 30, FontWeight.w700, ls: 0.5),
      titleLarge: rajdhani(20, 26, FontWeight.w600),
      titleMedium: inter(16, 22, 600),
      titleSmall: inter(14, 20, 600),
      bodyLarge: inter(16, 24, 400),
      bodyMedium: inter(14, 20, 400).copyWith(color: p.onSurfaceVariant),
      bodySmall: inter(12, 16, 400).copyWith(color: p.onSurfaceVariant),
      labelLarge: inter(14, 20, 600, ls: 0.4),
      labelMedium: inter(12, 16, 500, ls: 0.4),
      labelSmall: inter(11, 16, 500, ls: 0.4).copyWith(color: p.onSurfaceVariant),
    );
  }

  /// Orbitron with tabular figures, for timers and ring centers.
  static TextStyle displayNumbers(KnightPalette p, double size) => TextStyle(
    fontFamily: KnightFonts.display,
    fontSize: size,
    height: 1.16,
    fontWeight: FontWeight.w600,
    fontVariations: const [FontVariation.weight(600)],
    fontFeatures: const [FontFeature.tabularFigures()],
    color: p.onSurface,
  );

  static SystemUiOverlayStyle overlayStyle(KnightPalette p) => SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: p.background,
    systemNavigationBarIconBrightness: Brightness.light,
  );

  static FontWeight _weight(double w) => FontWeight.values[((w / 100).round() - 1).clamp(0, 8)];
}
