/// 4-pt spacing scale.
abstract final class KnightSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Corner radii.
abstract final class KnightRadius {
  static const double sm = 6;
  static const double md = 12;
  static const double lg = 16;

  /// Chamfer size for "armor plate" hero cards.
  static const double chamfer = 12;
}

/// Motion durations.
abstract final class KnightMotion {
  static const Duration ring = Duration(milliseconds: 600);
  static const Duration fast = Duration(milliseconds: 180);
}
