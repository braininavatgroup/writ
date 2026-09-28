---
name: verify-writ
description: Build and drive Writ’s real macOS UI through accessibility identifiers, capture evidence, check the site, and clean up the preview process.
---

# Verify Writ

From the repository root, first run the source and site checks:

```bash
python3 site/test_site_copy.py
python3 site/test_feature_map.py
swift test
tools/live site
```

Build an isolated, non-networking preview and start the process you own:

```bash
WRIT_UPDATE_FEED= WRIT_SUPPORT_EMAIL= ./build.sh --fast
mkdir -p .context/verification
./dist/Writ.app/Contents/MacOS/Writ --preview >.context/verification/writ-preview.log 2>&1 &
preview_pid=$!
```

Use computer-use on the Writ app. Capture its accessibility tree and a screenshot under `.context/verification/`. Check `writ.enforcing`, both `writ.direction.*` tabs, one dynamic `writ.device.*` row, `writ.settings`, and the Keyboard Shortcuts window. Do not click Mute, a device row, Restore Priority Order, update, support, Quit, or any shortcut value: those change audio, preferences, open another app or end evidence capture. Close the settings window, then clean up only the owned preview:

```bash
kill "$preview_pid"
wait "$preview_pid" 2>/dev/null || true
```

Evidence must survive cleanup. A source-only pass is a draft; record why the UI could not be driven. Update `features/README.md`, `features/features.json` and the identifier in source together.
