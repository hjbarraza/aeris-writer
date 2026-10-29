# M4 — Polish, writing aids, automation

Milestone goal: the P1 extras that make the editor pleasant — style check, custom
patterns, URL scheme, themes, preferences. Depends on M1.5 and M3.

Legend: `[ ]` todo · `[x]` done. Keep `swift build` and `swift run mdcheck` green.

---

- [ ] **M4-0 — Preferences window.** `NSWindowController` with SwiftUI panes:
  General, Editor (font, size, insets), Markdown (extensions), Preview (theme),
  Publishing (from M6). Settings via `UserDefaults` keys in one `Prefs` enum.
  *Verify:* change editor font → applies live; relaunch keeps it.

- [ ] **M4-1 — Preview themes.** Two built-in CSS themes (light/dark variants each);
  user CSS override file in Application Support.
  *Verify:* switch theme → preview updates; custom CSS applies.

- [ ] **M4-2 — Style check.** `NaturalLanguage` tagging; one Style Check menu with a
  master on/off and independently toggled targets: parts of speech (adjectives, nouns,
  adverbs, verbs, conjunctions) and style (fillers, clichés, redundancies, custom from
  M4-3). Turning the master back on restores the last set of targets; choices persist.
  Runs on the visible range, debounced.
  *Verify:* enable adverbs → "quickly" highlighted; disable → cleared; enable adverbs and
  clichés, master off then on → both back; relaunch keeps them; no lag on a 10k-word doc.

- [ ] **M4-3 — Custom patterns.** User-defined regex/word-list rules with a colour,
  managed in Preferences; applied by the style-check pass.
  *Verify:* add rule `\bvery\b` → highlighted.

- [ ] **M4-4 — URL scheme.** `aeris://` (x-callback-url style): `open?path=`, `new?text=`,
  `append?path=&text=`, `export?path=&format=`, `publish?path=&account=`. Registered
  via `Info.plist` (INF-1). Calls that mutate ask once for a per-caller token.
  *Verify:* `open "aeris://open?path=/tmp/a.md"` opens the file; `append` adds text.

- [ ] **M4-5 — Command palette.** ⇧⌘P: fuzzy list of every menu command.
  *Verify:* type "type" → "Typewriter Mode" → Return toggles it.

- [ ] **M4-6 — Document outline.** Sidebar pane listing headings; click to jump.
  *Verify:* click H2 → editor scrolls to it.

- [ ] **M4-7 — Version browser polish.** Confirm `NSDocument` version browser works with
  xattr metadata; diff view via `diff-match-patch` (optional).
  An older version shown in the browser is read-only.
  *Verify:* Revert To ▸ Browse All Versions shows history; typing into an old version
  does nothing; Restore replaces the text and the current text is kept as a version.

- [ ] **M4-8 — Theme per document and typography options.** Choosing a preview theme
  applies it to the current document (stored in its xattrs, never in the `.md`) and
  makes it the default for documents without a choice. Theme options: centre headings,
  number headings, indent paragraphs. Apply to preview, export and print.
  *Verify:* document A uses theme X, B uses Y → reopen both, each keeps its theme; `.md`
  bytes unchanged; "number headings" → preview shows 1, 1.1, …

- [ ] **M4-9 — Markdown syntax settings.** Settings choose what the Format commands
  write: emphasis marker (`*` / `_`), strong marker (`**` / `__`), bullet (`-` / `*` /
  `+`), ordered-list delimiter (`.` / `)`), heading style (`#` prefix, or underline for
  levels 1–2). `MarkdownCore` edit functions take these as parameters (tested); the
  Markdown pane shows them.
  *Verify:* bullet `*` → Format ▸ Bullet List writes `* `; emphasis `_` → ⌘I wraps in
  `_`; `mdcheck` cases for each option.

- [ ] **M4-10 — Editor layout and text-checking settings.** Editor pane: line length
  (maximum text-column width, or full width); a checklist of system text checking
  (spelling, grammar, autocorrect, smart insert/delete, text completion and inline
  predictions where macOS offers them). Automatic quote and dash substitution stay off
  in the editor whatever the system default (smart punctuation is a preview concern,
  M1-9).
  *Verify:* line length 70 characters → a wide window keeps a centred 70-character
  column; turn grammar on → grammar underline appears; with system smart quotes on,
  typing `"` in the editor stays straight in the file.

- [ ] **M4-11 — URL commands: consent and more commands.** The first time another app
  sends an `aeris://` command, an alert asks to Enable or Disable URL commands
  (remembered; changeable in Preferences). Links clicked inside Aeris never ask. Adds
  `read?path=` (returns the text via x-success) and `search?query=` (opens Quick Search
  with the query). x-success URLs are opened on success; failures open x-error, or show a
  sheet when there is none. Preferences shows each caller's token with Copy and Reset
  (Reset asks first).
  *Verify:* first external `open "aeris://open?path=…"` → prompt; Disable → later calls
  blocked; `append` with a wrong token → x-error called; `search?query=foo` → Quick Search
  open with "foo".

Exit criteria for M4: `aeris://open?path=…` opens a file; style check highlights
adverbs; theme switch persists across relaunch.
