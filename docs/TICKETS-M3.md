# M3 — Preview, export, copy, print

Milestone goal: a complete preview (show/hide, full size, two-way scroll sync, every
syntax the editor inserts rendered), then get a document out as Markdown, HTML, PDF; copy
as Markdown/HTML/rich text; print — from the editor and from the library. All free,
ungated and offline. Depends on M1 (preview HTML pipeline); the library items need M2.

Legend: `[ ]` todo · `[x]` done. Keep `swift build` and `swift run mdcheck` green.

Order: the preview tickets (M3-9…M3-13) come first, because export reuses their HTML.

---

## Preview

- [x] **M3-9 — Preview controls.** View ▸ Show/Hide Preview (persisted per window);
  Split / Full size (Full hides the editor; Split restores it); View ▸ Reload Preview.
  The preview only renders while visible and renders at once when shown. An empty
  document shows a centred, quiet placeholder line. The page's `lang` follows the
  document's language (detected with NaturalLanguage), so hyphenation and quotes match.
  The preview's context menu has no browser navigation or reload items.
  *Verify:* hide the preview → relaunch → still hidden; Full → editor gone, Split → back;
  empty document → placeholder; a French document → `<html lang="fr">`; right-click the
  preview → no Back/Reload.

- [ ] **M3-10 — Two-way scroll sync, with a setting.** Scrolling the preview moves the
  editor to the same source line, as the editor already moves the preview (M1-7). The
  preview also follows caret moves while typing. When the preview is shown it starts at
  the editor's position. A setting turns sync off (default on). No feedback loops: the
  pane being scrolled by the user leads.
  *Verify:* scroll the preview to a heading → the editor shows that heading's line; move
  the caret down with arrows past the visible preview → preview follows; sync off →
  neither pane moves the other; no jitter while scrolling either pane.

- [ ] **M3-11 — Extended syntax: highlight, footnotes, callouts, comments, page break,
  TOC.** `MarkdownCore.html` renders `==x==` as `<mark>`, footnotes as numbered
  references with a back-linked list at the end, callouts/alerts (`> [!NOTE]` etc.) as
  styled boxes, `<!-- comments -->` hidden, page breaks as a print page break, and the
  table-of-contents marker as a linked list of headings (heading ids from M1-11).
  Applies to preview, export, copy and print.
  *Verify:* a fixture with each syntax → `mdcheck` asserts the HTML; the preview shows a
  highlight, a clickable footnote, a coloured callout and a working TOC; PDF export
  breaks the page at the page-break marker.
  *Rules:* `{{TOC}}` makes a table of contents only when it is alone in its paragraph; a line of `===` on its own is a page break (print/PDF), invisible in the preview.

- [ ] **M3-12 — Math.** Inline `$…$` and display `$$…$$` render as typeset maths in
  the preview and every export, fully offline: a bundled maths renderer (open-source,
  licence-compatible, recorded in an ADR) produces static markup before the page loads,
  so page scripts stay off. Invalid TeX shows the source in an error style, never a
  blank.
  *Verify:* `$e^{i\pi}+1=0$` and a display matrix render with Wi-Fi off; exported HTML
  shows the same maths in Safari; `$\frac{$` shows an error-styled source.

- [ ] **M3-13 — Wikilinks, hashtags and autolinks in HTML.** `[[Name]]` renders as a
  link that opens the library file (M2-24) in the preview; `#tag` renders as a tag span;
  bare URLs autolink. Settings choose, separately for the preview and for other output
  (copy, export, publish), how wikilinks render (link / plain text / span), hashtags
  (span / plain text) and autolinks (link / plain text). Pane in M4-0.
  *Verify:* `mdcheck` cases for each setting; click `[[Other]]` in the preview → opens
  it in Aeris; exported HTML with "wikilinks as plain text" has no `<a>` for them.
  *Rules:* `[[Name|Label]]` shows Label, `[[Name]]` shows the file name without extension; a hashtag links to a library search for that tag.

## Export, copy, print

- [ ] **M3-0 — Export menu + save panel.** File ▸ Export… with a format popover
  (`ExportFormat` enum: markdown, html, pdf; word/archive added later). `NSSavePanel`
  with the right extension, the name prefilled from the document, extension visible.
  One `Exporter` protocol, one type per format. A line under the format popup explains
  the choice (for PDF: page size comes from File ▸ Page Setup). The last format used is
  remembered across launches. Failures show as a sheet on the window.
  *Verify:* menu shows; choosing a format changes the suggested extension and the info
  line; export as PDF, relaunch, Export… → PDF preselected.

- [ ] **M3-1 — Markdown export.** Write the document text; if folder-wrapped, copy
  referenced images beside it.
  *Verify:* exported `.md` is byte-identical to the source; images present.

- [ ] **M3-2 — HTML export.** Standalone `.html`: `MarkdownCore.html` + the preview
  theme CSS inlined, images either relative or base64 (option). Template shared with
  the preview pane (one source of truth in `MarkdownCore/Templates`).
  *Verify:* open the `.html` in Safari → matches the preview pane.

- [ ] **M3-3 — PDF export.** Render the export HTML in an off-screen `WKWebView` →
  paginated PDF, using the paper size and orientation from File ▸ Page Setup (no
  separate size options to build).
  *Verify:* `.pdf` opens in Preview.app; headings, code, table paginate sanely, long code
  blocks and tables don't clip; Page Setup A4 → Letter is reflected in the next export.

- [ ] **M3-4 — Copy matrix.** Edit ▸ Copy as Markdown / HTML / Rich Text / Plain Text, each
  for the selection, or the whole document when nothing is selected. Rich text via
  `NSAttributedString(html:)` on the export HTML. Plain Text is the rendered text with all
  Markdown removed (headings, emphasis, link URLs, list markers kept as readable bullets).
  Pasteboard gets *only* the chosen type (plus plain text). More important than export
  (H, 2026-10-29).
  *Verify:* Copy as HTML → paste in a browser form shows markup; Copy as Rich Text →
  paste in Pages shows formatting; Copy as Markdown → plain source; Copy as Plain Text →
  no `#`, `*`, `[]()` left; nothing selected → whole document.

- [ ] **M3-5 — Print.** File ▸ Print: formatted (via the preview web view) and plain
  text (via `NSTextView`); both support print-to-PDF from the system dialog.
  *Verify:* ⌘P shows the formatted doc; "Print plain text" shows the source.

- [ ] **M3-6 — Pre-export warnings.** `MarkdownCore.Links.extract` (tested) → check
  local image/link targets exist; show a sheet listing broken ones before export.
  *Verify:* reference a missing image → export warns, lists the path, lets you continue.

- [ ] **M3-7 — Word export (P1).** `.docx` via a maintained Swift lib or our own minimal
  OOXML writer from the AST. Decide in-ticket; record the choice in an ADR.
  *Verify:* `.docx` opens in Pages/Word with headings, lists, bold/italic intact.

- [ ] **M3-8 — Project archive (P2).** Zip of the folder-wrapped document. Pick a
  maintained zip lib.
  *Verify:* archive unzips to the original folder.

- [ ] **M3-14 — Title page, headers and footers for print and PDF.** Settings: an
  optional title page (title from the document title, author name from the document's
  author or else settings, date), a header (document title) and a footer (page number
  "n / total"). The header and footer band heights are settings and can be overridden per
  document by front matter (M3-16). Apply to Print and PDF export, not the live preview.
  *Verify:* enable all three → exported PDF page 1 is the title page, every other page
  has the title on top and "n / total" at the bottom; disable → plain pages.

- [ ] **M3-15 — Export, print and copy from the library.** The file list's context menu
  (single text file) gains Export…, Print ▸ (Formatted / Plain Text) and Copy ▸
  (Markdown / HTML / Rich Text / File Path / Aeris Link — an `aeris://open?path=` URL),
  all working without opening the file in the editor. Needs M2-10.
  *Verify:* right-click a closed file ▸ Export… ▸ PDF → PDF written, no editor window
  opened; Print ▸ Plain Text prints the source; Copy ▸ Markdown pastes the whole file;
  Copy ▸ Aeris Link pasted into Terminal `open "…"` opens the file.

- [ ] **M3-16 — Front matter.** A leading `---` … `---` (or closing `...`) block of
  `key: value` lines is recognised as metadata. Keys compare case-, punctuation- and
  hyphen-insensitively (`Header Height`, `header-height`, `Header_Height` are one key); a
  value may continue on following lines indented two spaces. The editor draws the block
  de-emphasised; the preview and exports leave it out of the body. `title` is the export
  title (HTML `<title>`, PDF title, publishing title) and `author` the PDF author; with no
  `title` the file name is used. `header-height` and `footer-height` override the band
  heights of M3-14. Aeris never creates or changes a front matter block unless the user
  runs an explicit command (M5-7 is the only one planned). Parser in `MarkdownCore`,
  tested.
  *Verify:* `mdcheck` cases: block with `---`/`...` closers, folded value, key
  normalisation; file with a block → editor shows it in secondary colour, preview shows
  only the body; export PDF with `title: A` and `author: B` → document properties show A
  and B, without `title` → the file name; `footer-height: 60` → taller footer band; open
  and close the file → `.md` bytes unchanged.

- [ ] **M3-17 — Variables.** `{{key}}` in the body is replaced in the preview and in
  every export by the value of the matching front matter key (same key normalisation as
  M3-16); a missing key renders as empty text; the source file is unchanged. Lookup order:
  the document's own keys, then a user-editable list of global values (Preferences ▸
  Markdown: add, edit, remove key/value pairs, stored in app preferences, never in a
  file). Can be switched off in M4-9's syntax settings.
  *Verify:* `title: A` and body `{{title}}` → preview and PDF show A; add global
  `company: X` → `{{company}}` shows X in any document; a document key of the same name
  wins; `{{nope}}` renders nothing; switch off → literal text shows; `mdcheck` cases.

- [ ] **M3-18 — Citations and reference links.** Inline citation `[@key]` (optional
  locator, `[@key, p. 4]`) with a definition line `[@key]: text` anywhere in the
  document. In the preview and exports a citation becomes a parenthetical link to its
  definition; a citation with no definition is visibly marked as missing. Reference-style
  links (`[text][label]` with `[label]: url "title"`) render as links, and the editor
  dims definition lines and markers. Citations can be switched off in M4-9's syntax
  settings. The syntax is ours, documented in the PRD. Parsing in `MarkdownCore`, tested.
  *Verify:* one defined and one undefined citation → one working link, one marked;
  `[text][docs]` with a definition links correctly; switch citations off → literal
  text; `mdcheck` cases.

Exit criteria for M3: the preview hides, goes full size, and syncs both ways; a fixture
with highlight, footnotes, maths, a callout and a TOC renders in the preview with Wi-Fi
off; export one doc to `.md`, `.html`, `.pdf` and open each in another app; Copy as HTML
pastes into a browser; print preview renders; Export… works from the library's context
menu.
