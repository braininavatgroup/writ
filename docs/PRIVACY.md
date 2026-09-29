# Writ — Privacy Policy

_Last updated: 28 September 2026_

Writ does not create an account or collect analytics. Optional crash and
failed-device-switch reporting is off by default. This page exists because an
app that asks for microphone access owes you a specific answer rather than a
reassuring one.

## Microphone

Writ requests microphone access for one purpose: to draw the input level meter,
so you can see that your microphone is being heard before you start speaking.

Audio is read in short buffers, reduced to a loudness number, and discarded in
the same instant. It is never written to disk, never buffered beyond the
measurement, never transmitted, and never made available to anything else on
your Mac. Nothing is recorded, so there is nothing to store, share or hand over.

The meter runs only while the panel is open and showing Input. Closing the panel
stops it.

## What Writ stores

On your Mac only, in standard macOS preferences
(`~/Library/Preferences/dance.braininavat.writ.plist`):

- Your priority order for input and output devices
- Device names, unique identifiers and any custom labels or icons you set
- Per-device rules (never use / only when the lid is open)
- Whether enforcement is on, and whether Writ opens at login
- Whether optional error reporting is on, and the last attempt time for each
  error kind so a repeated failure cannot create a reporting loop

Deleting the app and that file removes everything Writ has ever kept.

## Network

Writ never sends audio, device identities, your priority order, labels, settings
or user content.

Three features make network connections:

- **Update checks** — Writ asks a small version file whether a newer release
  exists, once a day, and whenever you choose Check for Updates. As with any web
  request the server can see your IP address, the standard headers your system
  sends, and the fact that Writ checked for an update; no persistent identifier
  for you or your Mac, device details, audio settings, or in-app activity are
  included, and no record is kept.

  Switch it off with **Check Automatically** in the gear menu, and Writ will
  only ask when you do. Builds distributed without an update feed configured
  cannot make the request at all.

  If you choose to install an update, Writ downloads it and verifies that it was
  signed by us before replacing anything. A download that fails that check is
  deleted rather than installed.
- **Contact Support** — opens a draft in your mail app, pre-filled with your
  Writ version, macOS version, Mac model and audio device names. It is a draft.
  You see all of it, you can edit or delete any of it, and nothing is sent until
  you send it.
- **Optional error reports** — off by default. If you switch on **Send Crash &
  Error Reports** in the gear menu, Writ reports a crash or a failed attempt to
  switch audio devices. Each report contains exactly the error kind, Writ
  version and macOS version. It contains no persistent identifier, device name or identifier,
  audio setting, priority order, user content or stack trace. For crashes, macOS
  provides Writ a MetricKit diagnostic; Writ uses only the fact that a crash
  diagnostic exists and discards the diagnostic itself. The request goes
  directly to Brain in a Vat's rate-limited error intake. As with any web
  request, the server can see your IP address and standard headers. The three
  report values are kept in an operational issue so the fault can be fixed.
  Switching the option off stops Writ subscribing to new crash diagnostics and
  sending error reports.

## Third parties

Writ contains no third-party code, SDKs, frameworks or trackers. Writ does not
send analytics or usage telemetry. Update checks expose only the ordinary
request metadata described above, Contact Support sends only what you review
and choose to send, and optional error reports contain only the three values
listed above.

## Your rights

Because Writ does not retain personal data, there is nothing held about you to
access, correct, export or delete. Data stored locally is yours and under your
control at all times.

## Contact

Questions about this policy: see the support address on the Writ download page.
