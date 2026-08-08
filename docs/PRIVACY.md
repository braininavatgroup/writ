# Writ — Privacy Policy

_Last updated: 8 August 2026_

Writ collects nothing about you. There is no account, no analytics, no crash
reporting and no telemetry of any kind. This page exists because payment
processors and app marketplaces require one, and because an app that asks for
microphone access owes you a specific answer rather than a reassuring one.

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
  request the server can see your IP address and the standard headers your
  system sends; no identifier for you or your Mac is included, and no record is
  kept. Nothing about your devices, settings or usage is transmitted.

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

Writ contains no third-party code, SDKs, frameworks or trackers. Nothing about
your use of it is shared with anyone, because nothing about your use of it
leaves your Mac.

If you buy Writ, the purchase is handled by a payment provider under their own
privacy policy. Writ itself never sees your payment details.

## Your rights

Since no personal data is collected or transmitted, there is nothing held about
you to access, correct, export or delete. Data stored locally is yours and under
your control at all times.

## Contact

Questions about this policy: see the support address on the Writ download page.
