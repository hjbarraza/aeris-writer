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

- [ ] **M4-7 — macOS Versions.** Aeris is a full participant in File ▸ Revert To ▸
  Browse All Versions (`NSDocument` versions), working with xattr metadata. An older
  version shown in the browser is read-only. Local snapshots (M4-13, M4-14) are the second
  safety net; both exist and neither replaces the other.
  *Verify:* Revert To ▸ Browse All Versions shows history; typing into an old version
  does nothing; Restore replaces the text and the current text is kept as a version.

- [ ] **M4-8 — One global preview theme and options.** The preview, export and print
  all use ONE global theme (Preferences ▸ Preview), not a per-document choice: one
  place to change the look of everything Aeris renders. Nothing about the theme is stored
  in any document or its xattrs. Global options: centre headings, number headings,
  indent paragraphs, invert colours in dark mode. Built-in themes come from M4-1 and
  user-installed ones from M4-15. Typography (size, typeface, line length, writing
  systems) is M4-12 and M4-16.
  *Verify:* choose theme X → preview, exported HTML/PDF and print all use X, in every
  open document; relaunch keeps it; no document's `.md` bytes or xattrs change;
  "number headings" → preview shows 1, 1.1, …; "indent paragraphs" shows in export.

- [ ] **M4-9 — Markdown syntax settings.** Settings choose what the Format commands
  write: emphasis marker (`*` / `_`), strong marker (`**` / `__`), bullet (`-` / `*` /
  `+`), ordered-list delimiter (`.` / `)`), heading style (`#` prefix, or underline for
  levels 1–2). `MarkdownCore` edit functions take these as parameters (tested); the
  Markdown pane shows them.
  *Verify:* bullet `*` → Format ▸ Bullet List writes `* `; emphasis `_` → ⌘I wraps in
  `_`; `mdcheck` cases for each option.

- [ ] **M4-10 — Editor layout and text-checking settings.** Editor pane: line length
  as a number of characters of the current font (not points) or full width, plus a side
  margin of 0–7 characters; the column is centred. Below the width that fits the column,
  a minimum side padding applies and the column shrinks with the window. A checklist of
  system text checking (spelling, grammar, autocorrect, smart insert/delete, text
  completion and inline predictions where macOS offers them). Automatic quote and dash
  substitution stay off in the editor whatever the system default (smart punctuation is
  a preview concern, M1-9). The same line length applies to preview and export (M4-12).
  *Verify:* line length 64 → a 64-character line fills the column exactly and the column
  stays 64 characters as the window grows; narrower than that → it follows the window;
  change the typeface or size → the column keeps its character count; turn grammar on →
  grammar underline appears; with system smart quotes on, typing `"` in the editor stays
  straight in the file.

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

- [ ] **M4-12 — Typography: size steps, typefaces, line length.** Text size is a named
  scale of 14 steps (smallest to largest), not free points; ⌘+ / ⌘− / ⌘0 (M1.5-10) move
  one step and the default step is a setting. Font size and line height come from a table
  keyed on the step, the window-width class (compact / regular) and light / dark, so the
  same step has a different line height in a narrow window than in a wide one. Three
  bundled editor typefaces (proportional, monospaced, duospaced) selectable in
  Preferences ▸ Editor; each defines body, heading, code, quote and emphasis fonts, and
  code stays monospaced in all three. Line length in characters is M4-10. Preview,
  export and print use the same typeface, size step and line length as the editor.
  Bundled fonts have a licence compatible with MIT, recorded in an ADR. The table and
  lookup live in `MarkdownCore` (or a small pure target), tested.
  *Verify:* `mdcheck` cases: step up/down changes size and line height; compact vs
  regular width gives different line heights at one step; switch typeface → editor and
  preview change and code blocks stay monospaced; export a PDF → text size matches the
  preview at the chosen step; relaunch keeps step and typeface.

- [ ] **M4-13 — Local snapshot history: store and thinning.** On every save, a copy of
  the file's text is kept in app storage (Application Support, never beside the file or
  in the user's folder) when it differs from the newest copy for that path. Copies thin
  with age: about 2-minute spacing for the last 10 minutes, 15 minutes for the last hour,
  2 hours for the last day; then one per day for 7 days, then one per week for 4 weeks,
  then none (H, 2026-10-29; a setting can keep them longer). Each library location has
  a "keep local history" switch, and files outside every location count as one more
  location that can be switched off. Deleting or moving a file keeps its history,
  browsable by path. Storage and thinning rules in `LibraryCore`, tested with a fake
  clock.
  *Verify:* `mdcheck` cases with a fake clock: 5 saves of changed text within 2 minutes →
  at most 2 copies after 10 minutes; identical text twice → one copy; location switched
  off → none stored; delete the file → its copies still listed by path; the user's
  folder contains no extra files after all of this.

- [ ] **M4-14 — Local history: browse and restore.** File ▸ Revert To ▸ Local History…
  (and File list context menu for a closed file) opens a sheet listing the copies for the
  document with date and a preview of the text, plus a compare view against the current
  text. Restore replaces the document text as one undoable edit and keeps the replaced
  text as a snapshot. Works for files whose original is gone (restore creates a new file
  in a chosen folder). Switches from M4-13 are in Preferences ▸ General.
  *Verify:* edit and save a doc four times → the sheet lists the copies; pick an old one →
  preview shows it; Restore → editor has that text; ⌘Z returns the previous text; trash
  the file → History for that path still lists copies and Restore writes a new file.

- [ ] **M4-15 — Installable themes and templates.** A theme/template is a folder with a
  manifest in our own format: identifier, name, CSS, optional scripts, header and footer
  band heights, and the features it needs (maths, code highlighting, callouts, smart
  tables); a feature's runtime loads only if declared. Users install one by dropping a
  folder or `.zip` onto Preferences ▸ Preview (or the themes folder in Application
  Support), uninstall it, and duplicate a built-in to edit it. The themes folder is
  watched: editing, adding or removing a file reloads the preview with no restart. All
  assets are local; nothing is fetched from the network. The chosen theme is the global
  one from M4-8.
  *Verify:* drop a sample theme folder → it appears in the picker within 2 s and applies
  to the preview; edit its CSS → preview updates without restart; a theme without maths
  loads no maths runtime; offline, all declared features still render; uninstall →
  picker falls back to the default.

- [ ] **M4-16 — Writing systems: tradition and emphasis.** Preferences ▸ Editor ▸
  Language & Script: tradition = Default (follows the first preferred system language),
  Traditional Chinese, Simplified Chinese, Japanese, Korean. The tradition picks the
  language-tagged fallback font order for Han text, sets `lang` on the preview and export
  HTML, and sets the default emphasis style. Emphasis style = italic or emphasis marks
  (dots beside the characters), default italic for Latin and marks for the East-Asian
  traditions, overridable per tradition. In the editor `*word*` gets the chosen emphasis
  with the `*` characters kept dimmed; the preview and export use the same style. Mixed
  Latin and CJK paragraphs use per-script fallback so no glyph is missing. Applies to
  preview, export and print.
  *Verify:* Japanese → preview HTML has `lang="ja-JP"` and Han text uses a Japanese font;
  Japanese + marks → `*word*` shows marks beside the characters in editor and preview,
  `*` dimmed; switch to italic → italics; a mixed English/Chinese paragraph shows no
  tofu boxes; relaunch keeps the settings; `.md` bytes unchanged.

Exit criteria for M4: `aeris://open?path=…` opens a file; style check highlights
adverbs; the global theme switch persists across relaunch and applies to preview, export
and print; a text-size step and typeface change shows in editor and preview; Local
History restores an old version.
