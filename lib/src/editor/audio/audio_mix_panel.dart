import 'package:flutter/material.dart';

import '../../core/story_scope.dart';
import '../widgets/editor_icon_button.dart';
import '../widgets/editor_panel.dart';

/// Original-audio volume (with mute) and music volume.
class AudioMixPanel extends StatelessWidget {
  /// Creates the panel.
  const AudioMixPanel({
    required this.showOriginal,
    required this.showMusic,
    required this.originalVolume,
    required this.musicVolume,
    required this.onChangeStart,
    required this.onOriginalChanged,
    required this.onMusicChanged,
    required this.onChangeEnd,
    required this.onToggleMute,
    super.key,
  });

  /// Whether the video has audio of its own.
  final bool showOriginal;

  /// Whether music is selected.
  final bool showMusic;

  /// Current original volume.
  final double originalVolume;

  /// Current music volume.
  final double musicVolume;

  /// A slider drag starts.
  final VoidCallback onChangeStart;

  /// Original volume changed.
  final ValueChanged<double> onOriginalChanged;

  /// Music volume changed.
  final ValueChanged<double> onMusicChanged;

  /// A slider drag ends.
  final VoidCallback onChangeEnd;

  /// Mute tapped.
  final VoidCallback onToggleMute;

  @override
  Widget build(BuildContext context) {
    final strings = StoryScope.of(context).strings.editor;
    final muted = originalVolume == 0;
    return EditorPanel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showOriginal)
            _VolumeRow(
              key: const ValueKey('originalVolume'),
              label: strings.originalAudio,
              value: originalVolume,
              onChangeStart: onChangeStart,
              onChanged: onOriginalChanged,
              onChangeEnd: onChangeEnd,
              trailing: EditorIconButton(
                icon: muted ? Icons.volume_off : Icons.volume_up,
                label: muted ? strings.unmute : strings.mute,
                toggled: muted,
                onPressed: onToggleMute,
              ),
            ),
          if (showMusic)
            _VolumeRow(
              key: const ValueKey('musicVolume'),
              label: strings.musicVolume,
              value: musicVolume,
              onChangeStart: onChangeStart,
              onChanged: onMusicChanged,
              onChangeEnd: onChangeEnd,
              trailing: const SizedBox.square(dimension: EditorIconButton.size),
            ),
        ],
      ),
    );
  }
}

class _VolumeRow extends StatelessWidget {
  const _VolumeRow({
    required this.label,
    required this.value,
    required this.onChangeStart,
    required this.onChanged,
    required this.onChangeEnd,
    required this.trailing,
    super.key,
  });

  final String label;
  final double value;
  final VoidCallback onChangeStart;
  final ValueChanged<double> onChanged;
  final VoidCallback onChangeEnd;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final theme = StoryScope.of(context).theme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: ExcludeSemantics(
                  child: Text(label, style: theme.labelStyle),
                ),
              ),
              SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: theme.accent,
                  inactiveTrackColor: theme.outline,
                  thumbColor: theme.accent,
                  overlayColor: theme.accent.withValues(alpha: 0.2),
                ),
                child: Semantics(
                  label: label,
                  child: Slider(
                    value: value.clamp(0, 1),
                    semanticFormatterCallback: (v) => '${(v * 100).round()}%',
                    onChangeStart: (_) => onChangeStart(),
                    onChanged: onChanged,
                    onChangeEnd: (_) => onChangeEnd(),
                  ),
                ),
              ),
            ],
          ),
        ),
        trailing,
      ],
    );
  }
}
