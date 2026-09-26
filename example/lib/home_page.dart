import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:story_creator_kit/services.dart';
import 'package:story_creator_kit/story_creator_kit.dart';

import 'result_page.dart';
import 'sample_config.dart';
import 'sample_music_provider.dart';
import 'simulated_capture_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _settings = ExampleSettings();
  final _music = SampleMusicProvider();
  final List<String> _log = [];
  StoryOutcome? _lastOutcome;
  bool _simulator = false;

  @override
  void initState() {
    super.initState();
    detectIosSimulator().then((value) {
      if (mounted) {
        setState(() => _simulator = value);
      }
    });
  }

  Future<void> _create() async {
    final config = _settings.toConfig(
      musicProvider: _music,
      onEvent: (event) {
        debugPrint('story event: $event');
        setState(() => _log.insert(0, event.toString()));
      },
    );
    // The iOS Simulator has no camera; swap in a simulated one.
    StoryServices? services;
    if (_simulator) {
      final platform = StoryServices.platform(config);
      services = platform.copyWith(
        createCapture: SimulatedCaptureService.new,
        permissions: SimulatedCameraPermissions(platform.permissions),
      );
    }
    final outcome = await StoryCreator.open(
      context,
      config: config,
      services: services,
    );
    if (!mounted) {
      return;
    }
    setState(() => _lastOutcome = outcome);
    if (outcome case StoryCompleted(:final result)) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => ResultPage(result: result)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final outcome = _lastOutcome;
    return Scaffold(
      appBar: AppBar(title: const Text('Story Creator Kit')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(
            key: const ValueKey('create-story'),
            onPressed: _create,
            icon: const Icon(Icons.add_a_photo_outlined),
            label: const Text('Create story'),
          ),
          if (_simulator)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Running in the iOS Simulator: the camera is simulated.',
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(height: 24),
          Text('Options', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<GalleryMode>(
            segments: const [
              ButtonSegment(value: GalleryMode.inApp, label: Text('In-app')),
              ButtonSegment(
                value: GalleryMode.systemPicker,
                label: Text('System picker'),
              ),
              ButtonSegment(value: GalleryMode.disabled, label: Text('None')),
            ],
            selected: {_settings.galleryMode},
            onSelectionChanged: (v) =>
                setState(() => _settings.galleryMode = v.first),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Max video length'),
            trailing: DropdownButton<int>(
              value: _settings.maxVideoSeconds,
              items: const [
                DropdownMenuItem(value: 15, child: Text('15 s')),
                DropdownMenuItem(value: 30, child: Text('30 s')),
                DropdownMenuItem(value: 60, child: Text('60 s')),
              ],
              onChanged: (v) =>
                  setState(() => _settings.maxVideoSeconds = v ?? 60),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Save to gallery'),
            trailing: DropdownButton<SaveToGalleryMode>(
              value: _settings.saveMode,
              items: const [
                DropdownMenuItem(
                  value: SaveToGalleryMode.never,
                  child: Text('Never'),
                ),
                DropdownMenuItem(
                  value: SaveToGalleryMode.button,
                  child: Text('Button'),
                ),
                DropdownMenuItem(
                  value: SaveToGalleryMode.always,
                  child: Text('Always'),
                ),
              ],
              onChanged: (v) => setState(
                () => _settings.saveMode = v ?? SaveToGalleryMode.button,
              ),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Preview before returning'),
            value: _settings.showPreview,
            onChanged: (v) => setState(() => _settings.showPreview = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Music catalog'),
            value: _settings.music,
            onChanged: (v) => setState(() => _settings.music = v),
          ),
          SwitchListTile(
            key: const ValueKey('liquid-glass'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Liquid glass buttons'),
            value: _settings.liquidGlass,
            onChanged: (v) => setState(() => _settings.liquidGlass = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Custom strings'),
            value: _settings.customStrings,
            onChanged: (v) => setState(() => _settings.customStrings = v),
          ),
          const Divider(height: 32),
          Text('Last outcome', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(key: const ValueKey('last-outcome'), switch (outcome) {
            null => 'None yet',
            StoryCompleted(:final result) =>
              'Completed: ${result.type.name}, ${result.width}×${result.height}, '
                  '${(result.fileSizeBytes / 1024).toStringAsFixed(0)} KB',
            StoryCancelled(:final reason) => 'Cancelled (${reason.name})',
            StoryFailed(:final error) => 'Failed: ${error.code.name}',
          }),
          if (kDebugMode && _log.isNotEmpty) ...[
            const Divider(height: 32),
            Text('Events', style: Theme.of(context).textTheme.titleMedium),
            for (final line in _log.take(20))
              Text(line, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}
