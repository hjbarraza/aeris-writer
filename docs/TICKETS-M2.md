# M2 — Library / organizer

Milestone goal: a sidebar over real folders on disk with favorites, tags, smart
folders and quick search; files change on disk → sidebar updates. Depends on M1.
Direct distribution, no sandbox (PLAN.md): store locations as plain bookmark data.

Legend: `[ ]` todo · `[x]` done. Keep `swift build` and `swift run mdcheck` green.

---

- [x] **M2-0 — Window shell.** `NSSplitViewController`: sidebar | editor | preview.
  Sidebar collapsible (⌘⌥S), state restored per window.
  *Verify:* toggle sidebar; relaunch → same layout.

- [x] **M2-1 — Library locations.** `Library` model: list of root folders ("Locations")
  stored as `URL` bookmark data in Application Support (no sandbox, so no
  security scoping needed). "Add Location…" open
  panel. Tree enumerated lazily (folders + `.md/.markdown/.txt`), shown in
  `NSOutlineView`.
  *Verify:* add a folder → its tree appears; relaunch → still there (bookmark resolves).

- [x] **M2-2 — Open from sidebar.** Click a file → opens in the editor (reuse window
  or tab); the sidebar selection follows the active document.
  *Verify:* click file A then B → editor shows B; ⌘S saves B; sidebar highlights B.

- [x] **M2-3 — Live refresh.** Watch each location with `FSEvents` (or
  `DispatchSource` per folder); coalesce; re-enumerate the changed subtree only.
  *Verify:* create/rename/delete a file in Finder → sidebar reflects it within 1 s.

- [ ] **M2-4 — File ops.** Context menu + File menu: New File, New Folder, New Folder
  with Selection, Duplicate, Rename (inline), Move to Trash (undoable via Finder),
  Reveal in Finder, Get Info. All through `FileManager` with file coordination.
  *Verify:* each op; trash is recoverable; open document survives a rename.

- [ ] **M2-5 — Auto-name new drafts.** New untitled doc gets its filename from the first
  non-empty line (sanitised) on first save; stops once the user renames.
  *Verify:* ⌘N, type `# My Post`, ⌘S → `My Post.md` suggested.

- [ ] **M2-6 — Favorites.** Pin files/folders to a *Favorites* group at the top.
  Persisted alongside locations.
  *Verify:* toggle favorite from context menu; relaunch → still favorited.

- [ ] **M2-7 — Hashtags.** `MarkdownCore.Hashtags.extract(text)` (tested: ignores
  headings `#`, code, URLs). Background indexer over the library; sidebar *Tags* group;
  clicking a tag lists matching files.
  *Verify:* `mdcheck` cases; add `#draft` to a file → tag appears → click → file listed.

- [ ] **M2-8 — Smart folders.** Saved query: text contains / tag / modified within.
  Editor sheet (SwiftUI leaf). Results are a virtual folder in the sidebar. Persisted.
  *Verify:* create "tag = draft AND modified < 7 days" → correct files; edit → updates.

- [ ] **M2-9 — Quick search (⇧⌘O; ⌘K is already Format ▸ Link).** Panel with fuzzy filename match + content search
  across all locations; arrow keys + Return to open. Index from M2-7 reused.
  *Verify:* ⌘K, type part of a name → file ranked first → Return opens it.

- [ ] **M2-10 — Sort & display options.** Sort by name / date modified / date created /
  extension, ascending/descending, pin folders to top, show/hide date, show/hide
  excerpt. Persisted.
  *Verify:* each option changes the list; relaunch keeps them.

- [ ] **M2-11 — Navigation history.** Two back/forward stacks: document history and
  library-browse history. Menu + ⌘[ ⌘].
  *Verify:* open A, B, C → back twice → A; browse folders X, Y → library back → X.

- [ ] **M2-12 — Native tabs.** `NSWindow.tabbingMode = .preferred`; "Open in New Tab",
  "Show All Tabs".
  *Verify:* ⌘T-style new tab holds a second document; tab bar merges windows.

- [ ] **M2-13 — Folder-wrapped documents.** A document may live as `Name/Name.md` with
  sibling images; image paths resolve relative to the folder in preview; drag-drop of
  an image into the editor copies it beside the file and inserts `![](img.png)`.
  *Verify:* drop a PNG → file copied, preview shows it.

Exit criteria for M2: add a folder, browse/create/rename/trash from the sidebar, see
`#tag` in Tags, a smart folder filters, ⌘K jumps to a file, a Finder change shows live.


## Fixes found in review (2026-10-29)

- [ ] **M2-14 — Library errors are visible.** If saving the library's location list fails,
  show an alert (not only a log line), and keep the in-memory list intact.
  *Verify:* make the library file's folder read-only, add a location → alert shown; list unchanged.
