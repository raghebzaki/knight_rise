import 'package:go_router/go_router.dart';
import 'package:knight_rise/core/config/flavor.dart';
import 'package:knight_rise/features/cycle/presentation/pages/home_page.dart';
import 'package:knight_rise/features/gallery/presentation/gallery_page.dart';

/// Routes. Milestone 2 adds `/break/:routine` deep links from notifications.
GoRouter buildRouter() => GoRouter(
  routes: [
    GoRoute(path: '/', builder: (_, _) => const HomePage()),
    if (Flavor.current.isDev) GoRoute(path: '/gallery', builder: (_, _) => const GalleryPage()),
  ],
);
