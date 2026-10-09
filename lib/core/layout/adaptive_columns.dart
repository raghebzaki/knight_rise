import 'package:flutter/widgets.dart';
import 'package:knight_rise/core/theme/knight_dimens.dart';

/// Widest content width (logical px) of a multi-column page on large windows.
const double kMaxContentWidth = 1280;

/// Widest a single-column page grows before it stops stretching.
const double kReadableWidth = 720;

/// Centres [child] and caps its width at [maxWidth], so a phone-style page
/// does not stretch across a large window. Narrower windows are unaffected.
class ReadableWidth extends StatelessWidget {
  const ReadableWidth({required this.child, this.maxWidth = kReadableWidth, super.key});

  final Widget child;

  /// Widest the child may be.
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}

/// Two side-by-side columns separated by a [gutter], centred and capped at
/// [maxWidth]. [start] sits on the reading-start side (right in RTL).
///
/// The columns get the full available height and do not scroll by
/// themselves: pass scrollable children (each `ListView` then scrolls
/// independently), or plain widgets for a static layout.
class AdaptiveTwoColumn extends StatelessWidget {
  const AdaptiveTwoColumn({
    required this.start,
    required this.end,
    this.startFlex = 1,
    this.endFlex = 1,
    this.gutter = KnightSpacing.xl,
    this.maxWidth = kMaxContentWidth,
    super.key,
  });

  final Widget start;
  final Widget end;
  final int startFlex;
  final int endFlex;

  /// Space between the columns.
  final double gutter;

  /// Widest the pair may be; wider windows centre it.
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: startFlex, child: start),
          SizedBox(width: gutter),
          Expanded(flex: endFlex, child: end),
        ],
      ),
    ),
  );
}
