import 'package:go_router/go_router.dart';
import 'package:knight_rise/core/config/flavor.dart';
import 'package:knight_rise/core/router/break_location.dart';
import 'package:knight_rise/features/cycle/presentation/pages/break_page.dart';
import 'package:knight_rise/features/cycle/presentation/pages/home_page.dart';
import 'package:knight_rise/features/device_health/presentation/device_health_page.dart';
import 'package:knight_rise/features/diagnostics/presentation/diagnostics_page.dart';
import 'package:knight_rise/features/gallery/presentation/gallery_page.dart';
import 'package:knight_rise/features/onboarding/presentation/onboarding_gate.dart';
import 'package:knight_rise/features/onboarding/presentation/onboarding_page.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/routines/presentation/routine_editor_page.dart';
import 'package:knight_rise/features/routines/presentation/routines_page.dart';
import 'package:knight_rise/features/settings/presentation/settings_page.dart';
import 'package:knight_rise/features/work_hours/presentation/work_hours_page.dart';

/// Routes. `/settings`, `/settings/work-hours`, `/settings/routines` and
/// `/settings/routines/:type` (invalid type redirects to the list).
/// `/break?types=hydration,eyeRest` is the notification-tap target;
/// invalid or empty `types` redirect to `/`.
/// `/onboarding` is the first-run flow: with a [gate] that is not completed
/// every location redirects there, and once completed it redirects to `/`.
/// Without a [gate] (tests) no onboarding redirect applies.
GoRouter buildRouter({String initialLocation = '/', OnboardingGate? gate}) => GoRouter(
  initialLocation: initialLocation,
  refreshListenable: gate,
  redirect: gate == null ? null : (_, state) => onboardingRedirect(completed: gate.completed, path: state.uri.path),
  routes: [
    GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingPage()),
    GoRoute(path: '/', builder: (_, _) => const HomePage()),
    GoRoute(
      path: '/break',
      redirect: (_, state) => parseBreakTypes(state.uri.queryParameters['types']).isEmpty ? '/' : null,
      builder: (_, state) => BreakPage(types: parseBreakTypes(state.uri.queryParameters['types'])),
    ),
    GoRoute(
      path: '/settings',
      builder: (_, _) => const SettingsPage(),
      routes: [
        GoRoute(path: 'work-hours', builder: (_, _) => const WorkHoursPage()),
        GoRoute(path: 'device-health', builder: (_, _) => const DeviceHealthPage()),
        GoRoute(
          path: 'routines',
          builder: (_, _) => const RoutinesPage(),
          routes: [
            GoRoute(
              path: ':type',
              redirect: (_, state) =>
                  routineTypeFromParam(state.pathParameters['type']) == null ? '/settings/routines' : null,
              builder: (_, state) => RoutineEditorPage(type: routineTypeFromParam(state.pathParameters['type'])!),
            ),
          ],
        ),
      ],
    ),
    if (Flavor.current.isDev) ...[
      GoRoute(path: '/gallery', builder: (_, _) => const GalleryPage()),
      GoRoute(path: '/diagnostics', builder: (_, _) => const DiagnosticsPage()),
    ],
  ],
);

/// The [RoutineType] named [name] (`hydration`, `stretch`, `eyeRest`), or null.
RoutineType? routineTypeFromParam(String? name) => RoutineType.values.asNameMap()[name];

/// The onboarding redirect: not completed sends everything but `/onboarding`
/// there; completed sends `/onboarding` to `/`; otherwise null.
String? onboardingRedirect({required bool completed, required String path}) {
  final onOnboarding = path == '/onboarding';
  if (!completed && !onOnboarding) return '/onboarding';
  if (completed && onOnboarding) return '/';
  return null;
}
