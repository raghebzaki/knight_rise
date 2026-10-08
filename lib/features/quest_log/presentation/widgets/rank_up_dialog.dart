import 'package:flutter/material.dart';
import 'package:knight_rise/core/theme/knight_dimens.dart';
import 'package:knight_rise/core/theme/knight_tokens.dart';
import 'package:knight_rise/features/quest_log/domain/entities/knight_rank.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';

String rankName(AppLocalizations l, KnightRank rank) => switch (rank) {
  KnightRank.page => l.rankPage,
  KnightRank.squire => l.rankSquire,
  KnightRank.knight => l.rankKnight,
  KnightRank.paladin => l.rankPaladin,
};

/// The rank-up moment: the new rank's badge scales in (instantly with
/// reduced motion), with the streak that earned it.
class RankUpDialog extends StatelessWidget {
  const RankUpDialog({required this.rank, required this.days, super.key});

  final KnightRank rank;
  final int days;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final name = rankName(l, rank);
    return Dialog(
      key: const Key('rank-up-dialog'),
      child: Padding(
        padding: const EdgeInsets.all(KnightSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: reduced ? 1 : 0.4, end: 1),
              duration: reduced ? Duration.zero : const Duration(milliseconds: 700),
              curve: Curves.elasticOut,
              builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
              child: DecoratedBox(
                decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: context.knight.activeGlow),
                child: Icon(Icons.military_tech, size: 72, color: scheme.primary),
              ),
            ),
            const SizedBox(height: KnightSpacing.md),
            Text(l.rankUpTitle.toUpperCase(), style: text.headlineSmall),
            const SizedBox(height: KnightSpacing.xs),
            Text(name.toUpperCase(), style: text.titleLarge?.copyWith(color: scheme.primary)),
            const SizedBox(height: KnightSpacing.sm),
            Text(l.rankUpBody(name, days), style: text.bodyMedium, textAlign: TextAlign.center),
            const SizedBox(height: KnightSpacing.lg),
            FilledButton(onPressed: () => Navigator.of(context).pop(), child: Text(l.rankUpDismiss)),
          ],
        ),
      ),
    );
  }
}
