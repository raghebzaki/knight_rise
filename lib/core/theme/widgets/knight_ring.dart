import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:knight_rise/core/theme/knight_dimens.dart';
import 'package:knight_rise/core/theme/knight_tokens.dart';

/// One ring's value and color.
@immutable
class RingSegment {
  const RingSegment({required this.progress, required this.color, this.label});

  /// 0..1; values above 1 are drawn as full.
  final double progress;
  final Color color;

  /// Screen-reader label, e.g. "Hydration 4 of 8".
  final String? label;
}

/// Concentric progress rings (outer → inner), drawn with a CustomPainter.
///
/// Spec: 10 px stroke, 6 px gap, round caps, sweep gradient from the ring
/// color to `secondary`, 600 ms ease-out, soft glow at 100 %.
class KnightRing extends StatelessWidget {
  const KnightRing({
    required this.segments,
    super.key,
    this.size = 220,
    this.strokeWidth = 10,
    this.gap = 6,
    this.center,
  });

  final List<RingSegment> segments;
  final double size;
  final double strokeWidth;
  final double gap;
  final Widget? center;

  @override
  Widget build(BuildContext context) {
    final tokens = context.knight;
    final secondary = Theme.of(context).colorScheme.secondary;
    final label = segments.map((s) => s.label).whereType<String>().join(', ');

    return Semantics(
      label: label.isEmpty ? null : label,
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            for (var i = 0; i < segments.length; i++)
              TweenAnimationBuilder<double>(
                tween: Tween(end: segments[i].progress.clamp(0, 1).toDouble()),
                duration: KnightMotion.ring,
                curve: Curves.easeOutCubic,
                builder: (context, value, _) => CustomPaint(
                  size: Size.square(size),
                  painter: _RingPainter(
                    progress: value,
                    color: segments[i].color,
                    gradientEnd: secondary,
                    track: tokens.ringTrack,
                    strokeWidth: strokeWidth,
                    inset: i * (strokeWidth + gap),
                  ),
                ),
              ),
            if (center != null) ExcludeSemantics(child: center),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.color,
    required this.gradientEnd,
    required this.track,
    required this.strokeWidth,
    required this.inset,
  });

  final double progress;
  final Color color;
  final Color gradientEnd;
  final Color track;
  final double strokeWidth;
  final double inset;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.shortestSide / 2 - strokeWidth / 2 - inset;
    if (radius <= 0) return;
    final c = size.center(Offset.zero);
    final rect = Rect.fromCircle(center: c, radius: radius);

    canvas.drawCircle(
      c,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = track,
    );
    if (progress <= 0) return;

    final sweep = 2 * math.pi * progress;
    const start = -math.pi / 2;
    final shader = SweepGradient(
      endAngle: math.max(sweep, 0.01),
      colors: [color, Color.lerp(color, gradientEnd, 0.6)!],
      transform: const GradientRotation(start),
    ).createShader(rect);

    if (progress >= 1) {
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..color = color.withValues(alpha: 0.45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }

    canvas.drawArc(
      rect,
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..shader = shader,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.track != track ||
      old.gradientEnd != gradientEnd ||
      old.strokeWidth != strokeWidth ||
      old.inset != inset;
}
