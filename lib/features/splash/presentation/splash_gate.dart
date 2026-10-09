import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';

/// Lets a deep link (a notification tap while the splash plays) dismiss the
/// splash so the page it opens is not hidden behind it. One-way: once
/// [dismissed], it stays so for the process.
@lazySingleton
class SplashGate extends ChangeNotifier {
  bool _dismissed = false;

  bool get dismissed => _dismissed;

  void dismiss() {
    if (_dismissed) return;
    _dismissed = true;
    notifyListeners();
  }
}
