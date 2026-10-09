import 'dart:ui' show Locale;

/// Languages the app ships, English first: when the device language is not
/// one of these, Flutter falls back to the first entry. (The generated
/// `AppLocalizations.supportedLocales` is alphabetical, so Arabic would win.)
const List<Locale> kSupportedLocales = [Locale('en'), Locale('ar')];

/// The supported locale stored as [code]; null (follow the device) for null
/// or an unknown code.
Locale? localeFromCode(String? code) {
  for (final locale in kSupportedLocales) {
    if (locale.languageCode == code) return locale;
  }
  return null;
}
