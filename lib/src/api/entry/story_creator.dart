import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/session_files.dart';
import '../../core/story_scope.dart';
import '../../flow/story_flow_controller.dart';
import '../../flow/story_flow_view.dart';
import '../../render/painters/story_paint_resources.dart';
import '../../render/painters/story_paint_resources_loader.dart';
import '../../services/story_services.dart';
import '../config/story_creator_config.dart';
import '../errors/story_exception.dart';
import '../events/story_event.dart';
import '../result/story_result.dart';
import '../theme/story_creator_theme.dart';

/// Entry point of the story creator.
abstract final class StoryCreator {
  /// Opens the story creator full screen and completes when it closes.
  ///
  /// Returns [StoryCompleted] with the exported file, [StoryCancelled] when
  /// the user leaves, or [StoryFailed] when the flow cannot run at all.
  /// [services] replaces the platform services (tests, simulators).
  static Future<StoryOutcome> open(
    BuildContext context, {
    StoryCreatorConfig config = const StoryCreatorConfig(),
    StoryServices? services,
  }) async {
    final outcome = await Navigator.of(context).push<StoryOutcome>(
      PageRouteBuilder<StoryOutcome>(
        fullscreenDialog: true,
        pageBuilder: (context, _, _) => StoryCreatorPage(
          config: config,
          services: services,
          onFinished: (outcome) => Navigator.of(context).pop(outcome),
        ),
        transitionsBuilder: (context, animation, _, child) => SlideTransition(
          position: Tween(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(animation),
          child: child,
        ),
      ),
    );
    return outcome ?? const StoryCancelled(StoryCancelReason.dismissed);
  }
}

/// The story creator as a widget, for hosts that manage their own routes.
///
/// Push it full screen and pop when [onFinished] fires. [onFinished] is
/// called exactly once.
class StoryCreatorPage extends StatefulWidget {
  /// Creates the page.
  const StoryCreatorPage({
    required this.onFinished,
    this.config = const StoryCreatorConfig(),
    this.services,
    super.key,
  });

  /// Host configuration.
  final StoryCreatorConfig config;

  /// Replacement services; platform services when `null`.
  final StoryServices? services;

  /// Receives the outcome once.
  final ValueChanged<StoryOutcome> onFinished;

  @override
  State<StoryCreatorPage> createState() => _StoryCreatorPageState();
}

class _StoryCreatorPageState extends State<StoryCreatorPage> {
  late final StoryServices _services =
      widget.services ?? StoryServices.platform(widget.config);
  late final StoryPaintResources _resources = createStoryPaintResources(
    widget.config.editor,
  );
  SessionFiles? _session;
  StoryFlowController? _flow;
  bool _reported = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      final session = await SessionFiles.create();
      if (!mounted) {
        await session.delete();
        return;
      }
      _report(const StoryEvent(StoryEventType.opened));
      setState(() {
        _session = session;
        _flow = StoryFlowController(
          config: widget.config,
          services: _services,
          session: session,
          report: _report,
        );
      });
    } on Object catch (e, s) {
      _finish(
        StoryFailed(
          StoryException(
            StoryErrorCode.unknown,
            'Could not create the session directory.',
            e,
            s,
          ),
        ),
      );
    }
  }

  void _report(StoryEvent event) {
    try {
      widget.config.onEvent?.call(event);
    } on Object catch (e, s) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: e,
          stack: s,
          library: 'story_creator_kit',
        ),
      );
    }
  }

  void _finish(StoryOutcome outcome) {
    if (_reported) {
      return;
    }
    _reported = true;
    widget.onFinished(outcome);
  }

  @override
  void dispose() {
    _flow?.dispose();
    unawaited(_services.gallery.dispose());
    unawaited(_session?.delete());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.config.theme;
    final session = _session;
    final flow = _flow;
    return Theme(
      data: _materialTheme(theme),
      child: DefaultTextStyle(
        style: theme.bodyStyle,
        child: IconTheme(
          data: IconThemeData(color: theme.onSurface, size: 26),
          child: BackdropGroup(
            child: Material(
              color: theme.background,
              child: session == null || flow == null
                  ? const SizedBox.expand()
                  : StoryScope(
                      config: widget.config,
                      services: _services,
                      session: session,
                      resources: _resources,
                      child: StoryFlowView(
                        controller: flow,
                        onFinished: _finish,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  static ThemeData _materialTheme(StoryCreatorTheme t) => ThemeData(
    brightness: Brightness.dark,
    fontFamily: t.fontFamily,
    colorScheme: ColorScheme.dark(
      primary: t.accent,
      onPrimary: t.onAccent,
      secondary: t.accent,
      onSecondary: t.onAccent,
      surface: t.surface,
      onSurface: t.onSurface,
      error: t.error,
      outline: t.outline,
    ),
    scaffoldBackgroundColor: t.background,
    sliderTheme: SliderThemeData(
      activeTrackColor: t.accent,
      thumbColor: t.onSurface,
      inactiveTrackColor: t.outline,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: t.accent,
      selectionHandleColor: t.accent,
    ),
  );
}
