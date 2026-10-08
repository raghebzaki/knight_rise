import 'package:flutter/material.dart';
import 'package:knight_rise/core/config/flavor.dart';
import 'package:knight_rise/core/theme/knight_dimens.dart';
import 'package:knight_rise/core/theme/knight_palette.dart';
import 'package:knight_rise/core/theme/knight_tokens.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';

/// Friendly failure state for a screen whose data stream failed: what
/// happened, that nothing was lost, and a Retry. The raw error is shown in
/// dev builds only.
class KnightErrorView extends StatelessWidget {
  const KnightErrorView({required this.onRetry, this.details, super.key});

  final VoidCallback onRetry;
  final String? details;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final muted = context.knight.textMuted;
    final details = this.details;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(KnightSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shield_moon_outlined, size: 48, color: muted),
            const SizedBox(height: KnightSpacing.md),
            Text(l.errorTitle, style: text.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: KnightSpacing.xs),
            Text(l.errorBody, style: text.bodyMedium, textAlign: TextAlign.center),
            const SizedBox(height: KnightSpacing.lg),
            FilledButton.icon(
              key: const Key('error-retry'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(l.errorRetry),
            ),
            if (Flavor.current.isDev && details != null) ...[
              const SizedBox(height: KnightSpacing.lg),
              Text(
                details,
                style: text.bodySmall?.copyWith(color: muted),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Replaces Flutter's red/grey error box in release builds when a widget
/// fails to build. Built outside the normal tree, so it cannot rely on
/// localizations or the theme.
class KnightBuildErrorFallback extends StatelessWidget {
  const KnightBuildErrorFallback({super.key});

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: KnightPalette.midnight.background,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Something went wrong here. Your data is safe.',
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
          style: TextStyle(color: KnightPalette.midnight.onSurfaceVariant, fontSize: 14),
        ),
      ),
    ),
  );
}
