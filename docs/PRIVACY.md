# Writ — Privacy Policy

_Last updated: 17 September 2026_

Writ does not create an account or collect analytics, crash reports, or app
telemetry. This page exists because an app that asks for microphone access owes
you a specific answer rather than a reassuring one.

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

Deleting the app and that file removes everything Writ has ever kept.

## Network

Writ makes no network connections in the course of managing your audio.

Two features make them:

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

## Third parties

Writ contains no third-party code, SDKs, frameworks or trackers. Writ does not
send analytics or telemetry about how you use the app. Update checks expose
only the ordinary request metadata described above, and Contact Support sends
only what you review and choose to send.

## Your rights

Because Writ does not retain personal data, there is nothing held about you to
access, correct, export or delete. Data stored locally is yours and under your
control at all times.

## Contact

Questions about this policy: see the support address on the Writ download page.
