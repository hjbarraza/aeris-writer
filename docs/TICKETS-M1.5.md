# M1.5 — Editor commands & writing tools

Milestone goal: every P0 editing command from PRD §4.3 works from the menu and a
shortcut. Depends on M1 complete. Each ticket is small and has a verify step.

Legend: `[ ]` todo · `[x]` done. Keep `swift build` and `swift run mdcheck` green.

---

- [ ] **M1.5-0 — Format menu + command router.** Add a *Format* menu. One
  `toggleInline(_:)` and one `toggleBlock(_:)` action on `EditorViewController`
  dispatching on a `MarkdownElement` enum; shortcuts ⌘B ⌘I ⌘K etc. Selection-aware:
  wrap selection, or insert empty markers and place the caret between them.
  *Verify:* select a word, ⌘B → `**word**`; ⌘B again → unwrapped.
  *(built 2026-10-29, verified headlessly; awaiting UI check.)*

- [ ] **M1.5-1 — Inline commands.** Bold, italic, highlight `==x==`, inline code,
  strikethrough, link `[x](url)`, image `![x](url)`, footnote `[^n]`, wikilink
  `[[x]]`, comment `<!-- -->`, clear styles. Pure range maths lives in `MarkdownCore`
  (`InlineEdit.toggle(...)`) with tests.
  *Verify:* `mdcheck` cases for each toggle (wrap / unwrap / empty selection); menu works.
  *(logic done 2026-10-29: InlineEdit in MarkdownCore. UI wiring built 2026-10-29
  (Format menu), verified headlessly; awaiting UI check. Clear styles (Format ▸ Clear
  Formatting) and link/image unwrap built 2026-10-29, verified headlessly; awaiting UI check.)*

- [ ] **M1.5-2 — Block commands.** Heading 1–6 (⌘1–6, toggles/replaces level), quote, *(logic done 2026-10-29: BlockEdit in MarkdownCore. UI wiring built 2026-10-29, verified headlessly; awaiting UI check.)*
  code block, callout/alert, display math `$$`, horizontal rule, page break, table of
  contents (generated from headings via `MarkdownCore`).
  *Verify:* ⌘2 on a line → `## `; ⌘2 again → removed; TOC lists every heading.

- [ ] **M1.5-3 — Lists & task lists.** List, ordered list, task `- [ ]`, ordered task. *(logic done 2026-10-29: ListEdit in MarkdownCore. UI wiring (menu, Return, Tab/⇧Tab) built 2026-10-29, verified headlessly; awaiting UI check. Source checkbox click built 2026-10-29, logic verified headlessly; awaiting UI check — the real mouse path could not be exercised with the screen locked.)*
  Return continues the list; Return on an empty item ends it; Tab/⇧Tab indents.
  Clicking a checkbox in the *source* toggles `[ ]`/`[x]`.
  *Verify:* type `- a` Return → `- ` auto-inserted; `- [ ]` Return → `- [ ] `; empty
  item Return → list ends; checkbox click flips state.

- [ ] **M1.5-4 — Live stats popover.** SwiftUI popover (via `NSHostingController`): *(logic + UI built 2026-10-29, verified headlessly; awaiting UI check.)*
  characters, characters without spaces, words, sentences, reading time, speaking
  time, tasks done/total. Counting in `MarkdownCore.TextStats`, tested. Choose which
  stat shows in the status bar.
  *Verify:* `mdcheck` fixture with known counts matches; popover updates while typing.

- [ ] **M1.5-5 — Table editor, basic.** Insert table; Tab/⇧Tab move between cells;
  add/delete row and column; reformat (align pipes). Table parsing/serialising in
  `MarkdownCore.TableEdit`, tested.
  *Verify:* insert 2×2 table, tab through cells, add a column, reformat → pipes aligned.
  *(logic done 2026-10-29: TableEdit in MarkdownCore. UI wiring (Format ▸ Table, Tab/⇧Tab)
  built 2026-10-29, verified headlessly; awaiting UI check.)*

- [ ] **M1.5-6 — Table editor, full.** Move rows/columns, column alignment, sort
  asc/desc, transpose, merge/unmerge cells.
  *Verify:* `mdcheck` cases for each operation on a fixture table.
  *(logic done 2026-10-29: TableEdit in MarkdownCore. UI wiring (Format ▸ Table) built
  2026-10-29, verified headlessly; awaiting UI check.)* Merge/unmerge
  not supported: GFM has no merged cells, so `TableEdit.merge`/`unmerge` return nil
  rather than inventing syntax.

- [ ] **M1.5-7 — Autocomplete popup.** While typing `#`, `[[`, or a path inside
  `](`, show a completion list (hashtags and files from the current folder for now;
  M2 widens it to the library). Esc dismisses, Return accepts.
  *Verify:* type `#` → list of tags in the doc; Return inserts.
  *(built 2026-10-29, verified headlessly; awaiting UI check.)*

- [ ] **M1.5-8 — Typewriter mode.** Keep the caret line vertically centred while typing
  and on caret moves. Menu toggle, persisted.
  *Verify:* enable, type to the bottom → caret stays centred; disable → normal. *(built 2026-10-29, verified headlessly; awaiting UI check.)*

- [ ] **M1.5-9 — Focus mode.** Dim everything except the current sentence or paragraph
  (scope selectable). Menu toggle, persisted.
  *Verify:* enable with scope = sentence → only the caret's sentence is full-contrast. *(built 2026-10-29, verified headlessly; awaiting UI check.)*

- [ ] **M1.5-10 — Spellcheck & text size.** Continuous spellcheck on by default
  (standard `NSTextView` checking); ⌘+ / ⌘− / ⌘0 text size, persisted.
  *Verify:* misspelled word underlined; ⌘+ enlarges; relaunch keeps size. *(built 2026-10-29, verified headlessly; awaiting UI check.)*

Exit criteria for M1.5: write a doc using only menu/shortcut commands — headings,
lists, a task list, a table, link, image, footnote — stats popover shows correct
counts, typewriter and focus toggle on/off. Then start M2.


## Fixes found in review (2026-10-29)

- [ ] **M1.5-11 — Completion list follows the editor.** The completion popup closes when the
  editor scrolls, loses focus, or the window changes; it never floats at a stale position.
  *Verify:* type `#ta`, scroll the editor → popup closes; click into the preview → popup closes.
