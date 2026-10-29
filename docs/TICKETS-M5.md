# M5 — Optional / differentiators (only after M1–M4)

Take these only if they don't slow the core. Each is self-contained.

Legend: `[ ]` todo · `[x]` done.

---

- [ ] **M5-0 — Authorship model.** Per-range author attribution stored in xattrs
  (never in the `.md`): author id + kind (Human / AI / Reference). Mark selection as
  author; paste as author; colour per author in the editor.
  *Verify:* mark a range as AI → tinted; save, reopen → tint restored; `.md` bytes clean.

- [ ] **M5-1 — Authorship analytics.** Stats popover shows % of words by
  Human / AI / Reference. Counting in `MarkdownCore`, tested.
  *Verify:* fixture with known ranges → expected percentages.

- [ ] **M5-2 — Range annotations.** Comments attached to ranges, listed in an inspector.
  *Verify:* add a comment → appears in list → click jumps to range.

- [ ] **M5-3 — Content blocks (transclusion).** `/path.md` on its own line embeds that
  file in preview and export.
  *Verify:* preview shows embedded content; export inlines it.

- [ ] **M5-4 — Scroll-synced PDF preview.** Preview mode showing paginated PDF with
  fit-page / fit-width.
  *Verify:* toggle PDF mode → pages render; zoom options work.

- [ ] **M5-5 — Content-block warnings.** When an embedded file (M5-3) is missing or
  can't be read, the preview toolbar shows a warning badge; clicking it lists each
  problem with its path. Export, print and publish ask Continue or Cancel first.
  *Verify:* embed a missing file → badge appears, its list names the path; Export →
  Continue/Cancel; Cancel writes nothing.
