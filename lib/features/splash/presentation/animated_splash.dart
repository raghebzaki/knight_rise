import 'dart:async';

import 'package:flutter/material.dart';
import 'package:knight_rise/core/theme/knight_palette.dart';
import 'package:knight_rise/core/theme/knight_theme.dart';
import 'package:knight_rise/features/notifications/domain/reminder_action.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';

/// Total time on screen before [AnimatedSplash.onFinished] fires.
const Duration kSplashDuration = Duration(milliseconds: 1900);

/// How long the splash takes to fade away over the first route.
const Duration kSplashFadeOut = Duration(milliseconds: 350);

/// Shield mark and its crest-glow layer: same frame, the glow padded by
/// [_glowPad] px on every side (see `assets/branding/README.md`).
const String kSplashMarkAsset = 'assets/branding/splash_mark.png';
const String kSplashGlowAsset = 'assets/branding/splash_crest_glow.png';
const double _markWidthPx = 526;
const double _glowPad = 60;

/// The launch moment, played once per cold start over the first route.
///
/// Timeline (1.9 s): the shield scales and fades in (0–700 ms, easeOutBack /
/// easeOutCubic); the lightning crest's cyan glow pulses (450–1500 ms);
/// "KNIGHT RISE" (650–1050 ms) and the tagline (850–1250 ms) fade and slide
/// up; then [onFinished]. With reduced motion everything is shown at once and
/// [onFinished] fires after the first frame.
class AnimatedSplash extends StatefulWidget {
  const AnimatedSplash({required this.onFinished, super.key, this.duration = kSplashDuration});

  final VoidCallback onFinished;
  final Duration duration;

  @override
  State<AnimatedSplash> createState() => _AnimatedSplashState();
}

class _AnimatedSplashState extends State<AnimatedSplash> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration);
  bool _finished = false;

  /// Progress over [start]..[end] ms of the timeline, curved.
  Animation<double> _phase(int start, int end, Curve curve) {
    final total = widget.duration.inMilliseconds;
    return CurvedAnimation(
      parent: _c,
      curve: Interval(start / total, end / total, curve: curve),
    );
  }

  late final Animation<double> _markScale = Tween<double>(
    begin: 0.82,
    end: 1,
  ).animate(_phase(0, 700, Curves.easeOutBack));
  late final Animation<double> _markOpacity = _phase(0, 500, Curves.easeOutCubic);
  late final Animation<double> _glow = TweenSequence<double>([
    TweenSequenceItem(tween: ConstantTween(0), weight: 450),
    TweenSequenceItem(tween: Tween<double>(begin: 0, end: 0.95).chain(CurveTween(curve: Curves.easeOut)), weight: 400),
    TweenSequenceItem(
      tween: Tween<double>(begin: 0.95, end: 0.45).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 650,
    ),
    TweenSequenceItem(tween: ConstantTween(0.45), weight: 400),
  ]).animate(_c);
  late final Animation<double> _title = _phase(650, 1050, Curves.easeOutCubic);
  late final Animation<double> _tagline = _phase(850, 1250, Curves.easeOutCubic);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.isAnimating || _c.isCompleted || _finished) return;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _c.value = 1;
      WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
    } else {
      unawaited(_c.forward().whenComplete(_finish));
    }
  }

  void _finish() {
    if (_finished || !mounted) return;
    _finished = true;
    widget.onFinished();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final width = MediaQuery.sizeOf(context).width;
    final markWidth = (width * 0.42).clamp(120.0, 200.0);
    final scale = markWidth / _markWidthPx;

    Widget rise(Animation<double> t, Key key, Widget child) => AnimatedBuilder(
      animation: t,
      builder: (_, child) => Opacity(
        key: key,
        opacity: t.value.clamp(0, 1),
        child: Transform.translate(offset: Offset(0, 16 * (1 - t.value)), child: child),
      ),
      child: child,
    );

    return Semantics(
      label: l.appTitle,
      container: true,
      child: ExcludeSemantics(
        child: ColoredBox(
          color: KnightPalette.splashBackground,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _c,
                  builder: (_, _) => Opacity(
                    key: const Key('splash-mark'),
                    opacity: _markOpacity.value.clamp(0, 1),
                    child: Transform.scale(
                      scale: _markScale.value,
                      child: SizedBox(
                        width: markWidth,
                        height: markWidth * 618 / _markWidthPx,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            // Crest glow behind the shield, pulsing.
                            Positioned(
                              left: -_glowPad * scale,
                              top: -_glowPad * scale,
                              right: -_glowPad * scale,
                              bottom: -_glowPad * scale,
                              child: Opacity(
                                key: const Key('splash-glow'),
                                opacity: _glow.value.clamp(0, 1),
                                child: Image.asset(kSplashGlowAsset, fit: BoxFit.fill),
                              ),
                            ),
                            Positioned.fill(child: Image.asset(kSplashMarkAsset, fit: BoxFit.contain)),
                            // A lighter pass over the shield, so the bolt itself brightens.
                            Positioned(
                              left: -_glowPad * scale,
                              top: -_glowPad * scale,
                              right: -_glowPad * scale,
                              bottom: -_glowPad * scale,
                              child: Opacity(
                                opacity: (_glow.value * 0.55).clamp(0, 1),
                                child: Image.asset(kSplashGlowAsset, fit: BoxFit.fill),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                rise(
                  _title,
                  const Key('splash-title'),
                  ShaderMask(
                    blendMode: BlendMode.srcIn,
                    shaderCallback: (bounds) => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: KnightPalette.splashWordmark,
                    ).createShader(bounds),
                    child: Text(
                      l.appTitle.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: text.headlineMedium?.copyWith(fontSize: 34, letterSpacing: 3, height: 1.1),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                rise(
                  _tagline,
                  const Key('splash-tagline'),
                  Text(
                    l.tagline.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: text.labelLarge?.copyWith(
                      letterSpacing: KnightTheme.tracking(context, 1.6),
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Puts [AnimatedSplash] over the app's first route while [show] is true,
/// then fades it out (instantly with reduced motion). The first route builds
/// underneath meanwhile, so the hand-off is seamless and deep links,
/// redirects and the back stack are unaffected.
class SplashOverlay extends StatelessWidget {
  const SplashOverlay({required this.show, required this.onFinished, required this.child, super.key});

  final bool show;
  final VoidCallback onFinished;
  final Widget child;

  /// Whether the splash plays on a cold start that [launch] (the notification
  /// tap that opened the app, if any) caused. A notification launch is an
  /// instant-action context: the user came for that reminder, so the app
  /// opens straight to it.
  static bool playsOnLaunch(ReminderAction? launch) => launch == null;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        AnimatedSwitcher(
          duration: reduced ? Duration.zero : kSplashFadeOut,
          child: show
              ? AnimatedSplash(key: const Key('splash'), onFinished: onFinished)
              : const SizedBox.shrink(key: Key('splash-done')),
        ),
      ],
    );
  }
}
