# M5 — Optional / differentiators (only after M1–M4)

Take these only if they don't slow the core. Each is self-contained.

Legend: `[ ]` todo · `[x]` done.

---

- [ ] **M5-0 — Authorship model.** Per-range author attribution, hidden by default
  and stored in extended attributes, never in the `.md` unless the user runs Embed
  Authorship (M5-7). Use case: agents write first drafts as files and the owner edits them
  by hand in Aeris, so human vs AI attribution matters. Author id + kind (Human / AI /
  Reference). Mark selection as author; paste as author; colour per author in the editor,
  shown only when View ▸ Show Authorship is on. Each range stores a hash of its text so
  edits made in another app invalidate that range instead of mis-attributing it.
  *Verify:* mark a range as AI → tinted; save, reopen → tint restored; Show Authorship
  off → no tint; `.md` bytes clean; edit the file in another editor inside the range →
  that range loses its tint on reopen, the rest stays.

- [ ] **M5-1 — Authorship analytics.** Stats popover shows % of words by
  Human / AI / Reference. Counting in `MarkdownCore`, tested.
  *Verify:* fixture with known ranges → expected percentages.

- [ ] **M5-2 — Range annotations.** Comments attached to ranges, listed in an inspector.
  *Verify:* add a comment → appears in list → click jumps to range.

- [ ] **M5-3 — Content blocks (transclusion), including CSV/TSV.** `/path.md` on its own
  line embeds that file in preview and export. A `.csv` or `.tsv` path embeds as a
  Markdown table: delimiter detected from the first line, first row is the header, pipes
  in cells escaped, an optional caption renders as a figure caption. A data file with
  fewer than two rows shows an inline error in place of the table. CSV parsing in
  `MarkdownCore`, tested.
  *Verify:* preview shows embedded content; export inlines it; a 3-row CSV with a `|` in
  a cell → 3-row table with the pipe escaped; a TSV works the same; a 1-row file → inline
  error text; `mdcheck` cases for delimiter detection and escaping.

- [ ] **M5-4 — Scroll-synced PDF preview.** Preview mode showing paginated PDF with
  fit-page / fit-width.
  *Verify:* toggle PDF mode → pages render; zoom options work.

- [ ] **M5-5 — Content-block warnings.** When an embedded file (M5-3) is missing or
  can't be read, the preview toolbar shows a warning badge; clicking it lists each
  problem with its path. Export, print and publish ask Continue or Cancel first.
  *Verify:* embed a missing file → badge appears, its list names the path; Export →
  Continue/Cancel; Cancel writes nothing.

- [ ] **M5-6 — Paste as conversation.** When pasted plain text looks like a transcript of
  a chat with an AI assistant (speaker header lines such as the assistant's name, "AI",
  "User", "You"), offer Paste as Conversation (a pasteboard hint, never automatic):
  speaker headers are normalised to a fixed form on their own line, and each turn is
  attributed to an author, the user's Human author for user turns and an AI author for
  assistant turns (M5-0). Needs authorship on. Undo reverts text and attribution in one
  step. Detection and normalisation in `MarkdownCore`, tested.
  *Verify:* paste a two-turn transcript → offer appears; accept → two author-coloured
  ranges with normalised headers; ⌘Z removes both text and attribution; decline → plain
  paste, nothing attributed; `mdcheck` cases for several transcript shapes and for
  non-transcripts.

- [ ] **M5-7 — Embed and read embedded authorship.** File ▸ Embed Authorship writes the
  document's authorship into its front matter (M3-16): one key per author and one value
  per range with its length and hash. It runs only on that command, after a confirmation
  that says the `.md` will change, and is one undoable edit. File ▸ Read Embedded
  Authorship loads attribution from a front matter block written this way, for files that
  arrived through git, sync, zip or email without their xattrs; ranges whose hash no
  longer matches are dropped and counted in the result. Plain saves never write it, and
  Remove Embedded Authorship deletes just those keys.
  *Verify:* mark a range as AI → Embed → front matter holds the author and range, Undo
  removes it; copy the file elsewhere (no xattrs) → Read Embedded Authorship restores the
  tint; edit inside a range in another app first → that range is reported as dropped;
  normal ⌘S never adds front matter; `mdcheck` cases for write, read and hash mismatch.
