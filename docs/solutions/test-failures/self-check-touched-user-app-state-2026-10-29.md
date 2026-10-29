---
title: The self-check wrote into the user's real app state
date: 2026-10-29
category: docs/solutions/test-failures/
module: SelfCheck (--selfcheck) and app defaults
problem_type: test_failure
component: testing_framework
symptoms:
  - After test runs the user's column widths and collapsed sections were reset
  - File ▸ Open Recent filled with deleted temp files
  - A layout check failed only because earlier runs had changed shared preferences
  - Concurrent test runs overwrote each other's settings
root_cause: test_isolation
resolution_type: code_fix
severity: high
tags: [selfcheck, userdefaults, open-recent, window-restoration, test-isolation, bundle-id]
---

# The self-check wrote into the user's real app state

## Problem
`--selfcheck` ran inside the real app bundle with the real bundle id, so everything it did
landed in the user's preferences, window state and recent documents, including while the
user was testing the app.

## Symptoms
- Relaunch didn't keep the user's widths/sections; Open Recent held `aeris-selfcheck-…`
  paths; a preference key held a self-check temp folder.

## What Didn't Work
- Snapshot-and-restore of the defaults domain: a hang or crash leaves the user's prefs
  changed.
- Overriding `noteNewRecentDocumentURL` alone: ad-hoc signing with a per-build cdhash
  requirement made every rebuild reset Open Recent anyway.

## Solution
- All app defaults go through one `AppDefaults.store`: `.standard` normally, a cleared
  `UserDefaults(suiteName: "<bundle id>.selfcheck")` under `--selfcheck`.
- Self-check windows are not restorable; `ApplePersistenceIgnoreState = true` is
  registered before `app.run()` under `--selfcheck`.
- `noteNewRecentDocumentURL` does nothing when isolated.
- Split-view autosave keys use a `…SelfCheck…` prefix and are removed at start and end
  (and by the 240 s watchdog, which then `_exit(1)`s).
- `scripts/bundle.sh` signs with `designated => identifier "<bundle id from Info.plist>"`.
- Parallel runs: each worktree re-signs its bundle with its own `CFBundleIdentifier`.

## Why This Works
Every piece of state macOS keys by bundle id (defaults, saved application state, Open
Recent) is either redirected, disabled, or given a different id during the self-check.

## Prevention
- Evidence for any change here: `defaults export <id>` and the Open Recent `.sfl4` file are
  byte-identical before and after a full self-check run with the user's app open.
- Self-checks go through real entry points (`table.menu(for:)` with a synthetic event,
  `NSApp.sendAction`), not internal helpers, so they test what the user sees.
- Timing assertions get ~10× headroom over the measured idle time, written in a comment.

## Related Issues
- `docs/solutions/developer-experience/rebuilding-under-the-running-app-2026-10-29.md`
