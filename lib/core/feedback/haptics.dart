import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:knight_rise/features/settings/domain/repositories/settings_repository.dart';

/// What an action feels like.
enum HapticKind {
  /// Picking an option (presets, filters).
  selection,

  /// A small confirmation (snooze, extend).
  light,

  /// A completed action (Done, water logged, Shield up).
  success,

  /// A rank-up.
  celebrate,
}

/// Plays haptic feedback while the user has it on (Settings › Haptic
/// feedback). Follows the setting through the settings stream, so a toggle
/// applies immediately. Provided to the widget tree in `app.dart`; widgets
/// call `context.haptic(...)`, which is a no-op where none is provided.
@lazySingleton
class Haptics {
  Haptics(SettingsRepository settings) : this.withPerformer(settings, _platform);

  /// Tests pass a recording `perform`.
  @visibleForTesting
  Haptics.withPerformer(SettingsRepository settings, this._perform) {
    _sub = settings.watch().listen((s) => _enabled = s.hapticsEnabled);
  }

  final Future<void> Function(HapticKind kind) _perform;
  late final StreamSubscription<Object?> _sub;
  bool _enabled = true;

  void play(HapticKind kind) {
    if (_enabled) unawaited(_perform(kind));
  }

  @disposeMethod
  Future<void> dispose() => _sub.cancel();

  static Future<void> _platform(HapticKind kind) => switch (kind) {
    HapticKind.selection => HapticFeedback.selectionClick(),
    HapticKind.light => HapticFeedback.lightImpact(),
    HapticKind.success => HapticFeedback.mediumImpact(),
    HapticKind.celebrate => HapticFeedback.heavyImpact(),
  };
}

extension HapticsContext on BuildContext {
  /// Plays [kind] through the nearest [Haptics], if any (none in most tests).
  void haptic(HapticKind kind) => read<Haptics?>()?.play(kind);
}
