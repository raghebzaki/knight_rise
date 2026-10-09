import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/time/timezone_loader.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(tzdata.initializeTimeZones);

  group('resolveLocation', () {
    test('resolves every IANA id Windows (ICU / CLDR windowsZones) can report', () {
      final ids = [
        for (final line in File('test/core/time/fixtures/cldr_windows_zone_ids.txt').readAsLinesSync())
          if (line.isNotEmpty && !line.startsWith('#')) line,
      ];
      expect(ids, hasLength(greaterThan(400)));
      final unresolved = [
        for (final id in ids)
          if (resolveLocation(id, utcOffset: Duration.zero).name != id) id,
      ];
      expect(unresolved, isEmpty);
    });

    test('resolves legacy alias spellings older ICU builds return', () {
      for (final id in [
        'Asia/Calcutta',
        'Asia/Katmandu',
        'Asia/Rangoon',
        'Asia/Saigon',
        'America/Buenos_Aires',
        'America/Indianapolis',
        'America/Godthab',
        'Europe/Kiev',
        'Pacific/Truk',
        'Atlantic/Faeroe',
      ]) {
        expect(resolveLocation(id, utcOffset: Duration.zero).name, id);
      }
      final kolkata = tz.TZDateTime(resolveLocation('Asia/Calcutta', utcOffset: Duration.zero), 2026, 3, 15);
      expect(kolkata.timeZoneOffset, const Duration(hours: 5, minutes: 30));
    });

    test('Etc/Unknown (no ICU mapping) falls back to the fixed offset zone', () {
      final cairo = resolveLocation('Etc/Unknown', utcOffset: const Duration(hours: 3));
      expect(cairo.name, 'Etc/GMT-3');
      expect(tz.TZDateTime(cairo, 2026, 7, 10).timeZoneOffset, const Duration(hours: 3));

      final eastern = resolveLocation('Etc/Unknown', utcOffset: const Duration(hours: -5));
      expect(eastern.name, 'Etc/GMT+5');
      expect(tz.TZDateTime(eastern, 2026, 2, 10).timeZoneOffset, const Duration(hours: -5));

      expect(resolveLocation('Etc/Unknown', utcOffset: const Duration(hours: 14)).name, 'Etc/GMT-14');
    });

    test('no id, zero or fractional offsets fall back to UTC', () {
      expect(resolveLocation(null, utcOffset: Duration.zero), tz.UTC);
      expect(resolveLocation(null, utcOffset: const Duration(hours: 2)).name, 'Etc/GMT-2');
      expect(resolveLocation('Etc/Unknown', utcOffset: const Duration(hours: 5, minutes: 30)), tz.UTC);
      expect(resolveLocation('Etc/Unknown', utcOffset: const Duration(hours: 20)), tz.UTC);
    });
  });
}
