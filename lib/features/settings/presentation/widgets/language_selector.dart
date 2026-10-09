import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:knight_rise/features/settings/presentation/locale_cubit.dart';
import 'package:knight_rise/l10n/app_locales.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';

/// English / العربية toggle. Shows the language in use (the device language
/// until one is chosen) and switches through the [LocaleCubit] above it.
/// Each name is written in its own script, so it can be found from either.
class LanguageSelector extends StatelessWidget {
  const LanguageSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final current = localeFromCode(Localizations.localeOf(context).languageCode) ?? kSupportedLocales.first;
    return SegmentedButton<Locale>(
      key: const Key('languageSelector'),
      showSelectedIcon: false,
      segments: [
        for (final locale in kSupportedLocales)
          ButtonSegment(
            value: locale,
            label: Text(switch (locale.languageCode) {
              'ar' => l.languageNameAr,
              _ => l.languageNameEn,
            }),
          ),
      ],
      selected: {current},
      onSelectionChanged: (s) => unawaited(context.read<LocaleCubit>().setLocale(s.first)),
    );
  }
}
