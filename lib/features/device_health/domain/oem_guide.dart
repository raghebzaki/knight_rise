import 'package:equatable/equatable.dart';

/// OEM families with their own battery / auto-start screens.
enum OemMaker { xiaomi, samsung, huawei, oppo, vivo, generic }

/// A step-by-step guide to keep reminders alive on [maker]'s devices. The
/// localized steps live in the presentation layer (ARB).
class OemGuide extends Equatable {
  const OemGuide(this.maker, {this.settingsComponents = const []});

  final OemMaker maker;

  /// Android `package/class` components to try, in order, for "Open settings".
  final List<String> settingsComponents;

  @override
  List<Object?> get props => [maker, settingsComponents];
}

const _xiaomi = ['xiaomi', 'redmi', 'poco'];
const _samsung = ['samsung'];
const _huawei = ['huawei', 'honor'];
const _oppo = ['oppo', 'realme', 'oneplus'];
const _vivo = ['vivo', 'iqoo'];
const _otherAggressive = ['meizu', 'asus'];

bool _matches(String lower, List<String> brands) => brands.any(lower.contains);

/// Whether [manufacturer] (manufacturer and/or brand, any case) is known for
/// killing background work aggressively.
bool isAggressiveOem(String manufacturer) {
  final m = manufacturer.toLowerCase();
  return [_xiaomi, _samsung, _huawei, _oppo, _vivo, _otherAggressive].any((b) => _matches(m, b));
}

/// The guide for [manufacturer] (manufacturer and/or brand, any case).
OemGuide guideFor(String manufacturer) {
  final m = manufacturer.toLowerCase();
  if (_matches(m, _xiaomi)) {
    return const OemGuide(
      OemMaker.xiaomi,
      settingsComponents: ['com.miui.securitycenter/com.miui.permcenter.autostart.AutoStartManagementActivity'],
    );
  }
  if (_matches(m, _samsung)) {
    return const OemGuide(
      OemMaker.samsung,
      settingsComponents: ['com.samsung.android.lool/com.samsung.android.sm.ui.battery.BatteryActivity'],
    );
  }
  if (_matches(m, _huawei)) {
    return const OemGuide(
      OemMaker.huawei,
      settingsComponents: [
        'com.huawei.systemmanager/com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity',
      ],
    );
  }
  if (_matches(m, _oppo)) {
    return const OemGuide(
      OemMaker.oppo,
      settingsComponents: ['com.coloros.safecenter/com.coloros.safecenter.permission.startup.StartupAppListActivity'],
    );
  }
  if (_matches(m, _vivo)) {
    return const OemGuide(
      OemMaker.vivo,
      settingsComponents: ['com.vivo.permissionmanager/com.vivo.permissionmanager.activity.BgStartUpManagerActivity'],
    );
  }
  return const OemGuide(OemMaker.generic);
}
