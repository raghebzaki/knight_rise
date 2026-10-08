import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';

/// Live `MM:SS` / `H:MM:SS` countdown to [target].
///
/// The value is derived from the clock on every tick; nothing is stored.
/// Ticking pauses while the app is in the background.
class CountdownText extends StatefulWidget {
  const CountdownText({required this.target, super.key, this.style});

  final DateTime target;
  final TextStyle? style;

  static String format(Duration remaining) {
    final d = remaining.isNegative ? Duration.zero : remaining;
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  /// Whole minutes for screen readers, rounded up ("4:59" reads as 5).
  static int spokenMinutes(Duration remaining) =>
      remaining.isNegative ? 0 : (remaining.inSeconds + 59) ~/ Duration.secondsPerMinute;

  @override
  State<CountdownText> createState() => _CountdownTextState();
}

class _CountdownTextState extends State<CountdownText> {
  Timer? _timer;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _start();
    _lifecycle = AppLifecycleListener(onResume: _start, onPause: _stop);
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    if (mounted) setState(() {});
  }

  void _stop() => _timer?.cancel();

  @override
  void dispose() {
    _timer?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = context.read<Clock>().now();
    final remaining = widget.target.difference(now);
    return Semantics(
      // The spoken label changes at most once a minute, so the live region
      // is announced per minute, never per second.
      liveRegion: true,
      label: AppLocalizations.of(context).countdownRemaining(CountdownText.spokenMinutes(remaining)),
      child: ExcludeSemantics(child: Text(CountdownText.format(remaining), style: widget.style)),
    );
  }
}
