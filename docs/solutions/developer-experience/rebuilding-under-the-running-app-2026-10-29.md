---
title: Rebuilding the app bundle while it runs breaks the running app
date: 2026-10-29
category: docs/solutions/developer-experience/
module: scripts/bundle.sh
problem_type: developer_experience
component: tooling
severity: high
applies_when:
  - Rebuilding build/Aeris Writer.app while someone is using it
  - Renaming the app bundle or its path
  - Stopping a hung test run
symptoms:
  - "The save file operation failed to connect to the open and save panel service."
  - After a rename, the Dock launched the stale old bundle and testing saw old code
root_cause: missing_tooling
resolution_type: tooling_addition
tags: [codesign, app-bundle, save-panel, xpc, rebuild, pkill]
---

# Rebuilding the app bundle while it runs breaks the running app

## Context
Replacing a running app's bundle invalidates the running process's code signature; macOS
services (the open/save panel) then refuse it. The user hit this mid-edit. After the app
was renamed, a second bundle path existed and the Dock opened the stale one. A test agent
also ran `pkill -x AerisWriter` to stop its own hung run, which would have killed the
user's app with unsaved text.

## Guidance
- `scripts/bundle.sh` refuses to replace a bundle whose executable is running (matched by
  the process's exact executable path at the start of its command line, not a substring —
  a substring match false-positived on unrelated command lines). `AERIS_FORCE_BUNDLE=1`
  overrides.
- Rhythm with a user: tell them a build is ready → they quit → rebuild → they relaunch.
- After renaming the bundle, delete the old build (only when it isn't running) and say
  exactly which app to open.
- Never `pkill`/`killall` the app; run self-checks in the foreground under `timeout 300`.

## Why This Matters
The failure looks like an app bug ("save failed"), costs the user's trust and can cost
unsaved text.

## When to Apply
- Any script or agent that builds, signs, launches or stops the app.

## Examples
```sh
if ps -ax -o command= | grep -v -- '--selfcheck' |
   awk -v exe="$(pwd)/$APP/Contents/MacOS/AerisWriter" 'index($0, exe) == 1 { f = 1 } END { exit !f }'; then
  echo "bundle.sh: $(pwd)/$APP is running - quit it first" >&2; exit 3
fi
```

## Related
- `docs/solutions/test-failures/self-check-touched-user-app-state-2026-10-29.md`
