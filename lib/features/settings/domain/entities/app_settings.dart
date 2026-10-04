import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:knight_rise/core/theme/knight_palette.dart';

part 'app_settings.freezed.dart';

@freezed
abstract class AppSettings with _$AppSettings {
  const factory AppSettings({
    @Default(ThemeVariant.midnight) ThemeVariant themeVariant,

    /// Opt-in exact alarms on Android (Device Health screen, Milestone 3).
    @Default(false) bool precisionTiming,

    /// Water logged per tap and per notification "Done".
    @Default(250) int waterPerTapMl,
  }) = _AppSettings;
}
