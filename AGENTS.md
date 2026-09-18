# Writ

Global policy: read [global AGENTS.md](https://github.com/braininavatgroup/dotfiles/blob/18e1b7c7e69ef71363a9ae1752d23bc35a210b46/agents/AGENTS.md), pinned at dotfiles `18e1b7c7` (installed at `~/.codex/AGENTS.md`; source checkout `~/Spaces/dotfiles/agents/AGENTS.md`). Adopt newer global policy by bumping that SHA in a reviewed change, not by reading `main`, and treat an installed copy that differs from the pinned revision as stale. This file owns only repository-specific instructions.

macOS menu bar app enforcing a standing order for audio input and output
devices. Swift + SwiftUI + AppKit, no third-party dependencies.

Repo: `braininavatgroup/writ` · Bundle ID: `dance.braininavat.writ`

Read `docs/development-reference.md` for build, signing, audio verification, and platform constraints.

## Working here

- Sandboxing is **not** the default. It confines the app to its own preferences
  container and breaks reading the previous bundle ID's defaults. Mac App Store
  only.
- Device memory is permanent by design, so bad entries never age out on their
  own — anything filtered from live enumeration must also be purged from saved
  state.
- The app icon must stay original artwork. SF Symbols are fine throughout the
  UI but forbidden in app icons, logos, or trademark use.
