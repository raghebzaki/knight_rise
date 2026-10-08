import 'package:go_router/go_router.dart';
import 'package:injectable/injectable.dart';
import 'package:knight_rise/core/router/app_router.dart';
import 'package:knight_rise/features/onboarding/presentation/onboarding_gate.dart';

/// The app's single [GoRouter], shared by the widget tree and by code that
/// navigates from outside it (notification taps in `main.dart`).
@module
abstract class RouterModule {
  @lazySingleton
  GoRouter router(OnboardingGate gate) => buildRouter(gate: gate);
}
