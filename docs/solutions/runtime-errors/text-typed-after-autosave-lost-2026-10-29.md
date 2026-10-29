---
title: Text typed after an autosave was dropped on close or quit
date: 2026-10-29
category: docs/solutions/runtime-errors/
module: MarkdownDocument (NSDocument save path) and the editor NSTextView
problem_type: runtime_error
component: service_object
symptoms:
  - Words typed right after an autosave are missing from the file after closing the window or quitting
  - isDocumentEdited stays false after typing, so no save prompt and no further autosave
  - Only reproducible in a real event loop; the headless self-check stays green
root_cause: async_timing
resolution_type: code_fix
severity: critical
tags: [nsdocument, autosave, undo-coalescing, data-loss, nstextview, change-count]
---

# Text typed after an autosave was dropped on close or quit

## Problem
After any save that landed while the user was mid-typing (autosave in place, or a draft
naming itself on Return), the next keystrokes were folded into the typing undo action
registered *before* the save. The document's change count never rose again, so closing the
window or quitting discarded those words silently.

## Symptoms
- Type "# My Post", pause for an autosave, keep typing, ⌘W → the file holds "# My Post"
  without the later words; no "Save changes?" prompt.
- `isDocumentEdited == false` right after typing.

## What Didn't Work
- Headless self-checks that type with key events: the app's self-check runs before
  `NSApp.run`'s event loop, so the per-event undo group never closes and the bug can't show
  either way (checks passed with and without the fix).
- Sending keys through `window.sendEvent` from a main-queue block: same problem.

## Solution
Close the open typing undo group before every save (Apple documents this duty for save
overrides):

```swift
override func save(to url: URL, ofType typeName: String,
                   for saveOperation: NSDocument.SaveOperationType,
                   completionHandler: @escaping (Error?) -> Void) {
    for wc in windowControllers {
        Self.textViews(in: wc.window?.contentView).forEach { $0.breakUndoCoalescing() }
    }
    // … existing guards, then super.save(…)
}
```

## Why This Works
NSTextView coalesces consecutive typing into one undo action. A save resets the change
count to "clean"; without breaking coalescing, later keystrokes extend the pre-save action
and never register a new change. `breakUndoCoalescing()` makes the next keystroke start a
new undo action, which increments the change count after the save.

## Prevention
- Any change to saving, undo grouping or typing needs a real-event-loop test: post key
  events with `NSApp.postEvent` into a key window inside `NSApp.run`, then assert
  `isDocumentEdited` and the bytes on disk after close/quit.
- Don't trust a headless self-check for this class; say so in the review evidence.
- Keep the `breakUndoCoalescing()` line first in `save(to:ofType:for:completionHandler:)`.

## Related Issues
- `docs/solutions/test-failures/` — why headless checks can't see it.
