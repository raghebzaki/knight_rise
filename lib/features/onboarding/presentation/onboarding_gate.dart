import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:knight_rise/features/settings/domain/repositories/settings_repository.dart';

/// Whether first-run onboarding has finished. The router redirects on it
/// (`refreshListenable`), so flipping [completed] moves the user off
/// `/onboarding`.
///
/// Defaults to not completed until [load] has run; `main()` awaits [load]
/// before `runApp` so the first frame already routes correctly.
@lazySingleton
class OnboardingGate extends ChangeNotifier {
  OnboardingGate(this._settings);

  final SettingsRepository _settings;
  StreamSubscription<bool>? _sub;
  bool _completed = false;

  bool get completed => _completed;

  /// Reads the stored flag and keeps following it. Idempotent.
  Future<void> load() async {
    if (_sub != null) return;
    final first = Completer<void>();
    _sub = _settings.watch().map((s) => s.onboardingCompleted).listen((value) {
      _set(value);
      if (!first.isCompleted) first.complete();
    });
    await first.future;
  }

  void _set(bool value) {
    if (value == _completed) return;
    _completed = value;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }
}
