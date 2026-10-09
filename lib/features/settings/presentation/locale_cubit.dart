import 'dart:ui' show Locale;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:knight_rise/features/settings/domain/repositories/settings_repository.dart';
import 'package:knight_rise/l10n/app_locales.dart';

/// The chosen app language, persisted in settings; null follows the device
/// language. A singleton provided above the provider scope (see `app.dart`)
/// and [load]ed before the first frame, so the app never flashes the other
/// language on launch.
///
/// The only writer of `localeCode`, so it does not watch settings: a watch
/// echo arriving after a quicker second switch would flip the UI back.
@lazySingleton
class LocaleCubit extends Cubit<Locale?> {
  LocaleCubit(this._settings) : super(null);

  final SettingsRepository _settings;

  Future<void> load() async {
    final s = await _settings.get();
    if (!isClosed) emit(localeFromCode(s.localeCode));
  }

  /// Switches at once (the whole UI, including text direction, follows on the
  /// next frame), then persists.
  Future<void> setLocale(Locale locale) async {
    final supported = localeFromCode(locale.languageCode);
    if (supported == null) return;
    emit(supported);
    final current = await _settings.get();
    await _settings.save(current.copyWith(localeCode: supported.languageCode));
  }
}
