---
name: verify-writ
description: Verify Writ without disturbing the active Mac; drive its real UI only on an isolated GUI host, capture evidence, check the site, and clean up owned processes.
---

# Verify Writ

From the repository root, first run the source and site checks. These are the
default verification on Bradley's active Mac:

```bash
python3 site/test_site_copy.py
python3 site/test_feature_map.py
swift test
tools/live site
```

Do not launch Writ, order a window onscreen, use computer control, invoke global
shortcuts, replace or quit the installed app, change preferences, select audio
devices, or touch USB hardware on Bradley's active Mac. A worktree isolates
files, not the desktop, WindowServer, CoreAudio, defaults, or hardware. A broad
request to test Writ is not permission to use those shared resources.

Real UI verification runs only on an isolated GUI host: a disposable macOS VM,
a hosted macOS desktop that supports GUI interaction, or a dedicated test Mac.

`--preview` opens an ordinary design-preview window and deliberately bypasses
`StatusItemController`. Use it for layout and accessibility review only; it
cannot verify the menu-bar item, non-activating panel, outside-click handling,
or panel controls. On the isolated host, build the non-networking app:

```bash
WRIT_UPDATE_FEED= WRIT_SUPPORT_EMAIL= WRIT_ERROR_REPORT_URL= ./build.sh --fast
mkdir -p .context/verification
./dist/Writ.app/Contents/MacOS/Writ >.context/verification/writ.log 2>&1 &
preview_pid=$!
```

Use computer-use on the isolated host's Writ app. Capture its accessibility tree
and a screenshot under `.context/verification/`. Check `writ.enforcing`, both
`writ.direction.*` tabs, one dynamic `writ.device.*` row, `writ.settings`, and
the Keyboard Shortcuts window. Start from a fresh guest snapshot: this command
uses that host's actual preferences and CoreAudio devices. Do not attach
Bradley's dock, microphone, or audio path. Close the settings window, then clean
up only the owned process PID:

```bash
kill "$preview_pid"
wait "$preview_pid" 2>/dev/null || true
```

Evidence must survive cleanup. A source-only pass is a draft; record why the UI could not be driven. Update `features/README.md`, `features/features.json` and the identifier in source together.

Current-session UI or hardware control is allowed only when Bradley explicitly
requests the exact interaction at that time. State which app, shortcut,
preference, or device will be touched before doing it, and stop on any focus or
input conflict.
