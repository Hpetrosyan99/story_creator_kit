import 'package:flutter/material.dart';

import '../../camera/widgets/permission_prompt.dart';
import '../../core/story_scope.dart';
import '../gallery_keys.dart';

/// Shown with limited photo access; "Manage" changes the selection.
class LimitedAccessBanner extends StatelessWidget {
  /// Creates the banner.
  const LimitedAccessBanner({required this.onManage, super.key});

  /// Opens the system selection UI.
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final theme = scope.theme;
    final strings = scope.strings.camera;
    return Padding(
      key: GalleryKeys.limitedBanner,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.surface,
          border: Border.all(color: theme.outline),
          borderRadius: BorderRadius.circular(theme.cornerRadius),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
          child: Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 20,
                color: theme.onSurfaceMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  strings.limitedAccessMessage,
                  style: theme.bodyStyle.copyWith(
                    color: theme.onSurfaceSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              StoryActionButton(
                key: GalleryKeys.manage,
                label: strings.manageSelection,
                onPressed: onManage,
                primary: false,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
