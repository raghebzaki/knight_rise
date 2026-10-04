import 'package:go_router/go_router.dart';
import 'package:knight_rise/core/config/flavor.dart';
import 'package:knight_rise/core/router/break_location.dart';
import 'package:knight_rise/features/cycle/presentation/pages/break_page.dart';
import 'package:knight_rise/features/cycle/presentation/pages/home_page.dart';
import 'package:knight_rise/features/diagnostics/presentation/diagnostics_page.dart';
import 'package:knight_rise/features/gallery/presentation/gallery_page.dart';

/// Routes. `/break?types=hydration,eyeRest` is the notification-tap target;
/// invalid or empty `types` redirect to `/`.
GoRouter buildRouter() => GoRouter(
  routes: [
    GoRoute(path: '/', builder: (_, _) => const HomePage()),
    GoRoute(
      path: '/break',
      redirect: (_, state) => parseBreakTypes(state.uri.queryParameters['types']).isEmpty ? '/' : null,
      builder: (_, state) => BreakPage(types: parseBreakTypes(state.uri.queryParameters['types'])),
    ),
    if (Flavor.current.isDev) ...[
      GoRoute(path: '/gallery', builder: (_, _) => const GalleryPage()),
      GoRoute(path: '/diagnostics', builder: (_, _) => const DiagnosticsPage()),
    ],
  ],
);
