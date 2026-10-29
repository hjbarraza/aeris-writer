# Priorities (H, 2026-10-29)

Build order: every Must first, then Should, then Could. Within a tier, data safety first, then
what H asked for, then the rest. First pass by the decision model over every open ticket,
corrected by H's anchors (themes, PDF and authorship are Could; Substack and Hugo are the
publishing Musts). Done tickets are not listed.

## Must (daily driver) (35)

- M1-4 — Per-document metadata in xattrs
- M1-5 — Full HTML rendering in `MarkdownCore`
- M1-13 — Open any text file
- M1-16 — The self-check never touches the user's app state
- M1-18 — Our own link menu in the preview
- M1-19 — Rename everything to Aeris Writer
- M1.5-0 — Format menu + command router
- M1.5-1 — Inline commands
- M1.5-2 — Block commands
- M1.5-3 — Lists & task lists
- M1.5-23 — Renumber ordered lists
- M1.5-24 — Format toggles keep spacing and marker style
- M1.5-25 — Paste as Markdown from rich text
- M2-4 — Three-column shell with a working file list
- M2-5 — Organizer column (migrate the built sidebar)
- M2-6a — Relaunch returns to where you were
- M2-7 — Sort bar and view options
- M2-8 — New drafts save themselves into the folder
- M2-10 — File operations
- M2-13 — Locations: add, label, remove
- M2-14 — Library errors are visible
- M2-17 — Filter field
- M2-22 — Quick search: files
- M2-23 — Quick search: inside files
- M2-26 — Tabs
- M3-4 — Copy matrix (H: copy before export)
- M3-9 — Preview controls
- M4-7 — macOS Versions
- M4-13 — Local snapshot history: store and thinning
- M4-14 — Local history: browse and restore
- M6-0 — Publishing core
- M6-4 — Publish UI
- M6-13 — Publish to Substack
- M6-14 — Publish to a Hugo site
- M6-15 — Links between published notes (several publications, slug-built links)

## Should (soon after) (57)

- M1-7 — Editor↔preview scroll sync
- M1-11 — Preview links behave like a document, not a browser
- M1-14 — Caret at the end on first open
- M1.5-5 — Table editor, basic
- M1.5-7 — Autocomplete popup
- M1.5-8 — Typewriter mode
- M1.5-9 — Focus mode
- M1.5-10 — Spellcheck & text size
- M1.5-12 — Focus Mode: one toggle for dimming and centring
- M1.5-14 — Completions on demand
- M1.5-15 — Insert Table asks for its size
- M1.5-16 — Task checkboxes: Option-click and a keyboard toggle
- M1.5-17 — Inline math, Insert Date, Add Hashtag
- M1.5-18 — Line commands and structural move
- M1.5-19 — Tab key and indentation settings
- M1.5-20 — Auto-pair delimiters
- M1.5-21 — Completed tasks and wrapped list lines
- M1.5-22 — Open the link at the caret
- M2-6b — Every panel opens and closes smoothly
- M2-9 — Untitled documents named from their first line
- M2-12 — Drag and drop in the library
- M2-15 — Reveal in Library; move or copy into the library
- M2-16 — Library index
- M2-18 — Tags
- M2-19 — Favorites
- M2-20 — Smart folders: rules and results
- M2-21 — Smart folders: editor and management
- M2-24 — Completions and wikilinks across the library
- M2-25 — Navigation history
- M2-26a — Notes side by side
- M2-27 — Go menu
- M2-28 — Folder-wrapped documents and dropped files
- M2-29 — Linked from and Mentions
- M2-30 — Go to heading
- M3-0 — Export menu + save panel
- M3-1 — Markdown export
- M3-2 — HTML export
- M3-6 — Pre-export warnings
- M3-10 — Two-way scroll sync, with a setting
- M3-11 — Extended syntax: highlight, footnotes, callouts, comments, page break, TOC
- M3-13 — Wikilinks, hashtags and autolinks in HTML
- M3-15 — Export, print and copy from the library
- M3-16 — Front matter
- M3-17 — Variables
- M3-18 — Citations and reference links
- M4-0 — Preferences window
- M4-2 — Style check
- M4-4 — URL scheme
- M4-5 — Command palette
- M4-6 — Document outline
- M4-9 — Markdown syntax settings
- M4-10 — Editor layout and text-checking settings
- M4-12 — Typography: size steps, typefaces, line length
- M5-3 — Content blocks (transclusion), including CSV/TSV
- M5-5 — Content-block warnings
- M5-6 — Paste as conversation
- M6-12 — Publish from the library

## Could (later) (32)

- M1.5-4 — Live stats popover
- M1.5-11 — Completion list follows the editor
- M1.5-13 — Stats for the selection
- M2-11 — Get Info popover
- M2-31 — Import: Word documents and zip archives
- M3-3 — PDF export
- M3-5 — Print
- M3-7 — Word export (P1)
- M3-8 — Project archive (P2)
- M3-12 — Math
- M3-14 — Title page, headers and footers for print and PDF
- M4-1 — Preview themes
- M4-3 — Custom patterns
- M4-8 — One global preview theme and options
- M4-11 — URL commands: consent and more commands
- M4-15 — Installable themes and templates
- M4-16 — Writing systems: tradition and emphasis
- M5-0 — Authorship model
- M5-1 — Authorship analytics
- M5-2 — Range annotations
- M5-4 — Scroll-synced PDF preview
- M5-7 — Embed and read embedded authorship
- M6-1 — Accounts + Keychain
- M6-2 — WordPress, self-hosted
- M6-3 — WordPress.com
- M6-5 — Ghost
- M6-6 — Micropub
- M6-7 — Micro.blog
- M6-10 — Browser sign-in for self-hosted WordPress and Micropub
- M6-11 — Choose the blog
- M2-32 — Renaming a file updates the links to it
- M2-33 — Find and repair broken links

## Won't for v1 (2)

- M1-17 — New documents save as Markdown
- M1.5-6 — Table editor, full
