# M4.5 — Agent / MCP Control (after M3, before M4)

Jev placement: stdio MCP is not network-adjacent like HTTP publishing; core APIs stable after M3; agent assistance for M4/M5/M6 is a force multiplier; rework bounded to window state & document model interfaces.

Legend: `[ ]` todo · `[x]` done.

---

- [ ] **M4.5-0 — MCP dependency & server skeleton.** Add `modelcontextprotocol/swift-sdk` to `Package.swift`. Create `MCPServer.swift` with stdio transport, capability negotiation (`tools/list`, `resources/list`), and lifecycle tied to `--mcp` flag in `main.swift`. Server starts only when `--mcp` passed; normal app launch unaffected.
  *Verify:* `swift build` succeeds; `AerisWriter --mcp` starts and responds to `initialize` + `tools/list` (empty) + `resources/list` (empty) via stdio; `AerisWriter` without flag starts normally.

- [ ] **M4.5-1 — Document tools.** Implement 4 tools in `MCPTools.swift`:
  - `open_document(path)` — opens .md at absolute path via `NSDocumentController`
  - `get_document_content(path?)` — returns `{text, path, encoding, modified}` for front doc or path
  - `set_document_content(text, path?)` — replaces front doc text in memory (no disk write)
  - `save_document(path?)` — saves front doc (or to path) to disk
  All tools respect `AppDefaults.isolated` (return `error: isolated` in self-check mode).
  *Verify:* MCP client calls each tool in sequence: open → get → set → get (shows new text) → save → file on disk matches; modified flag toggles correctly.

- [ ] **M4.5-2 — Library & search tool.** Implement `search_library(query, limit?)` in `MCPTools.swift` using `Library.searchForMCP`. Returns ranked results with `{path, score, excerpt, breadcrumb}`. Read-only — no library mutation.
  *Verify:* MCP client searches → returns results matching quick search behaviour; breadcrumbs correct; limit respected; empty query returns empty array.

- [ ] **M4.5-3 — Export tool.** Implement `export_document(format, path)` in `MCPTools.swift` reusing M3 export pipeline. Formats: `md`, `html`, `pdf`. Writes to absolute path.
  *Verify:* MCP client exports front document to each format → files open correctly in other apps; `md` round-trips; `html` renders; `pdf` opens in Preview.

- [ ] **M4.5-4 — Window state tools.** Implement `get_window_state()` and `set_window_state(state)` in `MCPTools.swift`. Add `windowState` getter/setter to `EditorWindowController`. State: `{bounds, splitPositions[], sidebarVisible, sidebarCollapsed}`.
  *Verify:* MCP client gets state → modifies bounds/splits/sidebar → sets state → window updates instantly; invalid state returns error.

- [ ] **M4.5-5 — Resources.** Implement 3 resources in `MCPResources.swift`:
  - `aeris://document/current` → front document text + metadata
  - `aeris://library/roots` → library locations tree
  - `aeris://window/state` → current window state
  All read-only; subscribe to changes via MCP notifications (optional, nice-to-have).
  *Verify:* MCP client reads each resource → returns current data; after document edit, `document/current` reflects change.

- [ ] **M4.5-6 — Self-check isolation & cleanup.** Ensure all tools return `error: isolated` when `AppDefaults.isolated`. Verify `--mcp` + `--selfcheck` combination works (MCP server runs but tools are no-ops). Clean shutdown: MCP server stops on app quit, stdio closes cleanly.
  *Verify:* Launch with `--mcp --selfcheck` → selfcheck passes; MCP tools return isolated errors; quit → no zombie processes.

- [ ] **M4.5-7 — Documentation & example client.** Add `docs/MCP.md` with: protocol overview, tool/reference, resource/reference, example Python/JS client script, integration notes for Claude Code / Cursor / custom agents.
  *Verify:* Example client script runs against `--mcp` app and demonstrates open/edit/save/search/export/window roundtrip.