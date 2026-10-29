# Aeris Writer

A free, native macOS Markdown editor. Plain `.md` files on disk, local-first, no
accounts.

## Status

Early development. Editor with live styling, live preview, formatting commands and a
library sidebar work today. Roadmap in `docs/PLAN.md`, tickets in `docs/TICKETS-*.md`,
architecture in `docs/ADR-001-appkit-primary.md`.

```
swift build            # build
scripts/bundle.sh debug && open "build/Aeris Writer.app"  # build and run the app bundle
swift run mdcheck      # verify the Markdown pipeline (works on Command Line Tools)
swift test             # full XCTest suite (needs full Xcode)
```

## Scope (what we're building)

- Plain-text Markdown editing with live syntax styling
- Local files + folder-based library/organizer
- Live HTML preview
- Export (Markdown / HTML / PDF) and a copy-format matrix
- Direct publishing to WordPress, Ghost, Micropub, Micro.blog

## Out of scope (deliberate differences)

- **No accounts / login / trials / subscription / payment gating.** This is a free app.
- No proprietary typography engine, templates marketplace, or any copied code,
  strings, icons, or visual design.

## Layout

- `docs/PRD.md` — product requirements for our app
- `docs/PLAN.md`, `docs/TICKETS-*.md` — roadmap and tickets
- `docs/ADR-001-appkit-primary.md` — architecture decision
- `Sources/MarkdownCore` — parsing, rendering, edit logic (no AppKit)
- `Sources/LibraryCore` — library listing, locations, refresh logic (no AppKit)
- `Sources/AerisEditor` — the AppKit app
- `Sources/mdcheck` — test runner that works with Command Line Tools

## License

MIT. See `LICENSE`.
