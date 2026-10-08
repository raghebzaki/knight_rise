import 'package:flutter/material.dart' show ThemeData;
import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';

/// Theme variants shipped in v1. No light theme by design.
enum ThemeVariant { midnight, amoled }

/// Raw brand colors for one theme variant.
///
/// This is the only place in the app where hex color literals are allowed.
/// Widgets read colors through [ThemeData] / `context.knight`, never from here.
@immutable
class KnightPalette {
  const KnightPalette({
    required this.variant,
    required this.primary,
    required this.primaryPressed,
    required this.onPrimary,
    required this.secondary,
    required this.background,
    required this.surface,
    required this.surfaceContainerHigh,
    required this.outline,
    required this.outlineStrong,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.textMuted,
    required this.glow,
    required this.success,
    required this.warning,
    required this.error,
    required this.hydration,
    required this.stretch,
    required this.eyeRest,
  });

  final ThemeVariant variant;

  final Color primary;
  final Color primaryPressed;
  final Color onPrimary;
  final Color secondary;
  final Color background;
  final Color surface;
  final Color surfaceContainerHigh;
  final Color outline;
  final Color outlineStrong;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color textMuted;
  final Color glow;
  final Color success;
  final Color warning;
  final Color error;
  final Color hydration;
  final Color stretch;
  final Color eyeRest;

  /// Deep midnight navy with steel borders. The default.
  static const midnight = KnightPalette(
    variant: ThemeVariant.midnight,
    primary: Color(0xFF00E5FF),
    primaryPressed: Color(0xFF00B8D4),
    onPrimary: Color(0xFF00212A),
    secondary: Color(0xFF2F80FF),
    background: Color(0xFF0A1020),
    surface: Color(0xFF111A2E),
    surfaceContainerHigh: Color(0xFF1A2540),
    outline: Color(0xFF34445F),
    outlineStrong: Color(0xFF5B6B87),
    onSurface: Color(0xFFE6EDF5),
    onSurfaceVariant: Color(0xFFA7B4C8),
    textMuted: Color(0xFF7686A0), // ≥ 4.5:1 on background and surface
    glow: Color(0x4D00E5FF), // 30%
    success: Color(0xFF2EE6A6),
    warning: Color(0xFFFFB547),
    error: Color(0xFFFF5C7A),
    hydration: Color(0xFF00E5FF),
    stretch: Color(0xFFBCEC3B), // neon lime: distinct from hydration, eye rest and the success status
    eyeRest: Color(0xFF8FA8FF),
  );

  /// True-black surfaces for OLED screens; separation comes from borders.
  static const amoled = KnightPalette(
    variant: ThemeVariant.amoled,
    primary: Color(0xFF00E5FF),
    primaryPressed: Color(0xFF00B8D4),
    onPrimary: Color(0xFF00212A),
    secondary: Color(0xFF2F80FF),
    background: Color(0xFF000000),
    surface: Color(0xFF05080F),
    surfaceContainerHigh: Color(0xFF0C1322),
    outline: Color(0xFF263248),
    outlineStrong: Color(0xFF52617E), // ≥ 3:1 on surface (Switch off thumb, outlined buttons)
    onSurface: Color(0xFFE6EDF5),
    onSurfaceVariant: Color(0xFF9AA7BC),
    textMuted: Color(0xFF72819A), // ≥ 4.5:1 on background and surface
    glow: Color(0x6600E5FF), // 40%
    success: Color(0xFF2EE6A6),
    warning: Color(0xFFFFB547),
    error: Color(0xFFFF5C7A),
    hydration: Color(0xFF00E5FF),
    stretch: Color(0xFFBCEC3B), // neon lime: distinct from hydration, eye rest and the success status
    eyeRest: Color(0xFF8FA8FF),
  );

  static KnightPalette of(ThemeVariant variant) => switch (variant) {
    ThemeVariant.midnight => midnight,
    ThemeVariant.amoled => amoled,
  };
}
