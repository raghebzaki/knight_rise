import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:knight_rise/core/shortcuts/app_bindings.dart';
import 'package:knight_rise/core/theme/knight_dimens.dart';
import 'package:knight_rise/core/theme/knight_tokens.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';

/// Whether the cheat sheet is on screen. While it is, the app-wide shortcuts stand down (it is modal) and a second
/// request does not stack another copy.
final ValueNotifier<bool> shortcutsDialogOpen = ValueNotifier(false);

/// Shows the keyboard shortcut cheat sheet over [context]'s navigator. Esc or Close dismisses it and focus returns
/// to where it was (Material's default for dialogs). Does nothing if it is already open.
Future<void> showShortcutsDialog(BuildContext context) async {
  if (shortcutsDialogOpen.value) return;
  shortcutsDialogOpen.value = true;
  try {
    await showDialog<void>(context: context, builder: (_) => const ShortcutsDialog());
  } finally {
    shortcutsDialogOpen.value = false;
  }
}

/// The cheat sheet: every entry of [AppBindings.all], grouped, generated from the same table as the shortcuts
/// themselves. Key caps are laid out left-to-right in every language.
class ShortcutsDialog extends StatelessWidget {
  const ShortcutsDialog({super.key, this.platform});

  /// Overrides [defaultTargetPlatform] for the glyphs (tests).
  final TargetPlatform? platform;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final target = platform ?? defaultTargetPlatform;
    return AlertDialog(
      title: Text(l.shortcutsTitle),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final group in ShortcutGroup.values) ...[
                Padding(
                  padding: const EdgeInsetsDirectional.only(top: KnightSpacing.md, bottom: KnightSpacing.xs),
                  child: Text(
                    group.title(l).toUpperCase(),
                    style: text.labelSmall?.copyWith(color: context.knight.textMuted),
                  ),
                ),
                for (final binding in AppBindings.all.where((b) => b.group == group))
                  _BindingRow(label: binding.label(l), caps: binding.caps(target)),
              ],
            ],
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l.close))],
    );
  }
}

class _BindingRow extends StatelessWidget {
  const _BindingRow({required this.label, required this.caps});

  final String label;
  final List<String> caps;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: KnightSpacing.xs),
      child: Row(
        children: [
          Expanded(child: Text(label, style: text.bodyLarge)),
          const SizedBox(width: KnightSpacing.md),
          // Key caps are hardware legends: left-to-right even inside an RTL row.
          Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final cap in caps)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: KnightSpacing.xs),
                    child: _KeyCap(cap),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _KeyCap extends StatelessWidget {
  const _KeyCap(this.cap);

  final String cap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 28),
      padding: const EdgeInsets.symmetric(horizontal: KnightSpacing.sm, vertical: KnightSpacing.xs),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outline),
        borderRadius: BorderRadius.circular(KnightRadius.sm),
      ),
      child: Text(cap, style: Theme.of(context).textTheme.labelLarge),
    );
  }
}
