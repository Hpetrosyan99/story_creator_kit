import 'package:flutter/material.dart';

import '../../api/assets/story_sticker.dart';
import '../../core/story_scope.dart';
import '../widgets/editor_icon_button.dart';
import '../widgets/editor_panel.dart';

/// Sticker and emoji picker: a tab of host stickers (hidden when there are
/// none) and a tab of emoji.
class StickerPickerPanel extends StatefulWidget {
  /// Creates the panel.
  const StickerPickerPanel({
    required this.stickers,
    required this.emojis,
    required this.onSticker,
    required this.onEmoji,
    required this.onClose,
    super.key,
  });

  /// Host stickers.
  final List<StorySticker> stickers;

  /// Emoji.
  final List<String> emojis;

  /// A sticker was chosen.
  final ValueChanged<StorySticker> onSticker;

  /// An emoji was chosen.
  final ValueChanged<String> onEmoji;

  /// Close tapped.
  final VoidCallback onClose;

  @override
  State<StickerPickerPanel> createState() => _StickerPickerPanelState();
}

class _StickerPickerPanelState extends State<StickerPickerPanel> {
  late bool _showStickers = widget.stickers.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final strings = scope.strings;
    final hasStickers = widget.stickers.isNotEmpty;
    final showStickers = hasStickers && _showStickers;
    return EditorPanel(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (hasStickers)
                EditorTextButton(
                  label: strings.editor.stickers,
                  selected: showStickers,
                  onPressed: () => setState(() => _showStickers = true),
                ),
              if (hasStickers) const SizedBox(width: 8),
              EditorTextButton(
                label: strings.editor.emoji,
                selected: !showStickers,
                onPressed: () => setState(() => _showStickers = false),
              ),
              const Spacer(),
              EditorIconButton(
                icon: Icons.close,
                label: strings.common.close,
                onPressed: widget.onClose,
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 240,
            child: showStickers
                ? GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 88,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                        ),
                    itemCount: widget.stickers.length,
                    itemBuilder: (context, index) => _StickerTile(
                      sticker: widget.stickers[index],
                      onTap: widget.onSticker,
                    ),
                  )
                : GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 56,
                        ),
                    itemCount: widget.emojis.length,
                    itemBuilder: (context, index) => _EmojiTile(
                      emoji: widget.emojis[index],
                      onTap: widget.onEmoji,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _StickerTile extends StatelessWidget {
  const _StickerTile({required this.sticker, required this.onTap});

  final StorySticker sticker;
  final ValueChanged<StorySticker> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = StoryScope.of(context).theme;
    return Semantics(
      button: true,
      label: sticker.label,
      excludeSemantics: true,
      onTap: () => onTap(sticker),
      child: Material(
        color: theme.surfaceVariant,
        borderRadius: BorderRadius.circular(theme.cornerRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onTap(sticker),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Image(
              image: sticker.image,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => Icon(
                Icons.broken_image_outlined,
                color: theme.onSurfaceMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmojiTile extends StatelessWidget {
  const _EmojiTile({required this.emoji, required this.onTap});

  final String emoji;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = StoryScope.of(context).theme;
    return Semantics(
      button: true,
      label: emoji,
      excludeSemantics: true,
      onTap: () => onTap(emoji),
      child: InkWell(
        onTap: () => onTap(emoji),
        customBorder: const CircleBorder(),
        child: Center(
          child: Text(
            emoji,
            style: theme.titleStyle.copyWith(fontSize: 30),
            textScaler: TextScaler.noScaling,
          ),
        ),
      ),
    );
  }
}
