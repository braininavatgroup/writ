# Writ

A macOS menu bar app that keeps your audio input and output on the devices you
actually want, instead of whatever connected most recently.

Your priority list is a standing order the audio system obeys.

macOS has no concept of device priority — it simply switches to the newest
arrival. This enforces an explicit order, per direction, with rules.

## What it does

- **Priority order** for input and output, drag to reorder, click a device to
  use it now
- **Never use** — a hard block. The monitor over DisplayPort/HDMI is flagged
  automatically, because display audio hijacks output the moment a screen
  connects
- **Only when lid is open** — auto-applied to the built-in mic
- **Device memory** — devices are remembered by UID and hold their rank while
  disconnected
- **Input metering** — level, peak hold, rolling average and noise floor, plus
  Apple's microphone mode (Standard / Voice Isolation / Wide Spectrum)
- **Per-device icon and label**, chosen from SF Symbols
- **Global shortcuts** — mute the microphone (⌃⌥⌘M) or open Writ (⌃⌥⌘A) from any
  app, plus unassigned actions for pausing, restoring the order and cycling
  devices. Registered through Carbon, so Writ never asks for Accessibility
  permission and cannot read your keyboard
- Volume, mute, launch at login

`docs/GUIDE.md` is the user guide. `docs/PRIVACY.md` and `docs/EULA.md` hold the
legal text for the packaged app. Developer guidance is in `AGENTS.md`, release
notes in `CHANGELOG.md`, and the download site in `site/README.md`.

## Notes from building this

Things that are not obvious, and cost time to discover:

**The built-in mic is hardware-disconnected when the lid closes.** On Apple
silicon this happens below any software layer, so the device still enumerates
but captures silence. The "only when lid is open" rule exists to avoid
*selecting a dead device*, not to disable a working one.

**AirPlay devices are anonymous and per-session.** macOS names every AirPlay
target the bare string `AirPlay`, and their UIDs carry a per-session suffix:

```
cb56dc98-8819-425c-a21d-6b9ca8bb805a-2926033793250-Audio
└───────── stable per speaker ─────┘ └── per session ──┘
```

Keying on the full string makes a reconnected HomePod look like a new device.
Entries are keyed on the leading UUID instead. Because a name is the only way to
tell two AirPlay targets apart, a device becomes permanent once you label it and
is discarded otherwise. AirPlay is never overridden by the enforcer — nothing
connects to a HomePod by accident.

**`AVAudioEngine` creates phantom devices.** Tapping the default input makes
macOS spawn a private `CADefaultDeviceAggregate-<pid>-<n>` device. It enumerates
like any other and must be filtered, in both live enumeration and stored state.

**Microphone modes are read-only.** `activeMicrophoneMode` and
`preferredMicrophoneMode` can be read but never set; `showSystemUserInterface`
is the only affordance. The app reports the mode and opens Apple's picker.

**`MenuBarExtra` takes key focus,** which swallows ⌘V and breaks pasting into
other apps while the panel is open. The menu bar item is therefore AppKit —
`NSStatusItem` plus a `.nonactivatingPanel` shown with `orderFrontRegardless()`.
The trade-off is that standard controls render in their disabled grey state in a
non-key window, so the switch and segmented picker are custom-drawn.

**`List.onMove` does not work inside a menu bar panel,** and a row-wide drag
source swallows clicks. Reordering uses a plain `DragGesture` on the grip alone,
with fixed-height rows so the offset maths is exact.

**`MenuBarExtra` cannot be sandboxed into someone else's preferences.** Adding
`com.apple.security.app-sandbox` confines the app to its own container, so it
can no longer read the previous bundle identifier's defaults — which silently
orphaned every saved ranking during the rename. Sandboxing is therefore applied
only to the Mac App Store build.

## Build

Requires macOS 13+ and Swift 6.

```sh
./build.sh             # universal (arm64 + x86_64), ad-hoc signed
./build.sh --fast      # arm64 only, quick local iteration
./build.sh --release   # Developer ID + hardened runtime, ready to notarise
./build.sh --appstore  # + App Sandbox, Mac App Store only

swift test --scratch-path .build-test
./release.sh           # build → notarise → staple → DMG + zip
```

Universal is the default: Setapp requires a fat binary and Intel Macs still run
macOS 13. There is no runtime cost — Apple silicon executes the arm64 slice.

No third-party dependencies — Apple frameworks only (CoreAudio, AVFoundation,
AppKit, SwiftUI, IOKit, ServiceManagement).

## Distribution notes

Verified under the App Sandbox on macOS 26 with a signed test bundle:

| operation | sandboxed |
|---|---|
| IOKit `AppleClamshellState` read | works |
| CoreAudio device enumeration | works |
| CoreAudio default-device **write** | works |

No temporary-exception entitlements needed, so the App Store route is open.
Setapp requires a notarised, Developer ID signed, universal binary.

The app icon is original artwork. Apple's SF Symbols licence permits symbols
throughout the UI but forbids them — or confusingly similar glyphs — in app
icons, logos, or any trademark-related use.

## Status

Shippable. Signed with Developer ID, hardened runtime, notarised and stapled, so
it validates offline and opens with no Gatekeeper warning. `./release.sh`
produces the DMG.

## Download

Writ is free to download while it is in beta: [writ.braininavat.dance](https://writ.braininavat.dance).
The app checks that site's update feed for new versions.

## License

The source is published under the [PolyForm Noncommercial License 1.0.0](LICENSE).
You can read it, build it, and use it for any noncommercial purpose. Commercial
use, including redistribution for a fee, needs a separate license from the
author.
