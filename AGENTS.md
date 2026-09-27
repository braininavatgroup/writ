# Writ

Writ is a macOS menu bar app that holds a standing priority order for audio input and output devices: Swift, SwiftUI and AppKit, no third-party dependencies, bundle ID `dance.braininavat.writ`.

The check is `python3 site/test_site_copy.py && swift test`. `swift test` needs Xcode, because the Command Line Tools lack the SwiftUI macro plugin; without Xcode, the PR's `ci` run on macos-15 is the proof.

Device memory is permanent by design, so anything you filter out of live enumeration must also be purged from saved state, or it never ages out.

The site (`site/public`, writ.braininavat.dance) deploys from `ci`'s `deploy-site` job after the check passes on a push to main that changed `site/`; its live step runs `tools/live site`, and `gh workflow run deploy-site.yml` re-deploys main.

Live: `tools/live` checks production read-only (pages, links, assets, appcast.json) and exits non-zero on any failure; any live check you'd otherwise improvise belongs in it.

Sandboxing is only for the Mac App Store build (`./build.sh --appstore`), never the default, and the app icon stays original artwork, never an SF Symbol; build and signing are in `docs/development-reference.md`.
