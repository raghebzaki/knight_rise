import 'dart:ui' show Locale;

import 'package:knight_rise/l10n/app_locales.dart';

/// Language of a desktop toast built now: the stored app language if it is
/// supported, else the first device language the app ships, else English.
Locale resolveNotificationLocale(String? settingsCode, List<Locale> deviceLocales) {
  final stored = localeFromCode(settingsCode);
  if (stored != null) return stored;
  for (final device in deviceLocales) {
    final match = localeFromCode(device.languageCode);
    if (match != null) return match;
  }
  return kSupportedLocales.first;
}
