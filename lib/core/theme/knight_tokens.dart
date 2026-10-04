import 'package:flutter/material.dart';
import 'package:knight_rise/core/theme/knight_palette.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';

/// Brand-only values that [ColorScheme] has no slot for.
@immutable
class KnightTokens extends ThemeExtension<KnightTokens> {
  const KnightTokens({
    required this.variant,
    required this.glow,
    required this.success,
    required this.warning,
    required this.outlineStrong,
    required this.textMuted,
    required this.hydration,
    required this.stretch,
    required this.eyeRest,
    required this.ringTrack,
  });

  factory KnightTokens.fromPalette(KnightPalette p) => KnightTokens(
    variant: p.variant,
    glow: p.glow,
    success: p.success,
    warning: p.warning,
    outlineStrong: p.outlineStrong,
    textMuted: p.textMuted,
    hydration: p.hydration,
    stretch: p.stretch,
    eyeRest: p.eyeRest,
    ringTrack: p.surfaceContainerHigh,
  );

  final ThemeVariant variant;
  final Color glow;
  final Color success;
  final Color warning;
  final Color outlineStrong;
  final Color textMuted;
  final Color hydration;
  final Color stretch;
  final Color eyeRest;
  final Color ringTrack;

  /// Glow used on the active / next-due card.
  List<BoxShadow> get activeGlow => [BoxShadow(color: glow, blurRadius: 16)];

  Color routineColor(RoutineType type) => switch (type) {
    RoutineType.hydration => hydration,
    RoutineType.stretch => stretch,
    RoutineType.eyeRest => eyeRest,
  };

  @override
  KnightTokens copyWith({
    ThemeVariant? variant,
    Color? glow,
    Color? success,
    Color? warning,
    Color? outlineStrong,
    Color? textMuted,
    Color? hydration,
    Color? stretch,
    Color? eyeRest,
    Color? ringTrack,
  }) => KnightTokens(
    variant: variant ?? this.variant,
    glow: glow ?? this.glow,
    success: success ?? this.success,
    warning: warning ?? this.warning,
    outlineStrong: outlineStrong ?? this.outlineStrong,
    textMuted: textMuted ?? this.textMuted,
    hydration: hydration ?? this.hydration,
    stretch: stretch ?? this.stretch,
    eyeRest: eyeRest ?? this.eyeRest,
    ringTrack: ringTrack ?? this.ringTrack,
  );

  @override
  KnightTokens lerp(covariant KnightTokens? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return KnightTokens(
      variant: t < 0.5 ? variant : other.variant,
      glow: l(glow, other.glow),
      success: l(success, other.success),
      warning: l(warning, other.warning),
      outlineStrong: l(outlineStrong, other.outlineStrong),
      textMuted: l(textMuted, other.textMuted),
      hydration: l(hydration, other.hydration),
      stretch: l(stretch, other.stretch),
      eyeRest: l(eyeRest, other.eyeRest),
      ringTrack: l(ringTrack, other.ringTrack),
    );
  }
}

extension KnightThemeX on BuildContext {
  KnightTokens get knight => Theme.of(this).extension<KnightTokens>()!;
}
