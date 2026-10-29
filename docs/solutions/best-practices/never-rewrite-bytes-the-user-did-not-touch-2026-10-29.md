---
title: Never rewrite bytes the user didn't just type or ask to change
date: 2026-10-29
category: docs/solutions/best-practices/
module: Editor text handling, file opening, list editing, file operations
problem_type: best_practice
component: service_object
severity: high
last_updated: 2026-10-29
applies_when:
  - An edit hook converts or normalizes text (line endings, numbering, markers, encodings)
  - Code decides whether a file is text and may later autosave it
  - A feature writes to files other than the one being edited, or renames/moves files
  - Input comes from outside the app (paste, open, drop) and may be hostile or huge
tags: [data-safety, line-endings, multi-range-edit, binary-detection, atomic-create, paste, symlinks, fuzzing]
---

# Never rewrite bytes the user didn't just type or ask to change

## Context
Most data-safety fix rounds on 2026-10-29 had one shape: well-meaning code touched bytes
outside the user's edit.
- Line-ending conversion in `shouldChangeTextInRanges` shifted later ranges of a
  multi-range edit (paste over two selections deleted the wrong characters; Replace All
  landed one character off).
- A rule refusing control bytes would have stopped existing notes with a stray vertical
  tab from opening.
- List renumbering rewrote deliberately numbered lists (`1. 1. 1.`, years).
- A rich-text paste converter crashed on deep nesting and froze on 2 MB; binary files could
  open as text and be autosaved over.
- Two drafts with the same first line could both claim `My Post.md` (check-then-act race).

## Guidance
1. **Convert only the user's new insertion, and only when it's unambiguous.** Pass the edit
   through unchanged when several ranges change, when the replaced text already holds line
   breaks, during IME composition, or during programmatic edits.
2. **Apply strict rules only where the user's intent is unclear.** Refuse control bytes
   only for files without a text extension; NUL refuses everything.
3. **Only "repair" what was already consistent.** Renumber a list only if it was sequential
   before the edit.
4. **Cap input, output and depth for anything parsed from outside.** Sniff the first 8 KB
   before reading a whole file; cap HTML depth (256) and both input and output size (2 MB).
   A size cap must look at the real file: `fileSizeKey` on a symlink is the link's own
   size (a link to a 3 MB file reported 6 bytes), so resolve symlinks first and require
   `isRegularFileKey` (a FIFO named `x.md` would otherwise block the reading queue).
5. **Claim names atomically.** `open(path, O_WRONLY|O_CREAT|O_EXCL)`, then save over your
   own placeholder; on failure remove only that placeholder.
6. **Destructive file actions go to the Trash only**; never permanent delete.
7. **Verify parser positions before editing with them.** swift-markdown's source ranges are
   wrong on indented or lazy continuation lines (and with CRLF, blockquotes, multibyte
   text). Before removing markers at a span, check the text there really is the marker run;
   otherwise fall back. Toggling bold off on `"line one\n  **bold** more"` deleted "ld"
   until this check existed.
8. **Fuzz text transforms**: a few thousand random inputs, apply and re-apply, assert no
   non-marker character is lost. Fuzzing found the parser-offset bug in minutes.

## Why This Matters
These bugs don't crash; they silently change or lose writing, often in files the user isn't
looking at. Reviews found them only by asking "what existing bytes can this touch?".

## When to Apply
- Every brief and review for code in the editor's change delegate, document read/save,
  list/format commands, paste/drop, and file operations.

## Examples
- Line endings: `ranges.count == 1 && selectedRanges.count == 1 && replaced text has no
  CR/LF` → convert; otherwise return true unchanged.
- Renumber: `1. a / 2. b / 3. c` + Return after a → `1. a / 2. / 3. b / 4. c`;
  `1. a / 1. b / 1. c` + Return → only the new item is numbered.
- Binary: a PNG renamed `x.text` → refused with "It isn't a plain text file."; `Note.md`
  containing a vertical tab → opens and saves byte-identical.
- Parser spans: keep a swift-markdown span only if `text[openRange] == "**"` (or the
  expected marker) and the close run matches; else use the text-based path. A 2,500-input
  fuzz (toggle twice, assert only `*_~=` changed) now runs in mdcheck.
- Size cap: `url.resolvingSymlinksInPath()` then check `.isRegularFileKey` and
  `.fileSizeKey <= 2 MB` before `Data(contentsOf:)`.

## Related
- `docs/solutions/runtime-errors/text-typed-after-autosave-lost-2026-10-29.md`
