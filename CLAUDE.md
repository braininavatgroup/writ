# Writ

macOS menu bar app enforcing a standing order for audio input and output
devices. Swift + SwiftUI + AppKit, no third-party dependencies.

Repo: `braininavatgroup/writ` · Bundle ID: `dance.braininavat.writ`

## Build and run

```sh
./build.sh             # universal (arm64 + x86_64), ad-hoc signed
./build.sh --fast      # arm64 only, quick iteration
./build.sh --release   # Developer ID + hardened runtime, ready to notarise
./build.sh --appstore  # + App Sandbox, Mac App Store only

swift test --scratch-path .build-test   # device identity and ranking rules

# install a local build
pkill -f '/Applications/Writ.app'; rm -rf /Applications/Writ.app
cp -R dist/Writ.app /Applications/ && open -a /Applications/Writ.app
```

Version lives in `VERSION`. `CFBundleVersion` is the git commit count — the
updater compares that, never the version string, because "1.10" sorts below
"1.9" as text.

Two Info.plist keys gate features and are empty by default, so a build makes no
network requests and offers no support action until they are set:

```sh
WRIT_UPDATE_FEED=https://…/appcast.json WRIT_SUPPORT_EMAIL=support@… ./build.sh --release
```

`--preview` renders the panel in an ordinary window and deliberately installs no
menu bar item, so the UI can be inspected without fighting a menu bar manager:

```sh
./dist/Writ.app/Contents/MacOS/Writ --preview
```

## Signing

Identity: `Developer ID Application: Bradley Berkman (L65VUZN7VJ)` — team
**L65VUZN7VJ**, not the `U69MKH47B4` on the older Apple Development certs.

```sh
DEVELOPER_ID="Developer ID Application: Bradley Berkman (L65VUZN7VJ)" ./release.sh
```

That builds, notarises, staples, verifies against Gatekeeper and packages both a
DMG and a zip. It refuses to run on a dirty tree, because the build number comes
from the commit count and would otherwise collide with an existing release.

The first notarisation on a new signing identity is held for in-depth analysis —
ours took roughly 26 hours, and a 50 KB hello-world submitted alongside it took
11, which is how we established it was the identity and not the build.
Submissions after that return in minutes.

`.signing/` holds the CSRs and private keys. It is gitignored and must stay
that way — a leaked signing key means revoking the certificate.

## Verifying behaviour

The app mutates live system audio state, so check the real thing rather than
trusting the UI:

```sh
SwitchAudioSource -c -t input        # current input
SwitchAudioSource -c -t output       # current output
SwitchAudioSource -a -t output -f json

# saved rankings, labels and glyphs
osascript -l JavaScript -e 'ObjC.import("Foundation");
  const d = $.NSUserDefaults.alloc.initWithSuiteName("dance.braininavat.writ");
  const s = ObjC.unwrap($.NSString.alloc.initWithDataEncoding(
    d.objectForKey("priorityEntries.output"), $.NSUTF8StringEncoding));
  JSON.parse(s).map(e => (e.customName||e.name)).join(" > ")'
```

A controlled test beats a screenshot: quit the app, force a device it should
refuse, relaunch, and confirm it corrects. If the bad state sticks with the app
off and flips with it on, the app did it.

## Constraints that are not bugs

Each of these looked like a defect first and cost real time:

- **The built-in mic is hardware-disconnected in clamshell.** It still
  enumerates but captures silence. The lid rule avoids selecting a dead device.
  Built-in *speakers* are unaffected and work fine with the lid shut.
- **AirPlay devices are anonymous and per-session.** All named `AirPlay`, with a
  per-session suffix on the UID. Entries key on the leading UUID; a device
  becomes permanent once labelled, and the enforcer never overrides AirPlay.
- **`AVAudioEngine` following the default input spawns a phantom
  `CADefaultDeviceAggregate` device.** Pin the engine to a specific device via
  `kAudioOutputUnitProperty_CurrentDevice`, or it feeds back: phantom appears →
  gets filtered → current device reads nil → meter restarts → another phantom.
- **Microphone modes are read-only.** Report them; `showSystemUserInterface` is
  the only lever.
- **`MenuBarExtra` steals key focus** and breaks ⌘V in other apps. The menu bar
  item is AppKit (`NSStatusItem` + `.nonactivatingPanel`). Consequence: standard
  controls render greyed in a non-key window, so the switch and picker are
  custom-drawn.
- **`List.onMove` does not work in a menu bar panel**, and a row-wide drag source
  swallows clicks. Drag lives on the grip only, with fixed-height rows.
- **Menu bar managers hide new items.** Bartender parks unknown status items
  off-screen (x ≈ −8500). A missing icon is usually this, not a crash — check
  with the System Events AX query before debugging anything. `FirstRun` detects
  it and says so, but only after a delay: the status item window has an EMPTY
  frame for the first moment of its life, and an empty frame is not evidence of
  hiding.

## Working here

- Sandboxing is **not** the default. It confines the app to its own preferences
  container and breaks reading the previous bundle ID's defaults. Mac App Store
  only.
- Device memory is permanent by design, so bad entries never age out on their
  own — anything filtered from live enumeration must also be purged from saved
  state.
- The app icon must stay original artwork. SF Symbols are fine throughout the
  UI but forbidden in app icons, logos, or trademark use.
