import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/features/notifications/data/notification_locale.dart';

void main() {
  test('the stored app language wins over the device', () {
    expect(resolveNotificationLocale('ar', const [Locale('en', 'US')]), const Locale('ar'));
    expect(resolveNotificationLocale('en', const [Locale('ar', 'EG')]), const Locale('en'));
  });

  test('follow-device (null or unknown code) uses the first supported device language', () {
    expect(resolveNotificationLocale(null, const [Locale('ar', 'EG')]), const Locale('ar'));
    expect(resolveNotificationLocale('zz', const [Locale('fr'), Locale('ar')]), const Locale('ar'));
  });

  test('falls back to English', () {
    expect(resolveNotificationLocale(null, const [Locale('fr')]), const Locale('en'));
    expect(resolveNotificationLocale(null, const []), const Locale('en'));
  });
}
