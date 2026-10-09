import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/core/di/injection.dart';
import 'package:knight_rise/core/feedback/haptics.dart';
import 'package:knight_rise/core/shortcuts/app_shortcuts.dart';
import 'package:knight_rise/core/theme/knight_palette.dart';
import 'package:knight_rise/core/theme/knight_theme.dart';
import 'package:knight_rise/features/cycle/presentation/bloc/cycle_bloc.dart';
import 'package:knight_rise/features/notifications/presentation/notification_permission_cubit.dart';
import 'package:knight_rise/features/quest_log/domain/usecases/history_usecases.dart';
import 'package:knight_rise/features/scheduler/presentation/schedule_sync_service.dart';
import 'package:knight_rise/features/settings/presentation/locale_cubit.dart';
import 'package:knight_rise/features/settings/presentation/theme_cubit.dart';
import 'package:knight_rise/features/splash/presentation/animated_splash.dart';
import 'package:knight_rise/features/splash/presentation/splash_gate.dart';
import 'package:knight_rise/l10n/app_locales.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';

class KnightRiseApp extends StatefulWidget {
  const KnightRiseApp({super.key, this.router, this.showSplash = true});

  /// Injected in tests; the DI singleton otherwise.
  final GoRouter? router;

  /// False when a notification tap launched the app (see
  /// [SplashOverlay.playsOnLaunch]).
  final bool showSplash;

  @override
  State<KnightRiseApp> createState() => _KnightRiseAppState();
}

class _KnightRiseAppState extends State<KnightRiseApp> {
  late final GoRouter _router = widget.router ?? getIt<GoRouter>();
  late final ScheduleSyncService _sync = getIt<ScheduleSyncService>();
  late final NotificationPermissionCubit _permission = getIt<NotificationPermissionCubit>();
  late final LocaleCubit _locale = getIt<LocaleCubit>();
  late final AppLifecycleListener _lifecycle;
  StreamSubscription<void>? _tzSub;

  /// Animated splash over the first route, once per cold start. Held here,
  /// above the [_scope] key, so a timezone change never replays it.
  late bool _showSplash = widget.showSplash;
  late final SplashGate _splashGate = getIt<SplashGate>();

  /// Changing this recreates the BlocProviders (and so CycleBloc / ThemeCubit)
  /// after a timezone change, so they pick up the new `tz.Location`.
  Key _scope = UniqueKey();

  /// Keeps the shortcut host (and so the single native macOS menu bar) alive across a scope reset: a second
  /// PlatformMenuBar mounting before the first is disposed would clear the menu.
  final GlobalKey _shortcutsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _splashGate.addListener(_onSplashGate);
    if (_splashGate.dismissed) _showSplash = false;
    _lifecycle = AppLifecycleListener(
      onResume: () {
        unawaited(_sync.onResume());
        unawaited(_permission.check());
        unawaited(_maintainHistory());
      },
    );
    unawaited(_permission.check());
    _tzSub = _sync.timezoneChanged.listen((_) {
      if (mounted) setState(() => _scope = UniqueKey());
    });
    unawaited(_sync.start());
    unawaited(_maintainHistory());
  }

  /// Finalizes past days and prunes old data (launch and resume; the hourly
  /// background task does the same). Never throws.
  Future<void> _maintainHistory() async {
    try {
      await getIt<MaintainHistory>()();
    } on Object catch (e, st) {
      debugPrint('History maintenance failed: $e\n$st');
    }
  }

  /// A deep link (toast tap) asked for the splash to give way.
  void _onSplashGate() {
    if (_splashGate.dismissed && _showSplash && mounted) setState(() => _showSplash = false);
  }

  @override
  void dispose() {
    _splashGate.removeListener(_onSplashGate);
    _lifecycle.dispose();
    unawaited(_tzSub?.cancel());
    unawaited(_permission.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<Clock>.value(value: getIt<Clock>()),
        RepositoryProvider<Haptics>.value(value: getIt<Haptics>()),
      ],
      child: MultiBlocProvider(
        key: _scope,
        providers: [
          // Value-provided: owned by this state so it survives scope resets
          // (a dismissed card must stay dismissed after a timezone change).
          BlocProvider.value(value: _permission),
          // A process-wide singleton, loaded in main() before the first frame.
          BlocProvider.value(value: _locale),
          BlocProvider(create: (_) => getIt<ThemeCubit>()),
          BlocProvider(create: (_) => getIt<CycleBloc>()..add(const CycleStarted())),
        ],
        child: BlocBuilder<ThemeCubit, ThemeVariant>(
          builder: (context, variant) {
            final palette = KnightPalette.of(variant);
            // Null follows the device language.
            final locale = context.watch<LocaleCubit>().state;
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: KnightTheme.overlayStyle(palette),
              child: MaterialApp.router(
                onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
                debugShowCheckedModeBanner: false,
                theme: KnightTheme.build(palette),
                themeMode: ThemeMode.dark,
                darkTheme: KnightTheme.build(palette),
                locale: locale,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: kSupportedLocales,
                routerConfig: _router,
                // Inside Localizations: the resolved language is known here,
                // and RTL follows from GlobalWidgetsLocalizations.
                builder: (context, child) {
                  final app = AppShortcuts(
                    key: _shortcutsKey,
                    router: _router,
                    child: SplashOverlay(
                      show: _showSplash,
                      onFinished: () => setState(() => _showSplash = false),
                      child: child ?? const SizedBox.shrink(),
                    ),
                  );
                  return KnightTheme.isJoinedScript(Localizations.localeOf(context))
                      ? Theme(data: KnightTheme.build(palette, joinedScript: true), child: app)
                      : app;
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
