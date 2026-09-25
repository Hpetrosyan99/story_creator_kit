import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../api/theme/story_creator_theme.dart';

/// A short message shown by [PreviewToast].
@immutable
class PreviewToastMessage {
  /// Creates a message.
  const PreviewToastMessage(this.text, {this.isError = false});

  /// The text.
  final String text;

  /// Whether it reports a failure.
  final bool isError;
}

/// Shows toasts for a few seconds.
class PreviewToastController extends ValueNotifier<PreviewToastMessage?> {
  /// Creates a controller with nothing shown.
  PreviewToastController({this.duration = const Duration(seconds: 2)})
    : super(null);

  /// How long a toast stays.
  final Duration duration;

  Timer? _timer;

  /// Shows [text], replacing any current toast.
  void show(String text, {bool isError = false}) {
    _timer?.cancel();
    value = PreviewToastMessage(text, isError: isError);
    _timer = Timer(duration, () => value = null);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// A toast that does not depend on a `ScaffoldMessenger` (hosts may not have
/// one above the story creator). Announced as a live region.
class PreviewToast extends StatelessWidget {
  /// Creates the toast.
  const PreviewToast({
    required this.controller,
    required this.theme,
    super.key,
  });

  /// What to show.
  final PreviewToastController controller;

  /// Colours and text styles.
  final StoryCreatorTheme theme;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<PreviewToastMessage?>(
        valueListenable: controller,
        builder: (context, message, _) => AnimatedOpacity(
          opacity: message == null ? 0 : 1,
          duration: const Duration(milliseconds: 200),
          child: message == null
              ? const SizedBox.shrink()
              : Center(
                  child: Semantics(
                    liveRegion: true,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: message.isError ? theme.error : theme.surface,
                        borderRadius: BorderRadius.circular(theme.chipRadius),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        child: Text(
                          message.text,
                          style: theme.bodyStyle,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      );
}
