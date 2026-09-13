# Writ

Global policy: read [global AGENTS.md](https://github.com/braininavatgroup/dotfiles/blob/main/agents/AGENTS.md) (installed at `~/.codex/AGENTS.md`; source checkout `~/Spaces/dotfiles/agents/AGENTS.md`). This file owns only repository-specific instructions.

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
