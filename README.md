# Audio Priority

A macOS menu bar app that keeps your audio input and output on the devices you
actually want, instead of whatever connected most recently.

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
- Volume, mute, launch at login

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

## Build

Requires macOS 13+ and Swift 6.

```sh
./build.sh          # produces dist/Audio Priority.app
```

No third-party dependencies — Apple frameworks only (CoreAudio, AVFoundation,
AppKit, SwiftUI, IOKit, ServiceManagement).

The build is ad-hoc signed, which is fine locally. Distributing to another
machine needs a Developer ID certificate and notarisation.

## Status

Personal tool, works. Not signed for distribution, no license chosen yet.
