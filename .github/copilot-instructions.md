<!-- GENERATED FILE — DO NOT EDIT. Source: AGENTS.md. Regenerate: ./tool/sync_agents.sh -->

# AGENTS.md

Instructions for any coding agent working in this repo (Claude Code, Codex, Cursor, Copilot, Gemini…). This file is the **single source** — `CLAUDE.md`, `GEMINI.md`, `.github/copilot-instructions.md` and `.cursor/rules/000-agents.mdc` are generated from it by `./tool/sync_agents.sh`.

## Project

`story_creator_kit` — a publishable Flutter plugin (pub.dev) that provides an Instagram-style story creation flow: camera → capture or pick from gallery → editor (text, drawing, stickers, filters, music, trim) → native export → preview → result returned to the host app. Android (API 26+) and iOS (16+).

- The approved plan: [`docs/plans/story-creator-kit.md`](../docs/plans/story-creator-kit.md). Change it when reality changes; do not silently diverge.
- Research behind the dependency choices: [`docs/research/`](../docs/research/).

## Layout

```
lib/story_creator_kit.dart     public barrel — the ONLY public surface
lib/src/api/                   public config, result, music, theme, strings, errors, events
lib/src/model/                 StoryDocument and its parts (immutable), undo/redo history
lib/src/core/                  scope, canvas maths, session files, logging
lib/src/services/              interfaces + implementations (capture, gallery, permissions, audio, video, export)
lib/src/flow/                  StoryFlowController: camera → editor → export → preview
lib/src/camera/  gallery/      capture UI, gallery grid
lib/src/editor/                editor UI and tools
lib/src/render/painters/       painters SHARED by the editor view and the export rasterizer
lib/src/render/                overlay rasterizer, frame composer
lib/src/music/  export/  preview/
lib/src/native/                Pigeon-generated Dart (do not edit)
pigeons/                       Pigeon contract (source of the generated files)
ios/story_creator_kit/Sources/ Swift (SPM + CocoaPods): AVFoundation export, probe, waveform, thumbnails
android/src/main/kotlin/       Kotlin: Media3 Transformer export, probe, waveform, thumbnails
example/                       demo app + integration_test/
test/                          unit, widget, golden; mirrors lib/src paths; fakes in test/fakes/
```

## Commands

```bash
flutter pub get                               # root + example
flutter analyze                               # must be clean (infos included)
dart format .                                 # format
flutter test                                  # unit + widget + golden
flutter test --update-goldens                 # after an intended visual change
dart run pigeon --input pigeons/story_native_api.dart   # after editing the contract
cd example && flutter test integration_test   # on a booted simulator / emulator
dart pub publish --dry-run                    # publish readiness (never run the real publish)
./tool/sync_agents.sh                         # after editing this file
```

## Rules

- **Public API is explicit.** Only `lib/story_creator_kit.dart` exports. Everything else lives under `lib/src/`. Every public symbol has a dartdoc comment. Breaking changes go in `CHANGELOG.md`.
- **Host-agnostic.** No app, backend, analytics or DI assumptions. No MobX, Provider, GetIt, hooks, routing or localization packages in `lib/`. State is `ChangeNotifier` / `ValueNotifier` / `InheritedWidget`.
- **No inline UI strings.** All user-visible text comes from `StoryCreatorStrings` (English defaults, host-overridable). Semantics labels too.
- **No hard-coded colours or text styles in widgets.** Read them from `StoryCreatorTheme` via the scope.
- **One document, two renderers.** Anything visible on the canvas is drawn by a painter in `lib/src/render/painters/`, used by both the editor view and the export rasterizer. Never draw an edit only in the widget tree.
- **Canvas units.** Overlays, strokes and placement are stored in 1080×1920 canvas coordinates, never screen pixels.
- **Services behind interfaces.** Widgets and controllers talk to `CaptureService`, `GallerySource`, `PermissionService`, `MusicSession`, `VideoSession`, `StoryExporter`; plugins are only touched in their `*_impl` / named implementations. Tests use `test/fakes/`.
- **Errors are typed.** Catch plugin/platform errors at the service boundary and map them to `StoryException` codes. Every `catch` either rethrows as a typed error, reports through `onEvent`, or shows the error in UI — never swallows silently.
- **Temp files belong to the session.** Everything written goes into the session directory and is deleted on every exit path (complete keeps only the result file).
- **Native contract changes** go through `pigeons/story_native_api.dart` → regenerate → update Swift and Kotlin together.
- **Widget discipline.** No `Widget _buildX()` helper methods; extract widget classes. `const` constructors where possible. Tap targets ≥ 48 logical px and a `Semantics` label on every control.
- **Imports.** Relative imports inside `lib/`, single quotes, trailing commas (enforced by `analysis_options.yaml`).
- **Never edit generated files** (`lib/src/native/*.g.dart`, `*.g.swift`, `*.g.kt`).

## Testing

- Unit + widget tests for every controller, model and screen state; goldens for painters.
- `example/integration_test/` exercises the real native export on a simulator/emulator and verifies output with `probe()`.
- Report honestly: what ran on which device, and what could not be verified (iOS Simulator has no camera; no physical device in CI).

## Agents

`.claude/agents/`: `flutter-team` (Dart/Flutter), `ios-team` (Swift/AVFoundation), `android-team` (Kotlin/Media3), `mobile-orchestrator` (cross-platform contract work). They review; implementation agents are briefed per phase from the plan.
