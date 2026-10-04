import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:knight_rise/core/theme/knight_palette.dart';
import 'package:knight_rise/features/settings/domain/repositories/settings_repository.dart';

/// Current theme variant, persisted in settings.
@injectable
class ThemeCubit extends Cubit<ThemeVariant> {
  ThemeCubit(this._settings) : super(ThemeVariant.midnight) {
    _sub = _settings.watch().listen((s) => emit(s.themeVariant));
  }

  final SettingsRepository _settings;
  late final StreamSubscription<Object?> _sub;

  Future<void> setVariant(ThemeVariant variant) async {
    final current = await _settings.get();
    await _settings.save(current.copyWith(themeVariant: variant));
  }

  Future<void> toggle() => setVariant(state == ThemeVariant.midnight ? ThemeVariant.amoled : ThemeVariant.midnight);

  @override
  Future<void> close() async {
    await _sub.cancel();
    await super.close();
  }
}
