import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:knight_rise/core/database/app_database.dart';
import 'package:knight_rise/core/di/app_environment.dart';

/// Ends the process; a seam so tests do not exit.
abstract interface class AppExit {
  Future<void> exit();
}

/// Closes the database best effort, then exits with code 0.
@desktopEnv
@LazySingleton(as: AppExit)
class ProcessAppExit implements AppExit {
  const ProcessAppExit(this._db);

  final AppDatabase _db;

  @override
  Future<void> exit() async {
    try {
      await _db.close();
    } on Object catch (e) {
      debugPrint('[shell] closing the database failed: $e');
    }
    io.exit(0);
  }
}
