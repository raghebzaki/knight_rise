import 'package:knight_rise/features/device_health/domain/oem_guide.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';

/// Localized title and numbered steps for an [OemMaker].
({String title, List<String> steps}) oemGuideText(AppLocalizations l, OemMaker maker) => switch (maker) {
  OemMaker.xiaomi => (
    title: l.healthOemXiaomiTitle,
    steps: [l.healthOemXiaomiStep1, l.healthOemXiaomiStep2, l.healthOemXiaomiStep3],
  ),
  OemMaker.samsung => (
    title: l.healthOemSamsungTitle,
    steps: [l.healthOemSamsungStep1, l.healthOemSamsungStep2, l.healthOemSamsungStep3],
  ),
  OemMaker.huawei => (
    title: l.healthOemHuaweiTitle,
    steps: [l.healthOemHuaweiStep1, l.healthOemHuaweiStep2, l.healthOemHuaweiStep3],
  ),
  OemMaker.oppo => (
    title: l.healthOemOppoTitle,
    steps: [l.healthOemOppoStep1, l.healthOemOppoStep2, l.healthOemOppoStep3],
  ),
  OemMaker.vivo => (
    title: l.healthOemVivoTitle,
    steps: [l.healthOemVivoStep1, l.healthOemVivoStep2, l.healthOemVivoStep3],
  ),
  OemMaker.generic => (
    title: l.healthOemGenericTitle,
    steps: [l.healthOemGenericStep1, l.healthOemGenericStep2, l.healthOemGenericStep3],
  ),
};
