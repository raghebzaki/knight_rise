import 'package:flutter/widgets.dart';

/// Lower bound (logical px) of [WindowSizeClass.medium].
const double kMediumBreakpoint = 600;

/// Lower bound (logical px) of [WindowSizeClass.expanded].
const double kExpandedBreakpoint = 840;

/// Lower bound (logical px) of [WindowSizeClass.large].
const double kLargeBreakpoint = 1200;

/// Material 3 window width classes.
enum WindowSizeClass {
  /// Under 600: phones. Bottom navigation.
  compact,

  /// 600 to 839: large phones, small tablets. Navigation rail.
  medium,

  /// 840 to 1199: tablets, small desktop windows. Labelled rail.
  expanded,

  /// 1200 and up: desktop. Extended sidebar.
  large;

  /// The class for a window [width] in logical pixels.
  static WindowSizeClass fromWidth(double width) {
    if (width >= kLargeBreakpoint) return large;
    if (width >= kExpandedBreakpoint) return expanded;
    if (width >= kMediumBreakpoint) return medium;
    return compact;
  }

  /// Whether navigation moves from the bottom bar to a side rail (medium+).
  bool get usesRail => this != compact;

  /// Whether there is room for list and detail side by side (expanded+).
  bool get isMultiPane => this == expanded || this == large;
}

/// The window size class of the surrounding [MediaQuery].
extension WindowSizeX on BuildContext {
  /// Class of the current window width; rebuilds only when the size changes.
  WindowSizeClass get windowSizeClass => WindowSizeClass.fromWidth(MediaQuery.sizeOf(this).width);

  /// See [WindowSizeClass.usesRail].
  bool get usesRail => windowSizeClass.usesRail;

  /// See [WindowSizeClass.isMultiPane].
  bool get isMultiPane => windowSizeClass.isMultiPane;
}
