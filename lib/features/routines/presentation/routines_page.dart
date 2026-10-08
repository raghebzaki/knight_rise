import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:knight_rise/core/di/injection.dart';
import 'package:knight_rise/core/theme/knight_dimens.dart';
import 'package:knight_rise/core/theme/knight_tokens.dart';
import 'package:knight_rise/core/theme/widgets/knight_card.dart';
import 'package:knight_rise/features/cycle/presentation/widgets/routine_presentation.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/routines/presentation/routines_cubit.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';

/// The three routines with inline on/off switches; tap a row to edit it.
class RoutinesPage extends StatelessWidget {
  const RoutinesPage({super.key, this.cubit});

  final RoutinesCubit? cubit;

  @override
  Widget build(BuildContext context) {
    final provided = cubit;
    return provided != null
        ? BlocProvider.value(value: provided, child: const _RoutinesView())
        : BlocProvider(create: (_) => getIt<RoutinesCubit>(), child: const _RoutinesView());
  }
}

class _RoutinesView extends StatelessWidget {
  const _RoutinesView();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.routineEditorListTitle)),
      body: BlocBuilder<RoutinesCubit, List<Routine>?>(
        builder: (context, routines) {
          if (routines == null) return const Center(child: CircularProgressIndicator());
          return ListView(
            padding: const EdgeInsetsDirectional.fromSTEB(
              KnightSpacing.lg,
              KnightSpacing.sm,
              KnightSpacing.lg,
              KnightSpacing.xxl,
            ),
            children: [
              for (final r in routines)
                Padding(
                  padding: const EdgeInsets.only(bottom: KnightSpacing.md),
                  child: KnightCard(
                    padding: const EdgeInsets.symmetric(vertical: KnightSpacing.xs),
                    child: ListTile(
                      key: Key('routine-${r.type.name}'),
                      leading: Icon(r.type.icon, color: context.knight.routineColor(r.type)),
                      title: Text(r.type.label(l)),
                      subtitle: Text(
                        r.enabled ? l.routineEditorSummary(r.intervalMinutes, r.dailyTarget) : l.routineEditorOff,
                      ),
                      onTap: () => context.push('/settings/routines/${r.type.name}'),
                      trailing: Switch(
                        key: Key('routineSwitch-${r.type.name}'),
                        value: r.enabled,
                        onChanged: (v) => context.read<RoutinesCubit>().setEnabled(r.type, enabled: v),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
