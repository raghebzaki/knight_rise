import 'package:flutter/widgets.dart';

extension LargeTextContext on BuildContext {
  /// True at 1.5× text and above, where side-by-side layouts (a title next
  /// to a value or a button) stack instead, so nothing overflows or clips.
  bool get isLargeText => MediaQuery.textScalerOf(this).scale(10) >= 15;
}
