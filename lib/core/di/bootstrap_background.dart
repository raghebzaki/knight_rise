import 'dart:async';
import 'dart:ui' show DartPluginRegistrant;

import 'package:knight_rise/core/di/injection.dart';
import 'package:knight_rise/features/notifications/domain/notification_gateway.dart';

Future<void>? _bootstrap;

/// Prepares a headless (non-UI) isolate: plugin registrant, DI (which
/// pre-resolves the timezone and opens the shared Drift database) and the
/// notification gateway. Idempotent per isolate: concurrent and repeated calls
/// share one initialisation.
///
/// Called by Task 4 (notification action handler) and Task 5 (WorkManager
/// callback dispatcher) before they resolve use cases from `getIt`.
///
/// `WidgetsFlutterBinding.ensureInitialized()` is deliberately not used here.
Future<void> bootstrapBackground() {
  final existing = _bootstrap;
  if (existing != null) return existing;
  final future = _run();
  _bootstrap = future;
  // Clear the cache on failure so the next wake-up retries.
  unawaited(
    future.onError<Object>((_, _) {
      if (identical(_bootstrap, future)) _bootstrap = null;
    }),
  );
  return future;
}

Future<void> _run() async {
  DartPluginRegistrant.ensureInitialized();
  await configureDependencies();
  await getIt<NotificationGateway>().initialize(onForegroundAction: (_) {});
}
