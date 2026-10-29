# M2 — Library / organizer

Milestone goal: a three-column library window — **organizer | file list | editor** (preview
beside or instead of the editor) — over real folders on disk, with favorites, hashtags,
smart folders, a filter field, quick search inside files, navigation history and tabs.
New drafts save themselves into the current folder. Files change on disk → every column
updates. Depends on M1. Direct distribution, no sandbox (PLAN.md): store locations and
favorites as plain bookmark data.

Legend: `[ ]` todo · `[x]` done. Keep `swift build` and `swift run mdcheck` green.

**Renumbered 2026-10-29** for the three-column design. The old M2-4…M2-13 are folded into
the tickets below (file ops → M2-10, auto-naming → M2-8/M2-9, favorites → M2-19, hashtags →
M2-18, smart folders → M2-20/21, quick search → M2-22/23, sort → M2-7, history → M2-25,
tabs → M2-26, folder-wrapped documents → M2-28). M2-14 keeps its number. Order is
"visible first": the three-column shell with a working file list lands before anything else.

**Window shape.** Organizer (left): sections *Locations*, *Favorites*, *Smart Folders*,
*Tags*. File list (middle): the contents of whatever the organizer has selected, with a
title bar (folder name, back/forward, "+" new-file button), a sort bar on top and a
filter field at the bottom. Editor (right), with the preview beside it.

---

## Built (one-tree sidebar) — what the three-column change means

- [x] **M2-0 — Window shell.** `NSSplitViewController`: sidebar | editor | preview.
  Sidebar collapsible (⌘⌥S), state restored per window.
  *Verify:* toggle sidebar; relaunch → same layout.
  *Three-column note:* M2-4 adds the file-list column between the sidebar and the
  editor. ⌘⌥S becomes "Hide Library" (organizer + file list together); a separate
  "Hide Organizer" hides only the left column. Layout restore extends to both widths.

- [x] **M2-1 — Library locations.** `Library` model: list of root folders ("Locations")
  stored as `URL` bookmark data in Application Support (no sandbox, so no
  security scoping needed). "Add Location…" open
  panel. Tree enumerated lazily (folders + `.md/.markdown/.txt`), shown in
  `NSOutlineView`.
  *Verify:* add a folder → its tree appears; relaunch → still there (bookmark resolves).
  *Three-column note:* the location store and bookmarks stay as built. The outline
  moves into the organizer's Locations section (M2-5); folder contents show in the
  file list instead of under the location row.

- [x] **M2-2 — Open from sidebar.** Click a file → opens in the editor (reuse window
  or tab); the sidebar selection follows the active document.
  *Verify:* click file A then B → editor shows B; ⌘S saves B; sidebar highlights B.
  *Three-column note:* the same open rules (read first, dirty-untitled prompt,
  already-open window comes forward) move to file-list rows (M2-4). "Selection follows
  the document" becomes a separate open-document marker (M2-6).

- [x] **M2-3 — Live refresh.** Watch each location with `FSEvents` (or
  `DispatchSource` per folder); coalesce; re-enumerate the changed subtree only.
  *Verify:* create/rename/delete a file in Finder → sidebar reflects it within 1 s.
  *Three-column note:* the watcher stays; its updates now feed the organizer and the
  file list (and later the index, M2-16). Live re-sort by date is in M2-7.

## Shell first

- [ ] **M2-4 — Three-column shell with a working file list.** Add the middle column:
  the existing sidebar stays on the left for now; selecting a folder in it shows that
  folder's files and subfolders in the file list (name only, current name order). A
  title bar shows the folder name. Clicking a file row opens it with M2-2's rules and
  moves keyboard focus to the editor; moving through rows with the arrow keys opens each
  file but keeps focus in the list. ⌘⌥S hides/shows organizer + list together; View ▸
  Hide Organizer hides only the left column. All three widths and both hidden states
  restore per window.
  *Verify:* select a folder → its files listed; click a file → it opens, typing goes to
  the editor; ↓ in the list → next file opens, focus stays in the list; Hide Organizer →
  list and editor remain; relaunch → same widths and visibility.

- [ ] **M2-5 — Organizer column (migrate the built sidebar).** Turn the one-tree
  sidebar into the organizer: sections Locations, Favorites, Smart Folders, Tags (the
  last three empty until their tickets). Locations show one row per location (display
  name, missing locations greyed); subfolders are navigated in the file list, not in
  the organizer. Existing "+", Add Location…, Remove from Library and refresh keep
  working. Sections start expanded and remember expansion. An empty section shows a
  one-line hint of our own wording (e.g. Favorites: "Drop files or folders here";
  Tags: "Type #tag in any file"). A stored setting can hide Favorites, Smart Folders
  and Tags individually (pane in M4-0; until then a View ▸ Organizer submenu).
  *Verify:* existing locations appear as organizer rows after upgrade, nothing re-added;
  select a location → its contents in the file list; collapse Tags, relaunch → still
  collapsed; hide Smart Folders → section gone, back after re-enabling and relaunch;
  empty Favorites shows its hint.

- [ ] **M2-6 — File list rows: excerpt, date, open marker.** Each file row shows the
  name (extension per a "show extensions" setting), a date on the right (time for
  today, "Yesterday", otherwise a short date) and up to two lines of excerpt: the text
  with Markdown removed (`MarkdownCore`, tested). An empty file reads "No text". A
  coloured bar at the row's leading edge marks the document open in this window,
  independent of the selection, so other rows can be selected without losing it.
  Excerpts are read off the main thread and cached by modification date.
  *Verify:* `mdcheck` cases for the excerpt (headings, emphasis, links, code, front
  blank lines, empty file); a file edited today shows a time, yesterday's shows
  "Yesterday"; select another row → open marker stays on the open file; a 2 000-file
  folder scrolls smoothly.

- [ ] **M2-6a — Relaunch returns to where you were.** On relaunch each restored window
  shows the same folder in the file list it showed at quit, with the same file
  selected, and the organizer keeps which folders were expanded. Works after a plain ⌘Q
  with macOS's default "close windows when quitting" setting: the state is stored by the
  app itself, not left to system window restoration. With no other window to restore, the
  last open document reopens. Stored per window
  as paths (no bookmarks needed: the location bookmark already resolves the root). A
  folder that no longer exists falls back to its location's root; a location that no
  longer resolves falls back to the first location.
  *Verify:* self-check: set folder + selection + expanded state, save the window
  state, restore into a fresh controller → same folder, selection, expansion; a
  deleted folder falls back to the root. On screen: open a subfolder, expand two
  folders in the organizer, quit, relaunch → same view.

- [ ] **M2-6b — Every panel opens and closes smoothly.** Showing or hiding the organizer,
  the file list and the preview animates the same way the sidebar toggle does, with no
  jump or flash, and the other columns keep their widths.
  *Verify:* self-check: each toggle ends at the expected widths and restores them when
  toggled back. On screen: toggle each panel → smooth, no flicker.

- [ ] **M2-7 — Sort bar and view options.** Sort by Date Modified, Date Created, Name,
  Extension; Newest/Oldest First (dates) or A→Z/Z→A (name, extension); Folders on Top;
  Show Date (Modified / Created / None); Show Excerpts; Navigation: **Tree** (folders
  expand inline in the list) or **List** (clicking a folder drills into it, back
  returns). The same options live in the sort bar's menu, View ▸ Sort By / View
  Options, and the list's context menu. Global for folder views; persisted. View ▸ Hide
  Sort Bar. A file whose date changes on disk re-sorts live. Defaults: Date Modified,
  Newest First, folders mixed, excerpts on, Tree.
  *Verify:* each key reorders rows; flip direction; Folders on Top → all folders above
  files at every level; List mode → click folder drills in, back returns; with Date
  Modified, edit a file in another app → it moves to the top within 1 s; relaunch keeps
  every option.

## Writing into the library

- [ ] **M2-8 — New drafts save themselves into the folder.** With a library folder
  shown, File ▸ New (⌘N) opens a draft that belongs to that folder. While untitled the
  window title follows the first line. When the name settles (Return after a non-empty
  first line, or the first autosave after typing pauses) the file is created in the
  folder with no dialog. Name = first line, cleaned (`MarkdownCore`, tested: heading,
  list and quote markers and inline Markdown removed, `/` and `:` replaced, trimmed,
  capped at 60 characters on a word boundary). A clash gets " 2", " 3", …; a missing
  folder is created. An empty draft is never written and closes without a prompt.
  The name is fixed once the file is first written; later edits to the first line never
  rename it (H, 2026-10-29). File ▸ New Untitled Document (⌥⌘N) is the classic flow. A setting picks
  which one ⌘N runs, and the default extension (`.md`; plain-text extensions only).
  *Verify:* `mdcheck` cases for the name cleaner; ⌘N in folder X, type `# My Post`,
  Return → `X/My Post.md` exists, no dialog; second draft with the same line → `My Post
  2.md`; change the first line after the first save → file name unchanged; ⌘N then
  close without typing → no file, no prompt.

- [ ] **M2-9 — Untitled documents named from their first line.** For a document that
  is not a library draft (⌥⌘N, or no folder shown): the window title follows the first
  line while untitled, and the save panel suggests that name (same cleaner as M2-8).
  *Verify:* ⌥⌘N, type `# My Post` → title "My Post"; ⌘S → panel suggests `My Post.md`.

## File operations

- [ ] **M2-10 — File operations.** Context menu on file-list rows and File menu: New
  File and New Folder (in the right-clicked folder, or the shown folder; the new row
  enters rename mode), New Folder with Selection (several rows selected), Duplicate
  ("Name copy", then "Name copy 2"), Rename (inline; name selected without extension;
  Return commits, Esc restores, empty or unchanged does nothing), Move to Trash (no
  prompt), and with Option held **Delete Immediately…** (confirmation naming the item,
  or the count when several), Show in Finder, Share ▸ (system share menu), Sort By ▸,
  View Options ▸. Multi-selection everywhere. All through `FileManager` with file
  coordination, off the main thread. Failures of a multi-item operation are collected
  into one alert sheet. An open document survives a rename or move.
  *Verify:* right-click a file inside a subfolder → New File → appears in that
  subfolder in rename mode; rename → Esc → old name, disk untouched; rename to "" → no
  change; Move to Trash → in Finder's Trash, no prompt; Option → Delete Immediately →
  confirmation → gone; trash 3 files where one is locked → one alert listing it, the
  other two trashed; rename the open file → editor keeps the document, title updates.

- [ ] **M2-11 — Get Info popover.** Get Info (context menu, File menu ⌥⌘I; ⌘I stays Italic) opens an
  in-app popover anchored to the row: icon or thumbnail, Name, Size, Extension, Date
  Created, Date Modified. Not Finder's window.
  *Verify:* Get Info on a file → popover with all six fields, values match Finder;
  click elsewhere → closes.

- [ ] **M2-12 — Drag and drop in the library.** Drag rows onto a folder (in the list or
  the organizer) to move them; Option-drag copies. Files dragged in from Finder are
  copied into the target folder (name clash → suffix). Errors use M2-10's batched sheet.
  *Verify:* drag a file onto a subfolder → moved; Option-drag → copied; drag a file
  from the Desktop onto the list → copied in, original stays.

- [ ] **M2-13a — Add locations by dragging folders or with Open.** Folders dragged from
  Finder onto the organizer are added as locations (the Locations section highlights);
  files are refused; a folder already present → nothing. The new location becomes the
  selected row and its contents show. File ▸ Open… accepts folders and adds them as
  locations; files open as before. The folder on disk is never touched (H, 2026-10-29).
  *Verify:* drop a folder → added once and selected, its files listed; drop it again →
  nothing; drop a file → refused; Open… with a folder and a file → folder added, file
  opened; the folder on disk is untouched.

- [ ] **M2-13 — Locations: add, label, remove.** A newly added location becomes the
  selected organizer row and its contents show. A folder dragged from Finder onto the
  Locations section is added (already present → nothing, no error). Rename Location
  sets a display name only (folder on disk untouched; clearing it restores the folder
  name; persisted). File ▸ Open… accepts folders too: choosing a folder adds it as a
  location (H, 2026-10-29). Remove Location from the context menu or the Delete key. Locations
  are listed in the Go menu (M2-27).
  *Verify:* add a folder → selected and shown; drag a folder from Finder onto Locations
  → added once, drag again → nothing; rename the label → disk unchanged, survives
  relaunch, clearing restores the folder name; Delete on a location → removed, folder
  untouched.

- [ ] **M2-14 — Library errors are visible.** If saving the library's location list fails,
  show an alert (not only a log line), and keep the in-memory list intact.
  *Verify:* make the library file's folder read-only, add a location → alert shown; list unchanged.

- [ ] **M2-15 — Reveal in Library; move or copy into the library.** File ▸ Reveal in
  Library selects the open document in the file list (switching folder or expanding as
  needed). A document opened from outside every location shows a slim bar in the window
  offering Move to Library (Option: Copy to Library) into the shown folder; File menu has
  the same two commands. Move keeps the document open with its undo history.
  *Verify:* collapse the open file's folder → Reveal in Library → row selected and
  visible; open a file from `/tmp` → bar appears → Move → file now in the shown folder,
  ⌘Z still undoes earlier edits; Option shows Copy → original stays in `/tmp`.

## Index, filter, tags, favorites, smart folders

- [ ] **M2-16 — Library index.** Background index of every Markdown/text file in all
  locations: name, path, dates, kind, plain text, headings (with level and offset),
  hashtags (`MarkdownCore`'s tag extractor) and outgoing references (links, wikilinks
  with their alias, images) with whether each target resolves to a file. Built off the
  main thread on launch, updated incrementally from the M2-3 watcher, saved to Caches so
  relaunch is fast. Pure query API in `LibraryCore`, tested with a fixture folder.
  *Verify:* `mdcheck` cases: index a fixture folder → expected files, headings, tags,
  references (including an aliased wikilink and an unresolved link); change one file →
  only that entry updates; a 5 000-file library indexes without blocking typing.

- [ ] **M2-17 — Filter field.** A field at the bottom of the file list (View ▸ Search
  Library, ⌥⌘F focuses it) filters the current view by name and content (index). Filter
  results keep their own sort and view options. Esc clears. View ▸ Hide Filter Bar.
  *Verify:* type a word that only appears inside one file's text → only that file
  listed; change sort while filtered → folder view's sort unchanged after Esc.

- [ ] **M2-18 — Tags.** The Tags section lists every tag in the library, A→Z, from the
  index. `#Draft` and `#draft` are one tag (shown as first seen). Clicking a tag shows
  the files containing it in the file list; tag views are part of library history
  (M2-25) and listed in the Go menu (M2-27). A tag disappears when no file uses it.
  *Verify:* add `#draft` to a file → tag appears within 2 s → click → only matching files;
  `# Heading`, `` `#code` ``, `http://x/#frag` → no tag; remove the last `#draft` → tag gone.
  *Tag rules:* a tag is `#` followed by letters, digits, `_` and joiners; `-` and `/` end it; a `#` right after a letter, digit or `&` is not a tag; headings (`# `) are never tags.

- [ ] **M2-19 — Favorites.** Add files or folders by dragging onto Favorites (inserted
  at the drop point) or with Favorite in the row context menu; reorder by drag. Stored
  as bookmarks, so they follow moves and renames. Shows the name without extension; a
  folder favorite shows its contents in the file list, a file favorite opens the file.
  Context menu: Reveal in Library, Show in Finder, Rename (renames the real file or
  folder on disk), Remove from Favorites. Delete key removes the favorite (file
  untouched). A favorite whose target is gone shows greyed with Remove offered.
  *Verify:* favorite a folder, rename it in Finder → favorite still works with the new
  name; drag a file onto Favorites at position 1 → inserted there; reorder → survives
  relaunch; Delete on a favorite → removed, file still on disk.

- [ ] **M2-20 — Smart folders: rules and results.** Rule model and evaluation in
  `LibraryCore` (tested), over the index. Rules: text contains, tag is, in folder,
  anywhere under folder, kind (Markdown file / plain-text file / folder), date created
  and date modified (before / after a date, or within the last N days, weeks or months).
  Groups combine with All or Any and nest. A result limit. Optional own sort and view
  options. Results show in the file list and update live as files change.
  *Verify:* `mdcheck` cases for each rule, All vs Any, nesting and limit; "tag = draft
  AND modified within 7 days" → correct files; edit a match so it no longer matches →
  gone within 1 s.

- [ ] **M2-21 — Smart folders: editor and management.** New Smart Folder… (organizer
  "+", Go menu) opens a sheet (SwiftUI leaf): name (trimmed; blank refused), a nested
  rule editor (the last rule can't be removed), limit, "use its own sort". Edit by
  double-click or context menu; Rename inline; Duplicate; Delete asks first; reorder by
  drag; persisted. First launch creates **Recents**: files modified in the last 30
  days, newest first, limit 50.
  *Verify:* first launch shows Recents with recent files newest first; create a folder
  with Any of two tags → union; add "under folder X" → only X's subtree; limit 5 → at most
  5; double-click → editor opens with the rules; Delete → confirmation; reorder → survives
  relaunch.

## Search and navigation

- [ ] **M2-22 — Quick search: files.** ⇧⌘O (Go ▸ Quick Search, toolbar button) opens a
  floating panel over the window. Typing ranks files across all locations by name
  (prefix, then word-start, then substring), each with its folder breadcrumb and the
  match highlighted. Arrows + Return open; Esc closes and returns focus to the editor.
  Extensions follow the "show extensions" setting.
  *Verify:* ⇧⌘O opens the panel, ⌘K still inserts a link; type part of a filename → that
  file first → Return opens it; Esc → focus back in the editor.
  *Ranking:* fuzzy on name and path, best match first, and drop the weakest tail of results instead of listing everything.

- [ ] **M2-23 — Quick search: inside files.** Results gain two groups. **This file**:
  matches in the open document with a snippet, "N more", and a Find and Replace action
  that hands the query to the editor's find bar. **Other files**: one header per file,
  then matching headings (with level) and text snippets, then "N more". A filter menu
  turns text and heading results on/off (persisted). Choosing a result opens the file
  and puts the caret on the match, scrolled into view; a file header can jump to the
  file's start or end.
  *Verify:* type a word in another file's heading → heading result under that file →
  Return opens it with the caret on the heading; This File group lists matches in the
  open document → Find and Replace opens the find bar with the query; turn off headings
  → only text results, still off after relaunch.

- [ ] **M2-24 — Completions and wikilinks across the library.** The completion list
  (M1.5-7) offers tags and files from the whole library index, not just the current
  folder. `[[Name]]` and `[[Name|shown text]]` (alias after a pipe) open the matching
  library file from the editor (⌘-click, ⌘-Return) and the preview; the alias is what
  the preview shows, the target is what resolves; a leading `/` is relative to the
  location root. A setting picks how new wikilinks and file links are written: shortest
  unique name, relative path, or path from the location root.
  *Verify:* type `[[` → files from other folders listed; ⌘-click `[[Other Note]]` in a
  different folder → opens it; `[[Other Note|see this]]` previews as "see this" and opens
  the same file; with "relative path" chosen, completing a file inserts `../sub/file.md`.

- [ ] **M2-25 — Navigation history.** **Document history:** Go ▸ Back ⌃⌘← / Forward
  ⌃⌘→, plus arrows by the document title; press-and-hold on an arrow lists the history.
  Entries follow renamed files and skip deleted ones. **Library history:** Go ▸ Back in
  Library / Forward in Library (arrows in the file-list title bar) record folder
  drill-ins and organizer selections (location, favorite, smart folder, tag). Go ▸
  Enclosing Folder (⌘↑ while the file list has focus). Two-finger swipe in the file list
  drives library back/forward. Both histories restore with the window on relaunch.
  (⌘[ / ⌘] are left for Indent/Outdent, M1.5-18.)
  *Verify:* open A, B, C → Back twice → A, Forward → B; rename B in Finder → Forward
  still reaches B; trash C → skipped; select folder X, tag #draft, folder Y → Back in
  Library → #draft, Back → X; relaunch → Back still works.

- [ ] **M2-26 — Tabs.** Native window tabs. Row context menu: Open in New Tab, Open in
  New Window; ⌘-click a row opens in a new tab, ⌥⌘-click in a new window. Opening a
  document already open in another tab selects that tab. The tab bar's "+" makes a new
  draft in the current folder (M2-8). View ▸ Show Tab Bar, Show All Tabs (⇧⌘\). Library
  and organizer widths stay in sync across the tabs of one window. A linked note (a click in
  the preview or ⌘-click in the editor) opens in a new tab of the same window, never a new
  window; new documents and File ▸ Open also prefer a tab (H, 2026-10-29).
  *Verify:* Open in New Tab → same window, new tab, first tab unchanged; open a file that
  is in tab 2 from tab 1 → tab 2 selected; tab bar "+" → draft in the current folder;
  drag the library divider in tab 1 → tab 2 matches; Window ▸ Merge All Windows works.

- [ ] **M2-26a — Notes side by side.** Show two notes next to each other in one window,
  each with or without its preview: View ▸ Open in Split (or ⌥-click a link or row), drag a
  tab onto the editor's edge to split; close a pane to go back to one. Each pane keeps its
  own cursor, undo and preview toggle; the library columns are shared (H, 2026-10-29).
  *Verify:* split with Other.md → two editors, typing in one leaves the other unchanged;
  preview off in one pane only; close the right pane → one editor, no document closed
  unsaved; relaunch restores the split.

- [ ] **M2-27 — Go menu.** Lists locations, favorites (⌃1…⌃9), smart folders (⌃⌥1…⌃⌥9)
  and tags; choosing one selects it in the organizer. Updates live as the lists change.
  *Verify:* ⌃1 shows the first favorite; ⌃⌥1 shows Recents; reorder favorites → ⌃1
  follows the new first; add a tag → appears in Go ▸ Tags.

## Documents with attachments

- [ ] **M2-28 — Folder-wrapped documents and dropped files.** A document may live as
  `Name/Name.md` with sibling images; image paths resolve relative to the document's
  folder in the preview. Dropping an image from outside copies it beside the document
  (clash → suffix) and inserts `![](img.png)` at the drop point; an image already in the
  document's folder is not copied, only referenced by relative path. Any other dropped
  file inserts a relative link. An untitled document says it must be saved first (or
  saves it, for a library draft) instead of silently dropping.
  *Verify:* drop a PNG from the Desktop → copied beside the file, reference inserted,
  preview shows it; drop an image already beside it → no copy; drop onto an untitled
  classic document → explanation, nothing inserted.

---

- [ ] **M2-29 — Linked from and Mentions.** A panel for the open file (View ▸ Show
  Links, in the inspector area) with two lists, both from the M2-16 index. **Linked
  from:** every file that links to this one by wikilink or relative link, each with an
  excerpt around the link; click opens that file at the match. **Mentions:** files whose
  name appears in this file's text as plain, unlinked prose (never the file itself), each
  with an excerpt and the match highlighted; a "Make link" button wraps the match as a
  wikilink in this file as one undoable edit. Lists update within 2 s of a change on disk.
  Nothing is written to any file unless Make link is pressed.
  *Verify:* A links to B → open B → A listed with excerpt; remove the link in A → A gone
  within 2 s; type B's name in prose in C → C appears under Mentions; Make link → the
  text becomes `[[B]]`, C moves to Linked from, ⌘Z restores; `mdcheck` cases for the
  index queries.

- [ ] **M2-30 — Go to heading.** Go ▸ Go to Heading (⌘⇧J): a fuzzy-search sheet over the
  headings of the current file, with a switch to search the whole library. Results show
  `File title` for current-file hits and `File#Heading` for library hits, with the
  matched letters emphasised; Return jumps to the heading (opening the file if needed),
  Esc closes. Fuzzy scoring in `LibraryCore`, tested.
  *Verify:* in a doc with an "Introduction" heading, type "intro" → it is first, Return
  scrolls there and moves the caret; switch to Library, type "plan" → heading in another
  file listed as `Other#Plan`, Return opens that file at it; `mdcheck` cases for scoring
  and ranking.

- [ ] **M2-31 — Import: Word documents and zip archives.** File ▸ Import… and dropping a
  `.docx` or `.zip` onto a library folder. A Word document becomes a new `.md` in the
  chosen folder (headings, paragraphs, bold and italic, links, bullet and numbered lists,
  tables as pipe tables, images copied beside it); the original is never modified and an
  existing file is never overwritten (name clash gets a suffix). A zip is extracted into
  a new folder named after the archive; unsafe paths (`..`, absolute) are refused. Our
  own converter, offline; the Word conversion lives in `MarkdownCore`, tested. Per-item
  failures are reported in one sheet (M2-10).
  *Verify:* import a sample `.docx` with a heading, a list, a table and an image →
  `.md` with matching structure and the image file next to it, source untouched; drop a
  zip with 3 notes → a folder with 3 files; a zip containing `../evil.md` → that entry
  refused and reported; `mdcheck` cases for the Word conversion.

Exit criteria for M2: the window shows organizer | file list | editor; add a folder →
browse its files with excerpts and dates, sort and filter them; ⌘N in a folder, type a
first line → the file appears there with no dialog; rename/trash/Get Info from the list;
`#tag` appears in Tags; a smart folder filters and Recents exists; ⇧⌘O finds a word
inside another file and jumps to it; Back/Forward work for documents and the library; a
Finder change shows live.
