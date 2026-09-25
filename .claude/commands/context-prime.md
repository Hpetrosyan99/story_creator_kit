Read `AGENTS.md` first. It is the single source of truth for this plugin's layout, rules, commands and testing contract.

Then:

1. Run `git ls-files` to see the file layout.
2. Read `docs/plans/story-creator-kit.md` for what is being built, the architecture (one document, two renderers; the native export engines) and who owns which directory.
3. Skim the two public barrels, `lib/story_creator_kit.dart` and `lib/services.dart`, and the Pigeon contract in `pigeons/story_native_api.dart`.
4. Open `docs/research/*.md` only when you need the reason behind a dependency or platform decision.

Don't load `.cursor/rules/*.mdc` wholesale. They hold language and library detail to consult when you need it, and `AGENTS.md` overrides them.
