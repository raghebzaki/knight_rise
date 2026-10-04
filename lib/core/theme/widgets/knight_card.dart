import 'package:flutter/material.dart';
import 'package:knight_rise/core/theme/knight_dimens.dart';
import 'package:knight_rise/core/theme/knight_tokens.dart';

/// Flat surface card with a steel border.
///
/// [glow] marks the active / next-due card (cyan border + glow).
/// [chamfered] gives hero cards the beveled "armor plate" corners.
class KnightCard extends StatelessWidget {
  const KnightCard({
    required this.child,
    super.key,
    this.glow = false,
    this.chamfered = false,
    this.padding = const EdgeInsets.all(KnightSpacing.lg),
    this.onTap,
  });

  final Widget child;
  final bool glow;
  final bool chamfered;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.knight;
    final side = BorderSide(color: glow ? scheme.primary : scheme.outline, width: glow ? 1.5 : 1);
    final ShapeBorder shape = chamfered
        ? BeveledRectangleBorder(borderRadius: BorderRadius.circular(KnightRadius.chamfer), side: side)
        : RoundedRectangleBorder(borderRadius: BorderRadius.circular(KnightRadius.lg), side: side);

    return AnimatedContainer(
      duration: KnightMotion.fast,
      decoration: ShapeDecoration(color: scheme.surface, shape: shape, shadows: glow ? tokens.activeGlow : const []),
      child: Material(
        type: MaterialType.transparency,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
