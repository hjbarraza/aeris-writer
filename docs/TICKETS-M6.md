# M6 — Publishing to the open web

Milestone goal: push the current document as a **draft** to WordPress first, then
Ghost, Micropub, Micro.blog, using their public APIs. Never an instant public post.
**Last milestone by decision (2026-10-28).** Depends on M1 + M3-2 (HTML payload). Credentials live in Keychain only.

Legend: `[ ]` todo · `[x]` done. Keep `swift build` and `swift run mdcheck` green.
Network clients are tested against a mock `URLProtocol`; request builders are pure
and unit-tested.

---

- [ ] **M6-0 — Publishing core.** `PublishTarget` protocol: `createDraft(post) → RemotePost`,
  `updateDraft(id, post)`, `uploadImage`. `PublishPayload` = HTML or Markdown (per
  account). `RemotePostMap`: local document ↔ (account, remote id), stored in the
  document's xattrs. All in a new `Publishing` target (no AppKit).
  *Verify:* unit tests for the map round-trip and payload selection.

  *Note (M1-5 review, 2026-10-29):* `MarkdownCore.html` passes raw HTML and
  `javascript:` URLs through unchanged, which is fine for the local preview. The
  publish payload must sanitise both before anything leaves the machine.

- [ ] **M6-1 — Accounts + Keychain.** `WebServiceAccount` (service, display name,
  endpoint, payload choice) in Application Support; secret in Keychain via
  `Security.framework` (no third-party wrapper). Preferences ▸ Publishing pane
  (SwiftUI leaf): add / edit / remove account; an empty state when there are none;
  rename inline; drag to reorder; remove asks first (it deletes a Keychain secret).
  Every sign-in sheet keeps its action button disabled until the inputs are valid (URLs
  need scheme, host and path), locks its fields while working, and on failure shows the
  error and unlocks them. Each sheet says plainly that Aeris creates drafts to review
  before publishing.
  *Verify:* add an account → entry in Keychain Access; remove → asks, then gone; rename and
  reorder → survive relaunch; `example.com` without a scheme keeps Add disabled; a wrong
  Ghost key → error, fields editable again.

- [ ] **M6-2 — WordPress, self-hosted.** WP REST API, application password (Basic).
  Create draft post (`status=draft`), upload media, update post.
  *Verify:* against a real site: Publish → draft appears in wp-admin, not public.

- [ ] **M6-3 — WordPress.com.** OAuth2 via `ASWebAuthenticationSession`; same REST
  calls through the `.com` endpoint.
  *Verify:* sign in → token stored → draft created on a `.com` blog.

- [ ] **M6-4 — Publish UI.** File ▸ Publish to ▸ (account). Sheet: title (from first
  H1), payload, tags; progress; result with "Open on site" link. Republish updates the
  mapped post instead of creating a new one. The Publish submenu is hidden when no
  account exists.
  *Verify:* publish twice → one remote draft, updated; remove all accounts → no Publish
  item in the File menu.

- [ ] **M6-5 — Ghost.** Admin API: Staff Access Token → JWT; create/update draft
  (`status: draft`); image upload.
  *Verify:* draft appears in Ghost admin.

- [ ] **M6-6 — Micropub.** Endpoint URL + token; `h-entry` with `post-status=draft`;
  media endpoint discovery.
  *Verify:* against a Micropub test endpoint, draft created.

- [ ] **M6-7 — Micro.blog.** Email magic-link sign-in, then Micropub to micro.blog.
  *Verify:* draft posted to a test Micro.blog account.
- [ ] **M6-8 (P2) — Medium.** Integration token; create draft via Medium API.
  *Verify:* draft appears on Medium.

- [ ] **M6-9 (P2) — Substack.** `WKWebView` login → read `substack.sid` cookie → minimal
  internal-endpoint client (create/put draft, upload image) + Markdown→ProseMirror
  converter in `MarkdownCore` (tested).
  *Verify:* draft appears in the Substack dashboard; paywall node survives re-read.

- [ ] **M6-10 — Browser sign-in for self-hosted WordPress and Micropub.** Self-hosted
  WordPress: after the site URL, Authorize opens the site's application-password
  approval page and the password returns through `aeris://`; manual username + app
  password stays available. Micropub: IndieAuth sign-in in the browser, returning
  through `aeris://`; manual token stays available.
  *Verify:* against a test WordPress site, Authorize → approve in the browser → account
  appears with no typing; against an IndieAuth test endpoint → account appears.

- [ ] **M6-11 — Choose the blog.** When an account has several blogs or publications
  (WordPress.com, Micro.blog, Medium), Publish asks which one, preselecting the last one
  used for that account.
  *Verify:* an account with two blogs → picker shows, choose B → draft on B; next
  publish preselects B.

- [ ] **M6-12 — Publish from the library.** The file list's context menu on a single
  text file has Publish ▸ (accounts), working without opening the file; hidden when no
  account exists. Needs M2-10.
  *Verify:* right-click a closed file ▸ Publish ▸ account → draft created, same flow as
  File ▸ Publish.

Exit criteria for M6: add a WordPress account (token in Keychain), Publish → draft on
the site, nothing public; republish updates the same post. Ghost/Micropub/Micro.blog
each pass their own ticket.

- [ ] **M6-13 — Publish to Substack.** Substack has no public posting API, so Aeris prepares the
  post for its editor: File ▸ Publish to ▸ Substack copies the document as rich text that
  Substack's editor keeps (headings, emphasis, links, lists, quotes, code, images as hosted
  or local files with a clear note), sets the title and subtitle from the first heading and
  subheading, and opens the publication's new-post page in the browser. Paid-content
  markers (a `[paywall]` line) become a visible reminder in the copied text. Never stores
  Substack credentials (H, 2026-10-29).
  *Verify:* a test document → pasteboard holds HTML with the expected elements and plain
  text fallback; title/subtitle taken from the first two headings; the browser opens the
  configured publication URL; on screen: paste into a Substack draft keeps formatting.

- [ ] **M6-14 — Publish to a Hugo site.** Settings: one or more Hugo sites (a folder with a
  Hugo config). File ▸ Publish to ▸ (site) writes the document into the site's content
  folder as a page bundle (`content/<section>/<slug>/index.md`) with front matter (title,
  date, draft, tags from #hashtags, description), copies local images next to it and
  rewrites their links, and never overwrites an existing post without asking. Optional:
  run the site's build or deploy command and show its output (H, 2026-10-29).
  *Verify:* publish a document with two images into a fixture site → bundle and front matter
  as expected, images copied and links rewritten, original document untouched; publish
  again → asks before replacing; build command output shown, failure shown as an error.

