import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:knight_rise/core/feedback/haptics.dart';
import 'package:knight_rise/core/shortcuts/app_intents.dart';
import 'package:knight_rise/core/theme/knight_dimens.dart';
import 'package:knight_rise/core/theme/knight_tokens.dart';
import 'package:knight_rise/core/theme/widgets/knight_card.dart';
import 'package:knight_rise/core/theme/widgets/knight_ring.dart';
import 'package:knight_rise/features/cycle/presentation/bloc/cycle_bloc.dart';
import 'package:knight_rise/features/cycle/presentation/widgets/routine_presentation.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';

/// Length of the eye-rest countdown (the 20-20-20 rule).
const int kEyeRestSeconds = 20;

/// Water amounts offered on the break screen, in ml.
const List<int> kWaterChoicesMl = [150, 250, 500];

/// Default selected water amount.
const int kDefaultWaterMl = 250;

/// Guided break opened from a notification tap: one page per routine, in
/// [RoutineType] order, with page dots when there is more than one.
///
/// Each page ends in a Done / Log action that dispatches [RoutineCompleted]
/// to the [CycleBloc]; after the last routine is done the screen closes and
/// shows a "Quest updated" snackbar.
class BreakPage extends StatefulWidget {
  const BreakPage({required this.types, super.key});

  /// Routines to guide through, already sorted and de-duplicated.
  final List<RoutineType> types;

  @override
  State<BreakPage> createState() => _BreakPageState();
}

class _BreakPageState extends State<BreakPage> {
  final _controller = PageController();
  final _done = <RoutineType>{};
  int _page = 0;

  /// Selected water amount; held here so the Done shortcut logs what the chips show.
  int _waterMl = kDefaultWaterMl;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _complete(RoutineType type, {int? waterMl}) {
    if (!_done.add(type)) return;
    context.haptic(HapticKind.success);
    context.read<CycleBloc>().add(RoutineCompleted(type, waterMl: waterMl));
    final next = widget.types.where((t) => !_done.contains(t)).firstOrNull;
    if (next == null) {
      _finish();
    } else {
      _controller.animateToPage(widget.types.indexOf(next), duration: KnightMotion.ring, curve: Curves.easeOutCubic);
      setState(() {});
    }
  }

  /// Mod+Enter: Done / Log on the step in view (a no-op once that step is done).
  void _completeCurrent() {
    final type = widget.types[_page.clamp(0, widget.types.length - 1)];
    _complete(type, waterMl: type == RoutineType.hydration ? _waterMl : null);
  }

  /// Esc: leave the break, like the back button.
  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  void _finish() {
    final messenger = ScaffoldMessenger.of(context);
    final message = AppLocalizations.of(context).questUpdated;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final types = widget.types;
    // The Actions sit above an autofocused Focus so they are on the focus path even before anything inside is
    // focused; they override the app-wide Done (Mod+Enter) and close (Esc) for this page. Done stays enabled
    // (and does nothing) after the step is complete so the key never falls through to Today's reminders.
    return Actions(
      actions: {
        CompleteNextIntent: CallbackAction<CompleteNextIntent>(onInvoke: (_) => _completeCurrent()),
        DismissIntent: CallbackAction<DismissIntent>(onInvoke: (_) => _leave()),
      },
      child: Focus(autofocus: true, skipTraversal: true, child: _scaffold(l, types)),
    );
  }

  Widget _scaffold(AppLocalizations l, List<RoutineType> types) {
    return Scaffold(
      appBar: AppBar(title: Text(l.breakTitle.toUpperCase())),
      body: SafeArea(
        child: Column(
          children: [
            if (types.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: KnightSpacing.sm),
                child: _PageDots(count: types.length, index: _page, label: l.breakStepOf(_page + 1, types.length)),
              ),
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  for (final type in types)
                    _StepFrame(
                      type: type,
                      child: switch (type) {
                        RoutineType.eyeRest => _EyeRestStep(
                          onDone: _done.contains(type) ? null : () => _complete(type),
                        ),
                        RoutineType.stretch => _StretchStep(
                          onDone: _done.contains(type) ? null : () => _complete(type),
                        ),
                        RoutineType.hydration => _HydrationStep(
                          ml: _waterMl,
                          onSelect: (ml) => setState(() => _waterMl = ml),
                          onLog: _done.contains(type) ? null : (ml) => _complete(type, waterMl: ml),
                        ),
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.index, required this.label});

  final int count;
  final int index;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < count; i++)
              AnimatedContainer(
                duration: KnightMotion.fast,
                margin: const EdgeInsets.symmetric(horizontal: KnightSpacing.xs),
                width: i == index ? 20 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: i == index ? scheme.primary : scheme.outline,
                  borderRadius: BorderRadius.circular(KnightRadius.sm),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Routine header + scrollable, width-limited content.
class _StepFrame extends StatelessWidget {
  const _StepFrame({required this.type, required this.child});

  final RoutineType type;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final color = context.knight.routineColor(type);
    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.fromSTEB(
        KnightSpacing.lg,
        KnightSpacing.sm,
        KnightSpacing.lg,
        KnightSpacing.xxl,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(type.icon, color: color),
                  const SizedBox(width: KnightSpacing.sm),
                  Text(type.label(l).toUpperCase(), style: text.titleLarge?.copyWith(color: color)),
                ],
              ),
              const SizedBox(height: KnightSpacing.xl),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- eye rest

class _EyeRestStep extends StatefulWidget {
  const _EyeRestStep({required this.onDone});

  /// Null once this routine has been completed.
  final VoidCallback? onDone;

  @override
  State<_EyeRestStep> createState() => _EyeRestStepState();
}

class _EyeRestStepState extends State<_EyeRestStep> {
  int _remaining = kEyeRestSeconds;
  Timer? _timer;

  bool get _running => _timer != null;
  bool get _finished => _remaining <= 0;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _start() {
    if (_running || _finished) return;
    setState(() {
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() => _remaining--);
        if (_remaining <= 0) {
          timer.cancel();
          _timer = null;
          if (mounted) context.haptic(HapticKind.light);
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final color = context.knight.routineColor(RoutineType.eyeRest);
    final progress = (kEyeRestSeconds - _remaining) / kEyeRestSeconds;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.eyeRestInstruction, style: text.headlineMedium, textAlign: TextAlign.center),
        const SizedBox(height: KnightSpacing.sm),
        Text(l.eyeRestHint, style: text.bodyMedium, textAlign: TextAlign.center),
        const SizedBox(height: KnightSpacing.xl),
        Center(
          child: KnightRing(
            segments: [RingSegment(progress: progress, color: color, label: l.eyeRestSecondsLeft(_remaining))],
            // Keep the Orbitron digits inside the ring at large text scales.
            center: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1,
              child: Text('$_remaining', style: text.displayLarge),
            ),
          ),
        ),
        const SizedBox(height: KnightSpacing.xl),
        if (!_running && !_finished) ...[
          FilledButton(onPressed: _start, child: Text(l.start)),
          const SizedBox(height: KnightSpacing.md),
        ],
        _DoneButton(label: l.done, primary: _finished, onPressed: widget.onDone),
      ],
    );
  }
}

/// Done / Log button: filled when it is the recommended next action,
/// outlined while something else is.
class _DoneButton extends StatelessWidget {
  const _DoneButton({required this.label, required this.primary, required this.onPressed});

  final String label;
  final bool primary;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => primary
      ? FilledButton(onPressed: onPressed, child: Text(label))
      : OutlinedButton(onPressed: onPressed, child: Text(label));
}

// -------------------------------------------------------------- stretch

class _StretchStep extends StatefulWidget {
  const _StretchStep({required this.onDone});

  final VoidCallback? onDone;

  @override
  State<_StretchStep> createState() => _StretchStepState();
}

class _StretchStepState extends State<_StretchStep> {
  final _ticked = <int>{};

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final color = context.knight.routineColor(RoutineType.stretch);
    final steps = [
      (l.stretchNeckTitle, l.stretchNeckHint),
      (l.stretchShouldersTitle, l.stretchShouldersHint),
      (l.stretchReachTitle, l.stretchReachHint),
      (l.stretchHipTitle, l.stretchHipHint),
    ];
    final allTicked = _ticked.length == steps.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.stretchInstruction, style: text.headlineMedium, textAlign: TextAlign.center),
        const SizedBox(height: KnightSpacing.sm),
        Text(l.stretchHint, style: text.bodyMedium, textAlign: TextAlign.center),
        const SizedBox(height: KnightSpacing.xl),
        KnightCard(
          padding: const EdgeInsets.symmetric(vertical: KnightSpacing.sm),
          child: Column(
            children: [
              for (final (i, step) in steps.indexed)
                CheckboxListTile(
                  value: _ticked.contains(i),
                  activeColor: color,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(step.$1, style: text.titleMedium),
                  subtitle: Text(step.$2, style: text.bodySmall),
                  onChanged: (v) => setState(() => (v ?? false) ? _ticked.add(i) : _ticked.remove(i)),
                ),
            ],
          ),
        ),
        const SizedBox(height: KnightSpacing.xl),
        _DoneButton(label: l.done, primary: allTicked, onPressed: widget.onDone),
      ],
    );
  }
}

// ------------------------------------------------------------ hydration

class _HydrationStep extends StatelessWidget {
  const _HydrationStep({required this.ml, required this.onSelect, required this.onLog});

  /// Selected amount, owned by the page.
  final int ml;
  final ValueChanged<int> onSelect;
  final ValueChanged<int>? onLog;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.hydrationInstruction, style: text.headlineMedium, textAlign: TextAlign.center),
        const SizedBox(height: KnightSpacing.sm),
        Text(l.hydrationHint, style: text.bodyMedium, textAlign: TextAlign.center),
        const SizedBox(height: KnightSpacing.xl),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: KnightSpacing.md,
          runSpacing: KnightSpacing.sm,
          children: [
            for (final choice in kWaterChoicesMl)
              ChoiceChip(label: Text(l.mlAmount(choice)), selected: ml == choice, onSelected: (_) => onSelect(choice)),
          ],
        ),
        const SizedBox(height: KnightSpacing.xl),
        FilledButton(onPressed: onLog == null ? null : () => onLog!(ml), child: Text(l.logWater)),
      ],
    );
  }
}
