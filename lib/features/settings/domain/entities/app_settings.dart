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

    /// IANA zone id the schedule was last planned in; null before first check.
    String? timezoneId,

    /// True once the onboarding flow has finished (or for upgraded installs).
    @Default(false) bool onboardingCompleted,

    /// Send a single "Shield down" summary reminder when a Shield ends.
    @Default(true) bool shieldRecoverOnExit,

    /// A work day counts toward the streak when every enabled routine reaches
    /// this percentage of its daily target.
    @Default(70) int streakThresholdPercent,

    /// Last run of the 90-day retention job (it runs at most once a day).
    DateTime? lastRetentionRunAt,

    /// Haptic feedback on actions.
    @Default(true) bool hapticsEnabled,

    /// Local date of the last rank-up celebration (date-only).
    DateTime? rankCelebratedOn,

    /// Chosen app language code (`en` | `ar`); null follows the device
    /// language (English when it is not supported).
    String? localeCode,
  }) = _AppSettings;
}
