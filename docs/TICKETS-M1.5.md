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
  *Replaced by M1.5-12:* the separate Typewriter toggle goes away; its centring code
  becomes half of Focus Mode. Tick this together with M1.5-12.
  *Verify:* enable, type to the bottom → caret stays centred; disable → normal. *(built 2026-10-29, verified headlessly; awaiting UI check.)*

- [ ] **M1.5-9 — Focus mode.** Dim everything except the current sentence or paragraph
  (scope selectable). Menu toggle, persisted.
  *Changed by M1.5-12:* Focus becomes one toggle for dimming and centring together.
  Tick this together with M1.5-12.
  *Verify:* enable with scope = sentence → only the caret's sentence is full-contrast. *(built 2026-10-29, verified headlessly; awaiting UI check.)*

- [ ] **M1.5-10 — Spellcheck & text size.** Continuous spellcheck on by default
  (standard `NSTextView` checking); ⌘+ / ⌘− / ⌘0 change the text size, persisted. Interim
  behaviour: M4-12 replaces the free point size with a stepped scale and these shortcuts
  then move one step.
  *Verify:* misspelled word underlined; ⌘+ enlarges; relaunch keeps size. *(built 2026-10-29, verified headlessly; awaiting UI check.)*

Exit criteria for M1.5: write a doc using only menu/shortcut commands — headings,
lists, a task list, a table (size chosen in the dialog), link, image, footnote — stats
popover shows correct counts for the document and for a selection; Focus Mode toggles
dimming and centring together. Then start M2.


## Fixes found in review (2026-10-29)

- [ ] **M1.5-11 — Completion list follows the editor.** The completion popup closes when the
  editor scrolls, loses focus, or the window changes; it never floats at a stale position.
  *Verify:* type `#ta`, scroll the editor → popup closes; click into the preview → popup closes.


## Focus Mode as one toggle (H, 2026-10-29)

- [ ] **M1.5-12 — Focus Mode: one toggle for dimming and centring.** View ▸ Focus Mode
  turns on both the dimming (M1.5-9) and caret centring (M1.5-8); the Typewriter Mode
  item is removed. View ▸ Focus Scope: Sentence, Paragraph, Typewriter (centring with
  no dimming). Choosing a scope turns Focus Mode on. Turning it on centres the caret at
  once. Scrolling by hand lifts the dimming and pauses centring until the next caret
  move or keystroke. After a mouse click moves the caret, centring follows after a short
  delay (about 0.3 s) instead of jumping. No centring during live resize or a
  full-screen transition. One app-wide setting, persisted. Upgrade: a saved
  "typewriter on, focus off" becomes Focus on with scope Typewriter.
  *Verify:* Focus off → View ▸ Focus Scope ▸ Paragraph → Focus on, paragraph scope,
  caret centred; scroll with the trackpad → all text full contrast; press → → dimming
  back and caret recentred; click a line near the bottom → it glides to centre; scope
  Typewriter → centred, nothing dimmed; relaunch keeps mode and scope; the View menu
  has no Typewriter Mode item.

## Editor commands and behaviour added 2026-10-29

- [ ] **M1.5-13 — Stats for the selection.** With text selected, the stats bar and
  popover count only the selection and say so ("Selection: 12 words"). Deselect →
  document totals return. Recomputed off the main thread after a short pause.
  *Verify:* select one sentence of five → words and sentences show that sentence's
  counts, labelled as a selection; click to deselect → totals back; `mdcheck` case for
  counting a substring.

- [ ] **M1.5-14 — Completions on demand.** Esc with no list showing opens completions
  at the caret (tags after `#`, files after `[[` or `](`, otherwise nothing); Esc with
  the list showing closes it. Home and End jump to the first and last item. After an
  accept the list closes.
  *Verify:* type `#ta`, Esc closes the list, Esc again reopens it; End → last item
  selected; Return inserts and the list is gone.

- [ ] **M1.5-15 — Insert Table asks for its size.** Format ▸ Table ▸ Insert Table…
  shows a small sheet for body rows and columns (minimum 1×1, maximum 50×20), defaulting
  to the last size used. A Compact / Padded setting decides how Reformat writes pipes
  (padded aligns columns, compact uses single spaces); default Padded.
  *Verify:* insert 3×4 → 3 body rows, 4 columns; next Insert Table defaults to 3×4;
  Compact → Reformat leaves `| a | b |` without padding; `mdcheck` cases for both styles.

- [ ] **M1.5-16 — Task checkboxes: Option-click and a keyboard toggle.** Option-click on
  a source checkbox places the caret inside the box without toggling. Format ▸ Toggle
  Task (⌃⌘X) flips the task(s) at the caret or in the selection: if any is open, all
  become done; otherwise all become open. One undo step.
  *Verify:* Option-click `[ ]` → text unchanged, caret inside the brackets; ⌃⌘X on an
  open task → `[x]`; select two tasks, one done → both done; ⌘Z restores both.

- [ ] **M1.5-17 — Inline math, Insert Date, Add Hashtag.** Format ▸ Inline Math toggles
  `$…$` (wrap / unwrap / empty markers, like the other inline commands). Insert ▸ Date
  inserts today's date (ISO `yyyy-MM-dd`). Format ▸ Add Hashtag inserts `#` at the caret
  (adding a space before it when needed) and opens the tag completion list.
  *Verify:* `mdcheck` cases for inline-math toggling; Insert Date on 2026-10-29 →
  `2026-10-29`; Add Hashtag mid-word → ` #` and the tag list opens.

- [ ] **M1.5-18 — Line commands and structural move.** Format ▸ Indent (⌘]) and Outdent
  (⌘[) for any lines (lists keep their marker rules from M1.5-3); Edit ▸ Move to Previous /
  Next Sentence. Move Line Up / Down (⌥⌘↑ / ⌥⌘↓) moves the caret line or selected lines,
  caret and selection following, and is structure-aware: on a list item it moves the item
  together with all its nested children as one unit, recomputing depth, marker and
  numbering so nesting stays valid and ordered lists renumber from their start number; a
  paragraph, code block or heading section moves whole; inside a block quote the `>`
  prefix is kept; at the edge of a container the item stops (it never leaves its list or
  quote). The commands are disabled when no move is possible. Range maths in
  `MarkdownCore`, tested.
  *Verify:* plain lines: Move Line Down on line 2 of 3 swaps lines 2 and 3, caret stays on
  the moved text. Ordered list `1. a / 2. b (with child) / 3. c`: Move Down on `b` →
  `1. a / 2. c / 3. b` with `b`'s child still under it; Move Up on the first item is
  disabled; in a quote each moved line keeps `> `; Indent on a plain paragraph line →
  indented; ⌘Z undoes each; `mdcheck` cases.

- [ ] **M1.5-19 — Tab key and indentation settings.** Settings: indent with tabs or
  spaces, tab width, indent width, list indentation (to the marker's width or the indent
  width), and what Tab does outside lists and tables (insert a tab/spaces, or indent the
  line). Shift-Tab always outdents. A Restore Defaults button. Pane in M4-0; stored now.
  *Verify:* choose spaces, width 4 → Tab on a plain line inserts four spaces; choose
  "indent line" → Tab mid-line indents the whole line; Restore Defaults → tab character.

- [ ] **M1.5-20 — Auto-pair delimiters.** Options to auto-insert the closer for brackets
  `( [ {`, quotes `" '`, and Markdown markers `*`, `_`, `` ` ``, `~`, `=`. Typing the closer over
  an auto-inserted one steps over it; Backspace right after removes both. With a
  selection, typing an opener or marker wraps the selection. Default: brackets on,
  quotes and markers off.
  *Verify:* type `(` → `()` caret between; type `)` → one `)`; select `word`, type `*` with
  markers on → `*word*`; options off → nothing inserted; `mdcheck` cases for the rules.

- [ ] **M1.5-21 — Completed tasks and wrapped list lines.** A completed task line is
  drawn dimmed and struck through (each switchable). Wrapped lines of a list item hang
  under the item's text, not under the marker (setting: hang to the marker width, a
  fixed indent, or off).
  *Verify:* `- [x] done` looks visibly different from `- [ ] open`; a long bullet's
  second visual line starts under the text; neither changes the file's bytes.

- [ ] **M1.5-22 — Open the link at the caret.** ⌘-Return opens the link at or next to
  the caret, with the same rules as ⌘-click (M1-11). Holding ⌘ over a link shows the
  pointing-hand cursor; a plain click only moves the caret.
  *Verify:* caret inside `[x](https://example.com)` → ⌘-Return opens the browser; hold ⌘
  over the link → pointer changes; click without ⌘ → caret moves, nothing opens.

- [x] **M1.5-23 — Renumber ordered lists.** Return in the middle of an ordered list renumbers
  the items below it, so a list never shows duplicate numbers; deleting an item renumbers too.
  Empty list items and markers are plain text only: never insert invisible placeholder
  characters into the document.
  *Verify:* in `1. a / 2. b / 3. c`, Return after `a` → `1. a / 2. / 3. b / 4. c`; delete
  line 2 → `1. a / 2. b / 3. c`; the saved file contains no zero-width characters.

- [ ] **M1.5-24 — Format toggles keep spacing and marker style.** Bold, italic, strike,
  highlight and code toggles read the selection as off / on / mixed: off applies the
  marker pair, on removes it, mixed applies it to the unmarked parts. Leading and trailing
  whitespace of the selection stays outside the markers. Toggling off removes only that
  span's markers, and an existing marker style (`_x_`, `__x__`) is preserved instead of
  being rewritten to `*`. Logic in `MarkdownCore`, tested.
  *Verify:* select ` word ` (with spaces) → ⌘B gives ` **word** `; `_x_` selected, ⌘I
  removes the underscores and ⌘I again writes the marker chosen in M4-9; a selection
  half in bold applies bold to the rest; `mdcheck` cases for each.

- [ ] **M1.5-25 — Paste as Markdown from rich text.** Edit ▸ Paste as Markdown (and a
  setting to make plain Paste do it for rich-text sources) converts rich text on the
  pasteboard to Markdown: paragraphs, bullet and numbered lists (nesting kept), tables
  (as pipe tables with a header row), links, bold and italic. Plain-text pastes are never
  altered. Conversion in `MarkdownCore`, tested.
  *Verify:* copy a 2×2 table from a web page → Paste as Markdown writes a pipe table;
  copy a nested list from a rich-text app → `- ` / `1. ` list with matching nesting; plain
  paste of plain text is byte-identical; ⌘Z undoes the paste in one step; `mdcheck` cases.

- [ ] **M1.5-26 — Every list edit keeps the numbering honest.** Outdent (⇧Tab), a Backspace
  that removes indentation, paste into a list and the list toggles renumber a sequential
  ordered list the same way Return and delete do (M1.5-23); lists numbered on purpose stay
  as they are.
  *Verify:* `1. a / 1. x (nested) / 2. b`, outdent x → `1. a / 2. x / 3. b`; paste two items
  into the middle of a sequential list → renumbered; `1. / 1. / 1.` list → unchanged.

