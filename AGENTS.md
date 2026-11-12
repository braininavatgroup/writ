# Writ

Writ is a macOS menu bar app that holds a standing priority order for audio input and output devices: Swift, SwiftUI and AppKit, no third-party dependencies, bundle ID `dance.braininavat.writ`.

The check is `python3 site/test_site_copy.py && python3 site/test_feature_map.py && python3 tools/test_verify_signing.py && python3 tools/test_workflows.py && swift test`. `swift test` needs Xcode, because the Command Line Tools lack the SwiftUI macro plugin. A PR's `ci` runs the Python checks on Ubuntu and calls `native.yml` for `swift-test` on GitHub-hosted macOS: writ is public, so no writ job runs on the Mini's runners, which can reach the login Keychain (BIV-1608), and standard hosted runners cost nothing in a public repository. `native.yml` runs only for pushes and same-repository pull requests, so a pull request from a fork fails `ci` by design; a fork's code is Bradley's call. Releases and `verify-signing.yml` run only when Bradley authorizes the run (BIV-1320): dispatches from the tag with `hosted_macos` set, never a tag push alone.

Layers run system (CoreAudio and IOKit wrappers, no UI framework) -> logic (device order, hot keys, updates, install) -> ui (SwiftUI views and AppKit windows), each using only itself and the layers before it. The app is one SwiftPM target, so the compiler only stops `Writ` importing `WritTests`; `Tests/WritTests/LayerTests.swift` assigns every source file a layer and fails a wrong-way reference.

Device memory is permanent by design, so anything you filter out of live enumeration must also be purged from saved state, or it never ages out.

The site (`site/public`, writ.braininavat.dance) deploys from `ci`'s `deploy-site` job after the check passes on a push to main that changed `site/`; its live step runs `tools/live site`, and `gh workflow run deploy-site.yml` re-deploys main.

Live: `tools/live` walks `features/features.json`, checks production read-only (pages, links, assets, appcast.json) and exits non-zero on any failure; any live check you'd otherwise improvise belongs in it.

This public repo's own secrets are Apple signing and `CLOUDFLARE_API_TOKEN`, so add a key here only with the workflow that reads it.

Crash and failed-device-switch reporting is opt-in and posts only its fixed three-field schema to the public, rate-limited `/app/writ` route; a native binary never contains the shared intake secret. For a deliberately non-networking build, set `WRIT_UPDATE_FEED= WRIT_SUPPORT_EMAIL= WRIT_ERROR_REPORT_URL=`.

Sandboxing is only for the Mac App Store build (`./build.sh --appstore`), never the default, and the app icon stays original artwork, never an SF Symbol; build and signing are in `docs/development-reference.md`.
