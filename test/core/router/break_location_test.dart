import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/router/break_location.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';

void main() {
  group('breakLocation', () {
    test('single type', () {
      expect(breakLocation({RoutineType.eyeRest}), '/break?types=eyeRest');
    });

    test('multiple types are written in RoutineType order', () {
      expect(
        breakLocation({RoutineType.eyeRest, RoutineType.hydration, RoutineType.stretch}),
        '/break?types=hydration,stretch,eyeRest',
      );
    });

    test('empty set goes to the dashboard', () {
      expect(breakLocation({}), '/');
    });

    test('round-trips through parseBreakTypes', () {
      for (final types in [
        {RoutineType.hydration},
        {RoutineType.stretch, RoutineType.eyeRest},
        RoutineType.values.toSet(),
      ]) {
        final query = Uri.parse(breakLocation(types)).queryParameters['types'];
        expect(parseBreakTypes(query), sortedBreakTypes(types));
      }
    });
  });

  group('parseBreakTypes', () {
    test('null, empty and all-invalid are empty', () {
      expect(parseBreakTypes(null), isEmpty);
      expect(parseBreakTypes(''), isEmpty);
      expect(parseBreakTypes('nope,,'), isEmpty);
    });

    test('ignores unknown names, de-duplicates and sorts', () {
      expect(parseBreakTypes('eyeRest,bogus,hydration,eyeRest'), [RoutineType.hydration, RoutineType.eyeRest]);
    });

    test('names are case-sensitive', () {
      expect(parseBreakTypes('Hydration'), isEmpty);
    });
  });

  group('OpenBreakDeduper', () {
    late DateTime clock;
    late OpenBreakDeduper deduper;

    setUp(() {
      clock = DateTime(2026, 1, 1, 9);
      deduper = OpenBreakDeduper(now: () => clock);
    });

    test('first open is allowed', () {
      expect(deduper.shouldOpen(1), isTrue);
    });

    test('same id within 10 s is ignored', () {
      expect(deduper.shouldOpen(1), isTrue);
      clock = clock.add(const Duration(seconds: 9));
      expect(deduper.shouldOpen(1), isFalse);
    });

    test('same id after 10 s is allowed', () {
      expect(deduper.shouldOpen(1), isTrue);
      clock = clock.add(const Duration(seconds: 10));
      expect(deduper.shouldOpen(1), isTrue);
    });

    test('different id is allowed', () {
      expect(deduper.shouldOpen(1), isTrue);
      clock = clock.add(const Duration(seconds: 1));
      expect(deduper.shouldOpen(2), isTrue);
    });
  });
}
