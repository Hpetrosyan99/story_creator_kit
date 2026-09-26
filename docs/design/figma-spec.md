# Figma spec — Add Story (Mabrook1, node 40000491:99941)

> **Not implemented by decision:** the Post / Story / Reel / Podcast / Live tab bar under the card (removed at the user's request, 2026-09-25). The card extends to the bottom inset instead.

Source: https://www.figma.com/design/JBUZttR3CV0OLy4YLFGZvW/Mabrook1?node-id=40000491-99941
Reference renders (375×812, the visual target): `docs/design/figma/01_camera.png` … `07_recording.png`.
Frame: 375×812; status bar 47; home indicator 34.

## Tokens (already in `StoryCreatorTheme` defaults)

| Design token | Value | Theme field |
|---|---|---|
| Grey/950 (page) | #141414 | `background` |
| Background/Surface | #1F1F21 | `surface` |
| Background/Surface Raised | #2D2D30 | `surfaceVariant` |
| Border/Default | #525257 | `outline` |
| Accent (bg/border/text/icon) | #CF5835 | `accent` |
| Text/Primary, Icon/Primary | #FFFFFF | `onSurface` |
| Text/Secondary | #C2C2C2 | `onSurfaceSecondary` |
| Text/Muted | #737373 | `onSurfaceMuted` |
| Status/Error (recording shutter) | #D92D20 | `error` |
| Nav button bg | rgba(31,31,33,0.4) | `controlBackground` |
| Pill bg (mode bar, toggle, flip) | rgba(20,20,20,0.5) | `pillBackground` |
| Radius lg (canvas card, thumbs) | 16 | `cornerRadius` |
| Radius md (track artwork) | 12 | — |
| Radius xl (music chip) | 20 | — |
| Body/M | 16/22 400 | `bodyLargeStyle` |
| Body/M Emphasis | 16/22 600 | `titleStyle` |
| Body/S | 14/20 400 | `bodyStyle` |
| Body/S Emphasis | 14/20 600 | `bodyEmphasisStyle` |
| Label/S | 12/16 400 | `labelStyle` (muted: `captionStyle`) |

Font: Onest (host-supplied; the example app bundles it).

## Shared UI (in `lib/src/ui/`, already implemented — use them)

- `StoryIcon(StoryIcons.x, color:)` — the design's SVGs at their exact size/bleed with the design drop shadow. Icons: close, check, chevronLeft, chevronRight, flash, text, layouts, music, flip, camera, search, chipClose, bookmark, bookmarkFilled, moreVertical, shutterPhoto, shutterRecording. Tint white icons with `theme.onSurface`, accent ones with `theme.accent`; never tint shutters.
- `StorySurface(fill:, radius:, padding:, child:)` — translucent background; renders as liquid glass when `theme.isLiquidGlassEnabled`. **Every translucent control on the canvas must use it** (nav buttons, pills, flip button, music chip).
- `StoryNavButton(icon:, label:, onPressed:, style: translucent|subtle|accent)` — 44 px circle, 20 px icon, 48 px tap target.
- `StoryModeBar()` / `StoryStage(card:, onModeSelected:)` — page frame: rounded card from the top safe area, 20 px gap, mode bar (only if `config.modeBar` set), bottom inset. Camera, editor and segment selector use `StoryStage`.
- `StoryPillToggle<T>(options:, selected:, onChanged:)` — "Video | Photo" pill.

## Screens (coordinates in the 375×812 frame; card = x0–374, y47–708, radius 16)

### Camera (01_camera, 07_recording)
- Card: live preview, cover. A horizontal scrim gradient on the preview: left→right rgba(0,0,0,0)→rgba(0,0,0,0.4).
- Nav row inside card top: padding 16/12 → close `StoryNavButton` (translucent) at left. Right side of the nav row: the confirm slot is empty on camera (opacity 0).
- Video/Photo `StoryPillToggle` at top-right: pill right edge ≈16 from card edge, top 17 in card, px12 py6, gap 10.
- Left CTA column: x=16, vertically centred in the card, icons 20 px, gap 13: flash (Lightning), text (Edit/Text), layouts (SquaresFour).
- Bottom row, top 585 in card (16 from card bottom): gallery thumbnail 60×60 radius 16 with 1 px white border (left 16); shutter 60×60 centred (`shutterPhoto`; `shutterRecording` while recording); lens switch: pill h44, px10 py6, `pillBackground`, icon `flip` 24 px, right-aligned 16 from card edge, vertically centred on the 60 px row (top 593).
- Mode bar under the card.

### Editor (02_editor, 06_editor_music)
- Card: the story canvas (existing).
- Nav row: close (translucent) left, confirm `StoryNavButton(style: accent)` right.
- Right CTA column: x = card right − 16 − 20, vertically centred, icons 20 px, gap 13: music, text, layouts (= stickers & emoji). Design keeps further items hidden behind a "More" chevron (Arrow/Chevron_Down, 20 px): put the remaining tools there (draw, filters, trim, audio, adjust, undo/redo).
- Bottom-left: gallery thumbnail 60×60 radius 16, 1 px white border, left 16, bottom 16 of card.
- Bottom-right when music is selected: music chip — `surface` bg, padding 10, radius 20: artwork 40 radius 12, gap 8, title Body/S white, subtitle Label/S muted "Artist | mm:ss". Right edge 16 from card edge, bottom aligned with the thumbnail row (top 591).
- Mode bar under the card.

### Gallery (03_gallery)
- Page bg #141414, no card. Nav bar 48 high below status bar: back chevronLeft 24 px at x16.
- "Recent" Body/S Emphasis white with text shadow (0,2,8, rgba(0,0,0,0.24)) + chevronRight 20 px, gap 2, at x16, 12 px above the grid.
- Grid: width = screen − 8 (4 px side margins), 3 columns, 2 px gaps both ways, tile aspect 1080:1920 (tall), no radius.
- First tile: camera tile, `surfaceVariant` bg, `camera` icon 24 px centred.
- Each media tile: radio circle 20 px, 1.5 px white border, at top-right inset ~4 px, drop shadow (0,0,2.5, rgba(0,0,0,0.2)).

### Add music (04_music)
- Nav bar: back chevronLeft at x16.
- Search field: 343 wide (16 margins), h52, 1 px `outline` border, radius 40, pl16 pr12, gap 8: `search` icon 24 (accent) + placeholder Body/M `onSurfaceMuted`.
- Chips 16 below: gap 8, h28, radius pill, Label/S white. Selected: bg accent at 10% alpha, 1 px accent border, pl12 pr6, then `chipClose` 16 px (accent) with gap 10. Unselected: `surfaceVariant` bg, 1 px `outline` border, px12.
- List 30 below chips. Row: px16 py8, artwork 40 radius 12, gap 8, title Body/S white, subtitle Label/S muted "Artist | mm:ss"; right: bookmark 24 (outline white / filled accent).
- Playing row: `surface` bg; title in accent preceded by an equaliser (3 bars 1×12, 1×12, 1×6, accent, radius 16, gap 2) with gap 4.
- Leaderboard style row: rank number Body/S secondary (w15) before the artwork, gap 8; `moreVertical` 24 instead of bookmark.
- No "+" button: tapping a row selects the track (opens the segment selector).

### Segment selector (05_segment)
- Stage like the editor; canvas dimmed by rgba(0,0,0,0.4).
- Nav: close (translucent) left, confirm `StoryNavButton(style: subtle)` right.
- Waveform strip across the full card width near the bottom (centre ≈ 30 px above card bottom): bars alternating 3 px / 2 px wide, gap 5, heights 5–27 px (from peaks), radius 40, white.
- Segment window: pill 120×41 (width = segment length on the strip), 1 px accent border, clips an accent fill from the left edge to the playback position; bars drawn on top in white.
- Mode bar under the card. No title text.
