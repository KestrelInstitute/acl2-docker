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

1. **allcerts image (primary).**  Dockerfile `allcerts` stage, after the
   regression RUN:
   - `COPY` the script into the image (same heredoc pattern as
     `certify-books-and-clean`), then
   - `RUN python3 xdoc_extract.py books/doc/manual books/doc/agent-corpus`
   - Cost: ~95 s build time, ~+0.45 GB image.  Same-layer placement as
     the regression RUN is NOT required (nothing is deleted), so a
     separate RUN keeps it cacheable and debuggable.
2. **Distribution artifact (serves kcerts, lean image, eval harness).**
   allcerts workflow step after the image push:
   `tar -C .../agent-corpus -cf - . | zstd` → ~38 MB, uploaded as a
   release asset named for the ACL2 commit (e.g.
   `xdoc-corpus-master-c492d30.tar.zst`), `--clobber` onto a rolling
   release plus the commit-named asset for pinning.
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

## Future work (explicitly deferred)

- Fidelity upgrade: regenerate bodies from xdoc's official text renderer
  (`rendered-doc-combined` machinery) behind the same format contract.
- Children links (index has parent idxs; corpus currently lists parents
  only — children can be derived and appended cheaply if agents want
  downward navigation).
- Per-book sub-corpora (e.g. kestrel-only extract for kcerts) if the full
  corpus's coverage-vs-size tradeoff ever matters.
- Upstreaming: the converter is general xdoc tooling; `books/xdoc/` may
  be its long-term home.
