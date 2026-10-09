import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/database/app_database.dart';

void main() {
  test('mobile keeps the Documents default and the shared isolate server', () {
    // Moving this would orphan every installed user's data.
    expect(mobileDatabaseOptions.databasePath, isNull);
    expect(mobileDatabaseOptions.databaseDirectory, isNull);
    expect(mobileDatabaseOptions.shareAcrossIsolates, isTrue);
  });

  group('desktop', () {
    late Directory root;

    setUp(() => root = Directory.systemTemp.createTempSync('knight_db_'));
    tearDown(() => root.deleteSync(recursive: true));

    test('stores the database in the support directory, creating it', () async {
      final support = Directory('${root.path}/Application Support/com.ragheb.knightRise');
      final options = desktopDatabaseOptions(() async => support);

      expect(options.databasePath, isNull);
      expect(options.shareAcrossIsolates, isFalse, reason: 'desktop has no background isolates');
      final resolved = await options.databaseDirectory!();
      expect((resolved as Directory).path, support.path);
      expect(support.existsSync(), isTrue);
    });
  });
}
