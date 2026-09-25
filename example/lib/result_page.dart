import 'dart:io';

import 'package:flutter/material.dart';
import 'package:story_creator_kit/story_creator_kit.dart';
import 'package:video_player/video_player.dart';

/// Shows the exported story and its metadata, as a host app would receive
/// them.
class ResultPage extends StatelessWidget {
  const ResultPage({required this.result, super.key});

  final StoryResult result;

  @override
  Widget build(BuildContext context) {
    final m = result.metadata;
    final rows = <(String, String)>[
      ('File', result.path.split('/').last),
      ('Type', '${result.type.name} (${result.mimeType})'),
      ('Size', '${result.width}×${result.height}'),
      ('Bytes', '${result.fileSizeBytes}'),
      if (result.duration != null)
        ('Duration', '${result.duration!.inMilliseconds} ms'),
      ('Saved to gallery', '${result.savedToGallery}'),
      ('Source', '${m.source.name} ${m.sourceType.name}'),
      if (m.trimStart != null)
        (
          'Trim',
          '${m.trimStart!.inMilliseconds}–${m.trimEnd?.inMilliseconds} ms',
        ),
      ('Original audio', m.originalAudioVolume.toStringAsFixed(2)),
      if (m.music != null)
        (
          'Music',
          '${m.music!.title} @${m.music!.start.inMilliseconds} ms, '
              '${m.music!.duration.inMilliseconds} ms, vol ${m.music!.volume}',
        ),
      ('Filter', m.filterId ?? 'none'),
      ('Texts', m.texts.map((t) => '"${t.text}" (${t.fontId})').join(', ')),
      ('Stickers', m.stickerIds.join(', ')),
      ('Emoji', m.emojis.join(' ')),
      ('Drawing', '${m.hasDrawing}'),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Your story')),
      body: ListView(
        key: const ValueKey('result-page'),
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                width: 240,
                height: 240 * 16 / 9,
                child: result.type == StoryMediaType.photo
                    ? Image.file(File(result.path), fit: BoxFit.cover)
                    : _VideoResult(path: result.path),
              ),
            ),
          ),
          const SizedBox(height: 16),
          for (final (label, value) in rows)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(label),
              subtitle: Text(value.isEmpty ? '—' : value),
            ),
        ],
      ),
    );
  }
}

class _VideoResult extends StatefulWidget {
  const _VideoResult({required this.path});

  final String path;

  @override
  State<_VideoResult> createState() => _VideoResultState();
}

class _VideoResultState extends State<_VideoResult> {
  late final VideoPlayerController _controller = VideoPlayerController.file(
    File(widget.path),
  );

  @override
  void initState() {
    super.initState();
    _controller.initialize().then((_) async {
      await _controller.setLooping(true);
      await _controller.play();
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _controller.value.isInitialized
      ? FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _controller.value.size.width,
            height: _controller.value.size.height,
            child: VideoPlayer(_controller),
          ),
        )
      : const ColoredBox(color: Colors.black);
}
