# M1 — Core editor (actionable tickets)

Milestone goal: open, edit, and save a real `.md` file, with live Markdown styling and
a working HTML preview. Each ticket is small and has a verify step. Do them in order.

Legend: `[ ]` todo · `[x]` done. Keep `swift build` and `swift run mdcheck` green.

---

- [x] **M1-0 — Buildable skeleton.** SPM package, `MarkdownCore` on swift-markdown,
  AppKit app opening one window with an `NSTextView`, `mdcheck` smoke test.
  *Verify:* `swift build` succeeds; `swift run mdcheck` prints "mdcheck passed". ✅ done.

- [x] **M1-1 — `NSDocument` document model.** Replace the hardcoded window with an
  `NSDocument` subclass (`MarkdownDocument`) + `NSDocumentController`, registered for
  `.md`/`.markdown`/`.txt` (UTType `net.daringfireball.markdown`, `public.plain-text`).
  Read/write plain UTF-8. Hook up the standard File menu (New/Open/Save/Save As).
  *Verify:* launch, ⌘N, type, ⌘S to a `.md` file, reopen it — content round-trips.
  Also closes INF-1: `open -a build/Aeris.app some.md` opens that file in a window.
  Requires adding an app menu + `Info.plist` document types (document the Xcode-project
  vs SPM-resources approach you choose). *Chosen: SPM only, no Xcode project —
  `scripts/bundle.sh` copies `Resources/Info.plist` into `build/Aeris.app`; the menu is
  built in code (`MainMenu.swift`). `open -a` needs an absolute app path on this macOS.*

- [x] **M1-2 — Editor view object.** Extract the `NSTextView` into an
  `EditorViewController` owning the text storage, wired to the document's content
  (two-way). Monospaced, plain text, 24pt insets, soft-wrap.
  *Verify:* edits update the document (dirty state ⌘S works); no rich-text pasteboard.

- [x] **M1-3 — Live Markdown styling.** *(revision 1 verified headlessly; in-app recheck of fence typing pending.)* On text change, parse with `MarkdownCore` and
  apply `NSAttributedString` attributes for headings, bold, italic, inline code, links,
  lists — styling the *source* text in place (in-place styling), not replacing it. Debounce /
  incremental: re-style only affected paragraphs (see architecture map §3).
  *Verify:* typing `# H` enlarges the line; `**x**` bolds; stays responsive on a long doc.

- [ ] **M1-4 — Per-document metadata in xattrs.** Store/restore cursor + scroll
  position in extended file attributes on save/open (never in file content).
  *Verify:* reopen a file — caret and scroll are where you left them; the `.md` bytes
  are unchanged (diff shows no added front-matter). *(built 2026-10-29, verified headlessly; awaiting UI check.)*

- [ ] **M1-5 — Full HTML rendering in `MarkdownCore`.** Extend the AST→HTML walker to
  cover the rest of CommonMark + GFM we need: code blocks, block quotes, links, images,
  tables, task lists, thematic breaks. Add XCTest cases per node type.
  *Verify:* `swift run mdcheck` (extend it) + `swift test` on Xcode/CI all green. *(mdcheck green 2026-10-28; XCTest pending CI, INF-2.)*

- [x] **M1-6 — `WKWebView` preview pane.** Split view: editor left, `WKWebView` right
  rendering `MarkdownCore.html(text)` wrapped in a themeable HTML template (light/dark
  CSS). Update on edit (debounced).
  *Verify:* type Markdown, see it render live; dark mode follows system.

- [ ] **M1-7 — Editor↔preview scroll sync.** *(built 2026-10-29, verified headlessly; awaiting UI check.)* Keep the preview roughly aligned to the
  editor's visible range as you scroll/type.
  *Verify:* scrolling the editor moves the preview to the matching section.

### Infrastructure (unblocks validation; do alongside M1)

- [x] **INF-1 — App bundle script.** `scripts/bundle.sh`: wraps the `swift build`
  binary into `build/Aeris.app` with an `Info.plist` (bundle id, document types for
  `.md/.markdown/.txt`, `aeris://` URL scheme). `swift run` stays the fast path.
  *Verify:* `scripts/bundle.sh && open build/Aeris.app` launches; Finder opens a
  `.md` with it.

- [ ] **INF-2 — CI.** *(workflow file written 2026-10-29; needs a GitHub remote + push from H.)* `.github/workflows/ci.yml` on `macos-latest`: `swift build`,
  `swift run mdcheck`, `swift test`. This is the only place XCTest runs today.
  *Verify:* green check on a pushed commit.

- [x] **INF-3 — Fixtures.** `Tests/Fixtures/*.md`, one per node type we render;
  `mdcheck` and XCTest both load them so the two suites can't drift.
  *Verify:* `swift run mdcheck` reports one line per fixture.

Exit criteria for M1: open a real `.md`, edit with live styling, see live preview,
save (content clean, cursor restored). Then start M2 (library/organizer).

---

## Follow-ups decided by H (2026-10-29)

- [x] **M1-8 — Auto-detect text encoding.** Opening a non-UTF-8 file (e.g. Latin-1 /
  Windows-1252 `.txt`, UTF-16 with BOM) detects the encoding instead of refusing.
  Save writes back in the same encoding, so the file is never silently re-encoded.
  Detection lives in `MarkdownCore` (pure, tested); `MarkdownDocument` uses it.
  *Verify:* mdcheck cases for UTF-8, UTF-8 BOM, UTF-16 LE/BE BOM, Windows-1252 with
  accents; open a Latin-1 file → text correct; edit, save → `file -I` still reports the
  original charset and bytes outside the edit are unchanged.
  Save As always writes UTF-8 (H, 2026-10-29).

- [x] **M1-9 — Smart punctuation in the preview.** Render `"quotes"` → “quotes”,
  `'` → ’, `--` → –, `---` → —, `...` → … (swift-markdown smart opts on). The `.md`
  source is never changed. Code spans and code blocks stay literal.
  *Verify:* update fixtures; mdcheck asserts curly quotes in prose and straight quotes
  inside `code`.

- [x] **M1-10 — External changes to the open document (H, 2026-10-29).** When another
  app or process changes, replaces, moves or deletes the file of an open document,
  Aeris detects it (NSFilePresenter via NSDocument: `presentedItemDidChange`,
  `presentedItemDidMove`, `accommodatePresentedItemDeletion`, comparing the file
  modification date and contents so our own saves never trigger it) and shows a
  window-modal sheet:
  - **Reload** replaces the editor text with the version on disk (undoable, caret kept
    near its old position).
  - **Ignore** keeps the editor text. The next save writes it over the disk version
    without NSDocument's "changed by another application" error, because the user
    already chose.
  When the document has unsaved edits, the sheet says so, and Reload warns those edits
  will be lost.
  Note: the system may reload an unedited document silently by default; that path must
  also ask, and our current reload clears undo history, so Reload must be built so ⌘Z works.
  Autosave must never re-create a file that was deleted on disk without the user choosing Keep. Several changes while the sheet is up collapse into one prompt. A move
  or rename follows the file silently (title updates). A deletion asks
  Keep (re-save on next save) / Close. Never auto-reload without asking, and never
  lose the user's text without an explicit Reload.
  *Verify:* self-check with a temp file: an external write fires exactly one prompt,
  and our own ⌘S/autosave fires none. Reload → text matches disk, ⌘Z restores the old
  text. Ignore → disk unchanged until save, then save writes ours with no error sheet.
  Two quick external writes → one prompt. On screen: edit the file in another editor
  while it is open in Aeris.
  *Status 2026-10-29: built and verified headlessly; awaiting the on-screen step.*

## Fixes found in review (2026-10-29)

- [ ] **M1-11 — Preview links behave like a document, not a browser.** `#heading` links
  scroll the preview to that heading (headings get stable ids); links to other `.md` files
  open them in Aeris; only http(s)/mailto go to the system. Editor: ⌘-click on a link opens
  it the same way.
  *Verify:* a document with a table of contents → click an entry → preview scrolls there, no
  Finder window opens; a link to `other.md` opens it in Aeris.

- [x] **M1-12 — Line endings stay consistent.** In a CRLF document, Return and every edit
  command insert CRLF, so a file never ends up with mixed endings.
  *Verify:* open a CRLF file, add lines with Return and list continuation, save → every line
  ends in CRLF (`od -c`).

## Added 2026-10-29

- [ ] **M1-13 — Open any text file.** A file with no extension or an unknown one (e.g.
  `README`, `notes.text`) opens as text when its bytes decode cleanly with M1-8's
  detection (no lossy decoding). Empty files open. RTF and binary files are refused
  with a clear message and no half-open window.
  *Verify:* open a UTF-8 file named `README` → opens as text; open a PNG renamed to
  `x.text` → refused with a message, no window left behind; open an empty file → empty
  document.

- [ ] **M1-14 — Caret at the end on first open.** A file with no stored caret (M1-4)
  opens with the caret at the end of the text, scrolled into view. If the stored caret
  was at the very end, it stays anchored to the end: a file that grew since reopens
  with the caret at the new end.
  *Verify:* open a file never opened before → caret at the end; put the caret at the
  end, close, `echo more >> file.md`, reopen → caret after "more"; `cmp` shows the file
  bytes unchanged by opening.


- [x] **M1-15 — The preview never navigates on its own.** The preview loads only the HTML
  Aeris renders for it. Every other navigation is cancelled: forms, meta refresh, iframes or
  embeds pointing elsewhere, and any `file:` page. In-page `#anchor` moves are allowed.
  Link clicks keep M1-11's rules. A `file:` link with a host other than empty or `localhost`
  is ignored. In an unsaved document, a relative link (`other.md#x`) is ignored instead of
  scrolling the current page.
  *Verify:* render `<iframe src="https://example.com">`, `<meta http-equiv="refresh"
  content="0;url=https://example.com">` and a `<form action>`: the preview stays on our page
  and makes no network request. `file://host/x.md` → ignored. Unsaved doc, ⌘-click
  `other.md#x` → nothing happens.

- [ ] **M1-16 — The self-check never touches the user's app state.** `--selfcheck` runs
  against its own preferences domain and its own window state, so running it (by hand or by
  any agent) never changes the user's column widths, collapsed sections, last folder or
  open documents. It also never hangs: each check that waits has a timeout and reports
  which check stopped.
  *Verify:* `defaults export com.aeris.editor` before and after a self-check run → byte
  identical; a self-check run while the app is open leaves the open app's layout unchanged
  after its next relaunch.

- [ ] **M1-17 — New documents save as Markdown.** Saving an untitled document offers `.md`
  by default (not `.txt`); the format pop-up still allows `.markdown` and `.txt`.
  *Verify:* ⌘N, type, ⌘S → the save panel proposes `Untitled.md`; save → the file on disk
  ends in `.md`.

- [ ] **M1-18 — Our own link menu in the preview.** Right-clicking a link in the preview shows
  Aeris's menu instead of WebKit's, so every item works. A link to a note: Open, Open in
  New Tab, Open in New Window, Reveal in Finder, Copy Link. A web or mail link: Open in
  Browser (or Mail), Copy Link. An `#anchor`: Jump to Section, Copy Link. WebKit's own
  items that can't work in a locked-down preview (Open Link in New Window, Download Linked
  File) never appear. Selected text keeps Copy and Look Up (H, 2026-10-29).
  *Verify:* self-check builds the menu for each link kind and runs every item: Open → the
  note opens in this window; Open in New Tab → same window, one more tab; Open in New
  Window → a second window; Copy Link → the pasteboard holds the absolute URL; no item is
  a no-op. On screen: right-click each link in `aeris-link-test/Start.md`.

