import 'package:flutter/material.dart';
import 'package:knight_rise/core/theme/knight_dimens.dart';
import 'package:knight_rise/core/theme/knight_tokens.dart';
import 'package:knight_rise/core/theme/widgets/knight_card.dart';
import 'package:knight_rise/core/theme/widgets/knight_ring.dart';

/// Dev-only showcase of tokens and components (Milestone 1 deliverable).
class GalleryPage extends StatefulWidget {
  const GalleryPage({super.key});

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  double _progress = 0.65;
  bool _switch = true;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final k = context.knight;

    Widget section(String title, List<Widget> children) => Padding(
      padding: const EdgeInsets.only(bottom: KnightSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(), style: text.titleLarge),
          const SizedBox(height: KnightSpacing.md),
          ...children,
        ],
      ),
    );

    final swatches = <String, Color>{
      'primary': scheme.primary,
      'secondary': scheme.secondary,
      'background': Theme.of(context).scaffoldBackgroundColor,
      'surface': scheme.surface,
      'surfaceHigh': scheme.surfaceContainerHigh,
      'outline': scheme.outline,
      'outlineStrong': k.outlineStrong,
      'onSurface': scheme.onSurface,
      'onSurfaceVariant': scheme.onSurfaceVariant,
      'textMuted': k.textMuted,
      'success': k.success,
      'warning': k.warning,
      'error': scheme.error,
      'hydration': k.hydration,
      'stretch': k.stretch,
      'eyeRest': k.eyeRest,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('GALLERY')),
      body: ListView(
        padding: const EdgeInsets.all(KnightSpacing.lg),
        children: [
          section('Colors', [
            Wrap(
              spacing: KnightSpacing.sm,
              runSpacing: KnightSpacing.sm,
              children: [
                for (final MapEntry(:key, :value) in swatches.entries)
                  SizedBox(
                    width: 96,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 40,
                          decoration: BoxDecoration(
                            color: value,
                            borderRadius: BorderRadius.circular(KnightRadius.sm),
                            border: Border.all(color: scheme.outline),
                          ),
                        ),
                        Text(key, style: text.labelSmall),
                      ],
                    ),
                  ),
              ],
            ),
          ]),
          section('Type', [
            Text('12:45', style: text.displayLarge),
            Text('SCREEN TITLE', style: text.headlineMedium),
            Text('Card title', style: text.titleLarge),
            Text('Title medium', style: text.titleMedium),
            Text('Body large — stay active, stay focused.', style: text.bodyLarge),
            Text('Body medium — secondary steel text.', style: text.bodyMedium),
            Text('LABEL LARGE', style: text.labelLarge),
            Text('label small', style: text.labelSmall),
          ]),
          section('Buttons', [
            Wrap(
              spacing: KnightSpacing.sm,
              runSpacing: KnightSpacing.sm,
              children: [
                FilledButton(onPressed: () {}, child: const Text('Claim break')),
                OutlinedButton(onPressed: () {}, child: const Text('Secondary')),
                TextButton(onPressed: () {}, child: const Text('Snooze 10m')),
                const FilledButton(onPressed: null, child: Text('Disabled')),
              ],
            ),
            const SizedBox(height: KnightSpacing.md),
            Row(
              children: [
                Switch(value: _switch, onChanged: (v) => setState(() => _switch = v)),
                Expanded(
                  child: Slider(value: _progress, onChanged: (v) => setState(() => _progress = v)),
                ),
              ],
            ),
          ]),
          section('Cards', [
            const KnightCard(child: Text('Default card · steel border')),
            const SizedBox(height: KnightSpacing.md),
            const KnightCard(glow: true, child: Text('Active card · cyan glow')),
            const SizedBox(height: KnightSpacing.md),
            const KnightCard(chamfered: true, child: Text('Hero card · chamfered armor plate')),
          ]),
          section('Rings', [
            Center(
              child: KnightRing(
                segments: [
                  RingSegment(progress: _progress, color: k.hydration),
                  RingSegment(progress: _progress * 0.7, color: k.stretch),
                  RingSegment(progress: (_progress * 1.6).clamp(0, 1), color: k.eyeRest),
                ],
                center: Text('${(_progress * 100).round()}%', style: text.displayMedium),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
