import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/core/di/injection.dart';
import 'package:knight_rise/core/router/app_router.dart';
import 'package:knight_rise/core/theme/knight_palette.dart';
import 'package:knight_rise/core/theme/knight_theme.dart';
import 'package:knight_rise/features/cycle/presentation/bloc/cycle_bloc.dart';
import 'package:knight_rise/features/scheduler/presentation/schedule_sync_service.dart';
import 'package:knight_rise/features/settings/presentation/theme_cubit.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';

class KnightRiseApp extends StatefulWidget {
  const KnightRiseApp({super.key, this.router});

  /// Injected in tests; built from [buildRouter] otherwise.
  final GoRouter? router;

  @override
  State<KnightRiseApp> createState() => _KnightRiseAppState();
}

class _KnightRiseAppState extends State<KnightRiseApp> {
  late final GoRouter _router = widget.router ?? buildRouter();
  late final ScheduleSyncService _sync = getIt<ScheduleSyncService>();
  late final AppLifecycleListener _lifecycle;
  StreamSubscription<void>? _tzSub;

  /// Changing this recreates the BlocProviders (and so CycleBloc / ThemeCubit)
  /// after a timezone change, so they pick up the new `tz.Location`.
  Key _scope = UniqueKey();

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(_sync.onResume()));
    _tzSub = _sync.timezoneChanged.listen((_) {
      if (mounted) setState(() => _scope = UniqueKey());
    });
    unawaited(_sync.start());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    unawaited(_tzSub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider<Clock>.value(
      value: getIt<Clock>(),
      child: MultiBlocProvider(
        key: _scope,
        providers: [
          BlocProvider(create: (_) => getIt<ThemeCubit>()),
          BlocProvider(create: (_) => getIt<CycleBloc>()..add(const CycleStarted())),
        ],
        child: BlocBuilder<ThemeCubit, ThemeVariant>(
          builder: (context, variant) {
            final palette = KnightPalette.of(variant);
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: KnightTheme.overlayStyle(palette),
              child: MaterialApp.router(
                onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
                debugShowCheckedModeBanner: false,
                theme: KnightTheme.build(palette),
                themeMode: ThemeMode.dark,
                darkTheme: KnightTheme.build(palette),
                localizationsDelegates: const [
                  AppLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                supportedLocales: AppLocalizations.supportedLocales,
                routerConfig: _router,
              ),
            );
          },
        ),
      ),
    );
  }
}
