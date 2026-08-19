# Changelog

Notable changes to Writ. Versions follow the `VERSION` file; the build number is
the commit count and is what the updater compares.

## 1.0 — unreleased

First release.

### Added

- Repository documentation is directly Obsidian-openable, with an explicit audited record that
  the archived Agent Workspace assigned zero legacy pages to Writ (BIV-227, #30).
- Priority order for input and output devices, enforced continuously. Drag to
  reorder, click a device to use it now.
- **Never use** — a hard block, applied automatically to display audio, which
  otherwise hijacks output the moment a monitor wakes.
- **Only when the lid is open** — applied automatically to the built-in
  microphone, which is disconnected in hardware when a MacBook is closed and
  captures silence while still appearing in every audio menu.
- Device memory by identifier, so unplugging something never loses its rank.
- Input metering: level, peak hold, rolling average and noise floor, plus a
  shortcut to Apple's microphone mode picker. Audio is measured and discarded.
- Per-device custom label and SF Symbol.
- AirPlay handling — never overridden, keyed on the stable part of an identifier
  that otherwise changes every session, and kept permanently once you name it.
- Global shortcuts: mute the microphone (⌃⌥⌘M) and show or hide Writ (⌃⌥⌘A),
  with four more actions available to assign. Registered through Carbon, so Writ
  never requests Accessibility permission.
- Volume and mute for the current device, and launch at login.
- First-run notice, which detects the case where a menu bar manager has parked
  the icon off-screen and says so.

### Changed

- Required CI now executes the ignored-device eligibility contract, preventing
  a green site-only check from masking a broken **Never use** rule.

### Distribution

- Launch landing page with stable privacy-policy and draft-EULA URLs. Public
  deployment, licensing, and announcement remain separate gated actions.
- Universal binary, macOS 13 and later.
- Signed with Developer ID, hardened runtime, notarised and stapled — validates
  offline and opens with no Gatekeeper warning.
