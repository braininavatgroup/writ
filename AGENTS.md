# Writ

Writ is a macOS menu bar app that holds a standing priority order for audio input and output devices: Swift, SwiftUI and AppKit, no third-party dependencies, bundle ID `dance.braininavat.writ`.

The check is `python3 site/test_site_copy.py && python3 site/test_feature_map.py && swift test`. `swift test` needs Xcode, because the Command Line Tools lack the SwiftUI macro plugin; without Xcode, the PR's `ci` run on macos-15 is the proof.

Layers run system (CoreAudio and IOKit wrappers, no UI framework) -> logic (device order, hot keys, updates, install) -> ui (SwiftUI views and AppKit windows), each using only itself and the layers before it. The app is one SwiftPM target, so the compiler only stops `Writ` importing `WritTests`; `Tests/WritTests/LayerTests.swift` assigns every source file a layer and fails a wrong-way reference.

Device memory is permanent by design, so anything you filter out of live enumeration must also be purged from saved state, or it never ages out.

The site (`site/public`, writ.braininavat.dance) deploys from `ci`'s `deploy-site` job after the check passes on a push to main that changed `site/`; its live step runs `tools/live site`, and `gh workflow run deploy-site.yml` re-deploys main.

Live: `tools/live` walks `features/features.json`, checks production read-only (pages, links, assets, appcast.json) and exits non-zero on any failure; any live check you'd otherwise improvise belongs in it.

Cloud agents working writ issues run from music-promo (`agent.yml` per issue, `cleanup-pass.yml` daily) with the org secrets `LINEAR_API_KEY` and `CLAUDE_CODE_OAUTH_TOKEN`; this public repo's own secrets are Apple signing and `CLOUDFLARE_API_TOKEN`, so add a key here only with the workflow that reads it.

Sandboxing is only for the Mac App Store build (`./build.sh --appstore`), never the default, and the app icon stays original artwork, never an SF Symbol; build and signing are in `docs/development-reference.md`.
