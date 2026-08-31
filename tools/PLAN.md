# xdoc Agent Corpus — Implementation & Deployment Plan

Companion to [DESIGN.md](DESIGN.md).

## Pipeline

One script, one pass, no dependencies beyond Python 3 stdlib:

```
xdoc_extract.py MANUAL_DIR OUT_DIR
  1. Load xindex.js  -> key -> (displayName, UPPERNAME, short-html)
  2. Load xdata.js   -> key -> (parents, source, package, long-html)
  3. Build natural-name map (DESIGN.md "Natural names") from 1+2
  4. For each topic: render long-html + short-html to corpus text
     (DESIGN.md rendering table), write topics/KEY.txt
  5. Write index.tsv (sorted by natural name) and AGENT-README.md
  6. Print statistics (topic count, sizes, dangling-link count)
```

Memory note: step 2 `json.loads` of the 380 MB file peaks around 3 GB;
fine at image-build time (the build machine just ran a regression) and in
a 7 GB sandbox.  If that ever becomes a constraint, the bracket-matching
streaming scan (prototyped 2026-08-30) drops peak memory to ~0.5 GB.

## Deployment targets

1. **allcerts image (primary) — IMPLEMENTED.**  Dockerfile `allcerts`
   stage, after the regression RUN: `COPY tools/xdoc_extract.py` (admitted
   by a `.dockerignore` exception) then
   `RUN python3 xdoc_extract.py books/doc/manual books/doc/agent-corpus`.
   Cost: ~90 s build time, ~+0.4 GB image.  A separate RUN (cacheable,
   debuggable); same-layer placement with the regression is not needed
   because nothing is deleted.
2. **Distribution artifact — IMPLEMENTED** (serves kcerts, lean image,
   eval harness).  The allcerts workflow's `publish-corpus` job pulls the
   pushed image on a GitHub-hosted runner, extracts
   `books/doc/agent-corpus`, and uploads `zstd -19` tarballs (~21 MB) to
   the rolling `xdoc-corpus` release: a commit-stamped asset
   (`xdoc-corpus-master-XXXXXXX.tar.zst`) for pinning plus
   `xdoc-corpus-latest.tar.zst`, both `--clobber`ed.  Requires
   `contents: write` workflow permission.
   Eval harness: vendor one tarball; no network, no tools, done.
3. **acl2-mcp (optional convenience).**  A `xdoc_search`/`xdoc_show` tool
   pair that shells out to grep over a corpus dir if configured; the
   `acl2-doc-lookup` skill updated to prefer a local corpus when present.
   Strictly a wrapper — agents without it use grep directly.

## Relationship to the "doc session" (complementary layer)

For authoritative, current-world queries (`:doc` of just-defined topics,
`:pe`/`:props`/theory queries over everything), acl2-mcp can host a
dedicated long-lived session that includes `doc/top` (allcerts only;
measured ~57 s / ~3 GB).  Policy: never in the working session; lazy-start
on first request or eager-start in background.  The corpus answers
instantly meanwhile.  Not part of this deliverable; noted so the two
layers stay designed as a pair.

## Verification checklist (run after any converter change)

- [ ] Topic count matches xdata entry count; zero unwritten topics.
- [ ] `rg -c "____"` over topics/ bodies ≈ only dangling-link keys
      (report count; expect small).  v1 had 2.32 M mangled links.
- [ ] FTY accessor names render with `->` (e.g. grep `vl-descriptionlist->names`
      hits both index.tsv and its own topic file).
- [ ] Surviving `&[a-z]+;` entity count is small and legitimately literal
      (the XDOC____ENTITIES topic documents entities and must display
      them; a blind second decode pass is intentionally NOT done).
      xdoc's supported set is documented in the `xdoc::entities` topic.
- [ ] Link rewriting applied to index.tsv shorts as well as bodies
      (v1 leaked `[COMMON-LISP____NUMERATOR]`-style keys into shorts).
- [ ] Spot-read: one plain function (bvplus), one macro with rich docs
      (defbitstruct or define), one math topic (rtl), one title topic
      (a workshop/notes page); confirm legibility.
- [ ] index.tsv line count == topic count; `grep -i` latency still ~ms.
- [ ] Record sizes (topics/, index.tsv, tar.zst) in DESIGN.md history.

## Upstream Lisp implementation (the `make manual` version)

The long-term home for corpus generation is xdoc itself, run as part of
building the manual, replacing the Python HTML back-conversion with
xdoc's own rendering pipeline.  Findings from reading
`books/xdoc/display.lisp` (the renderer behind terminal `:doc` and
`rendered-doc-combined.lsp` / acl2-doc.el) that shape this:

- **The pipeline already exists.**  `display.lisp` does exactly
  preprocess → parse-xml token stream → text.  A corpus emitter is a new
  *back end* over the same token stream, not a new renderer.  Notably,
  the official renderer already made two of this design's decisions
  independently: it un-mangles topic names, and it preserves link targets
  when display text differs (as `text (see [topic])` — required because
  acl2-doc.el navigates by the literal bracketed text).
- **The delta is small and enumerable.**  Terminal conventions → corpus
  conventions: indented code blocks → ``` fences; `<v>` as ANSI
  black-on-white (terminal) or plain text (rendered file) → backticks;
  `text (see [topic])` → `[text](topic)`; plain header lines → `#`
  headers.  Everything else (entity decoding, img/icon dropping, math
  passed plain) already matches.
- **Natural names are even easier in Lisp.**  Topics carry their name
  symbol and `:base-pkg`; printing the name relative to the ACL2 package
  gives the package-elided natural form directly — no unmangling and no
  xindex join needed.
- **Integration point: `save-fancy`,** which already iterates every topic
  with preprocessed content in hand to emit `xdata.js` — the corpus can
  be emitted in the same loop at near-zero marginal preprocessing cost.
  Gate it the way `rendered-doc-combined.lsp` is gated (an environment
  variable in the style of `ACL2_DOC_GENERATE_SUPPORTING_FILES`, or a
  `:corpus-p` option to `xdoc::save`), so builders who don't want it
  don't pay for it.
- **Contract test.**  DESIGN.md's format table is the spec.  Validate the
  Lisp emitter by running both implementations against the same built
  manual and diffing a broad sample of topic files; then the Python
  converter is demoted to a fallback for ACL2 refs predating the feature
  (image builds of old commits still work).
- **Ownership.**  This needs xdoc-maintainer buy-in; propose as
  `books/xdoc/save-corpus.lisp` (or an extension of save-fancy) with the
  DESIGN.md contract attached.

## Future work (explicitly deferred)

- Children links (index has parent idxs; corpus currently lists parents
  only — children can be derived and appended cheaply if agents want
  downward navigation).
- Per-book sub-corpora (e.g. kestrel-only extract for kcerts) if the full
  corpus's coverage-vs-size tradeoff ever matters.
