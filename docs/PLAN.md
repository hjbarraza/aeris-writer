# Development plan — aeris-md-editor

The single tracking doc. Milestones below; tickets live in one `docs/TICKETS-M*.md`
file per milestone. Run `scripts/status.sh` to see progress and validate the gates.

## How tracking works

- **One ticket at a time**, in file order. Flip `[ ]` → `[x]` only after its *Verify*
  step passes. The checkbox is the source of truth; no other tracker.
- **Every ticket has a Verify step.** Automated where possible (`mdcheck`, XCTest),
  manual otherwise (a concrete thing to do in the app and a concrete thing to see).
- **Every milestone has exit criteria** — a short acceptance script a human runs once
  on the built app. A milestone is done when every ticket is `[x]` *and* the exit
  script passes. Record the date next to the milestone when it does.
- **Always-green gates** (run before every commit; `scripts/status.sh` runs them):
  `swift build` · `swift run mdcheck`. On CI / full Xcode: `swift test` too.
- Pure logic goes in `MarkdownCore` with a test in **both** `mdcheck` and XCTest.
  UI behaviour is verified manually against the ticket's step.

## Milestones

| # | Milestone | Goal (one line) | Tickets | Exit criteria | Done |
|---|---|---|---|---|---|
| M1 | Core editor | Open, edit, style, preview, save a real `.md` | [TICKETS-M1](TICKETS-M1.md) | open a `.md` → edit with live styling → live preview → save: bytes clean, cursor restored on reopen | |
| M1.5 | Editor commands | Every editing command and writing behaviour: formatting, lists, tables, stats, completions, one Focus Mode (dimming + centring), line commands, auto-pairing | [TICKETS-M1.5](TICKETS-M1.5.md) | write a doc using only menu/shortcut commands: headings, lists, task list, table (size asked), link, image, footnote; stats correct for doc and selection; Focus Mode dims and centres in one toggle | |
| M2 | Library | Three-column window (organizer \| file list \| editor) over on-disk folders: excerpts, sort, filter, self-saving drafts, file ops, favorites, tags, smart folders, quick search inside files, backlinks and go-to-heading, import (Word, zip), history, tabs | [TICKETS-M2](TICKETS-M2.md) | add a folder → browse files with excerpts and dates; ⌘N in a folder saves itself there, no dialog; rename/trash/Get Info from the list; `#tag` in Tags; smart folder + Recents filter; ⇧⌘O finds text inside a file and jumps to it; Back/Forward; Finder change shows live | |
| M3 | Preview & export | Complete preview (show/hide, full size, two-way sync, extended syntax incl. maths, front matter, variables, citations, offline), then Markdown / HTML / PDF export, copy matrix, print — also from the library | [TICKETS-M3](TICKETS-M3.md) | extended-syntax fixture renders with Wi-Fi off; preview syncs both ways; export the same doc to `.md`, `.html`, `.pdf` and open each in another app; copy-as-HTML pastes into a browser; print preview renders; Export… from the library menu | |
| M4 | Polish | Prefs, one global theme and typography system (size steps, typefaces, writing systems), installable themes, style check, syntax settings, macOS Versions plus local snapshot history, URL scheme with consent | [TICKETS-M4](TICKETS-M4.md) | `aeris://open?path=…` opens a file after the consent prompt; style check highlights adverbs; global theme and text step persist and apply to preview, export and print; Local History restores an old version | |
| M5 | Optional | Authorship (hidden, in xattrs; optional embed in front matter), AI conversation paste, analytics, annotations, transclusion incl. CSV | [TICKETS-M5](TICKETS-M5.md) | only if M1–M4 are done; see file | |
| M6 | Publishing | Push a document as a *draft* to WordPress, Ghost, Micropub, Micro.blog (Medium, Substack P2) | [TICKETS-M6](TICKETS-M6.md) | add a WordPress account (token in Keychain) → Publish → draft appears on the site, nothing public; republish updates the same post | |

**Three-column library and full behaviour set (decided 2026-10-29).** H chose a
three-column window (organizer | file list | editor) and the full library feature set;
M2 was re-planned around it. Order inside M2 is *visible first*: the three-column shell
with a working file list (M2-4), then the organizer (M2-5), rows with excerpts (M2-6),
sorting (M2-7) and self-saving drafts (M2-8) — before file ops, index, tags, favorites,
smart folders, search, history and tabs. Focus Mode is one toggle for dimming and
centring (M1.5-12 replaces the separate typewriter toggle). Preview completeness moved
into M3 ahead of export, since export reuses the preview's HTML.

**Decisions of 2026-10-29 (H).** (1) Authorship is hidden by default and lives in
extended attributes; an explicit Embed Authorship command writes it into front matter
and Read Embedded Authorship loads it back (M5-0, M5-7); AI chat paste attributes turns
(M5-6). (2) Backups are both macOS Versions (M4-7) and our own local snapshot history in
app storage, thinned by age, per-location opt-out, with a restore UI (M4-13, M4-14).
(3) There is ONE global preview/export theme (M4-8), replacing the per-document plan;
typography is its own system (M4-12, M4-16, line length in M4-10).

**Publishing goes last (decided 2026-10-28).** The PRD puts it at M4; H moved it to
the end so the editor, library and export are solid before any network code. Nothing
in M1–M5 should depend on it.

**Note on M1.5.** PRD §5 lists five milestones, but the P0 editing commands in §4.3
(formatting, task lists, table editor, stats, typewriter/focus, autocomplete) belong to
none of them. M1.5 closes that gap so P0 work doesn't slip into "polish".

## Infrastructure tickets (do alongside M1)

These unblock validation itself. Tracked in [TICKETS-M1](TICKETS-M1.md) as `INF-*`.

- **INF-1 — App bundle.** SPM can't emit a `.app`; a script wraps the built binary with
  an `Info.plist` (document types, URL scheme, bundle id). Needed by M1-1.
- **INF-2 — CI.** GitHub Actions on a macOS runner: `swift build`, `swift run mdcheck`,
  `swift test`. This machine has CLT only, so CI is the only place XCTest runs.
- **INF-3 — Smoke-test fixtures.** `Tests/Fixtures/*.md` covering every node type we
  render; `mdcheck` and XCTest both read them.

## Decisions still open (and the ticket that forces each)

| Question | Forced by | Default if undecided |
|---|---|---|
| Word export library | M3-7 | Defer; P1 |
| Substack: Swift reimplementation vs bundled Python helper | M6-9 | Swift, cookie-authed, minimal endpoints |
| Draft file name: keep following the first line until the user renames (as planned), or fix it at first write | M2-8 | Follow until rename |
| Renaming a favorite renames the file on disk, or favorite labels are not editable | M2-19 | Renames on disk |
| Maths renderer to bundle (offline, licence-compatible) | M3-12 | Record in an ADR in-ticket |

Resolved: AppKit-primary (ADR-001) · WKWebView preview (ADR-001) · swift-markdown (ADR-001) ·
**Distribution = direct download, not Mac App Store** (decided 2026-10-28; no sandbox
constraints on folder access, Sparkle for updates later).

## Dependency order

```
INF-1 ─┐
M1 ────┼─▶ M1.5 ─▶ M2 ─▶ M3 ─▶ M4 ─▶ M5 ─▶ M6 (publishing, last)
INF-2 ─┘           (M3 only depends on M1; it can be parallelised
                    with M1.5/M2 if a second person joins; M3-13 and M3-15
                    need M2)
```

## Scope guard

Before taking any ticket, re-read the hard boundary (README, Out of scope): **no accounts,
login, trials, or payment gating**; **no copied code/strings/design**. A ticket that
needs either is wrong — fix the ticket, not the boundary.
