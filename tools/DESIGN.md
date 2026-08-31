# xdoc Agent Corpus — Design

Status: v2 draft, 2026-08-30.
Companion documents: [PLAN.md](PLAN.md) (implementation & deployment),
`xdoc_extract.py` (implementation), `AGENT-README.md` (shipped inside the
corpus, teaches agents the query patterns).

## Problem

Agents (Claude Cowork sessions, LLM eval harnesses, CLI assistants) need to
look up ACL2/xdoc documentation **locally and fast**.  Standard online lookup is
excluded: the manual site is a JavaScript SPA (fetches return an empty shell).
SEO-optimized online lookup is sometimes possible, but is often disabled due to
excessive hacking attempts, Cowork sandboxes often cannot reach acl2.org, and,
besides all that, eval harnesses are deliberately air-gapped.

The raw material is the built web manual (`books/doc/manual/`), a free
byproduct of certifying `doc/top` (present in the `acl2-allcerts` Docker
image).  Two files matter:

- `xdata.js` (~380 MB, one line): `{KEY: [parents, source, package,
  long-html], ...}` for ~77,000 topics.  NOTE: shorts are NOT here.
- `xindex.js` (~13 MB): `[[KEY, displayName, UPPERNAME, parentIdxs,
  short-html], ...]`.  Display strings are HTML-escaped (FTY accessor
  names like `foo->field` appear as `foo-&gt;field`).

Neither is directly agent-friendly: single-line JSON is hostile to line
tools, per-query parsing costs seconds and GBs, and the HTML bodies waste
tokens and poison grep results with markup.

## Design principles

1. **No tooling required.**  The corpus must be fully usable with only
   `ls`, `grep`/`rg`, and file reads — the lowest common denominator of
   agent harnesses.  Any CLI or MCP tool on top is a convenience, not a
   dependency.
2. **Speak the agent's native languages.**  Content is Markdown-flavored
   plain text; names are in ACL2's own register (`bvplus`,
   `fty::defbitstruct`), not xdoc's URL-mangled keys.  LLMs have deep
   priors on Markdown, Lisp, and LaTeX; they have none on
   `FTY____DEFBITSTRUCT`.
3. **Token economy.**  The corpus is read by token-metered models.
   Measured on the 2026-08-29 manual: 2.32 million cross-reference links;
   rewriting `[ACL2____FOO-BAR]` to `[foo-bar]` saves roughly 4 tokens per
   link (~9M tokens corpus-wide, concentrated in the hub topics agents
   read most).
4. **Information-preserving rendering.**  "Rendered" means token-efficient,
   not lossy.  Cross-reference targets, code blocks, and math source
   survive; only markup overhead is removed.
5. **Docs and code cannot skew.**  The corpus is generated during the
   image build from that build's own manual, so it documents exactly the
   books in the image (stamped by the image tag, e.g. `master-c492d30`).

## Corpus layout

```
agent-corpus/
  AGENT-README.md      # how to query (for agents; ~30 lines)
  index.tsv            # one topic per line: natural-name \t KEY \t short
  topics/
    ACL2____BVPLUS.txt # one file per topic, named by xdoc KEY
    FTY____DEFBITSTRUCT.txt
    ...
```

File names use the xdoc KEY (filesystem-safe on every OS; some topics are
prose titles that aren't symbols).  Everything *inside* files and the
index uses natural names.  `index.tsv` is the bridge: grep the natural
name, read the KEY column, open the file.

## Natural names

For topic KEY with `xindex` symbol name UPPER and `xdata` package PKG:

- name = lowercase(html-unescape(UPPER))     ; e.g. `vl-descriptionlist->names`
- natural = name                              if PKG is ACL2 or COMMON-LISP
          = lowercase(PKG) "::" name          otherwise (`apt::tailrec`)
- Topics whose UPPER is not symbol-like (contains spaces — chapter/title
  topics) use the display name verbatim, unqualified.

This requires no reverse-engineering of xdoc's `_XX` name mangling: the
un-mangled name and package are both present in the source data.

## Topic file format

```
# bvplus
Key: ACL2____BVPLUS | Package: ACL2
Source: kestrel/bv/doc.lisp :DIR :SYSTEM
Parents: [bv]

Bit-vector sum.

<body: markdown-flavored text>
```

Body rendering rules (HTML → text):

| xdoc HTML                        | corpus text                          |
|----------------------------------|--------------------------------------|
| `<see topic="K">text</see>`      | `[natural]` if text ≈ natural name; else `[text](natural)` |
| dangling `<see>` (K not in data) | `[K]` (mangled key kept, greppable)  |
| `<v>x</v>` (inline, from `@('...')`) | `` `x` ``                        |
| `<code>`/`<pre>` (block, from `@({...})`) | fenced ``` block            |
| `<see>` inside a code block      | display text only (code stays copy-pasteable; xdoc auto-links symbols in code) |
| `<h1>`..`<h5>`                   | `#`..`#####` markdown headers        |
| `<p>`                            | blank-line separated paragraphs      |
| `<ul>/<ol>/<li>`                 | `- ` items                           |
| `<dl>/<dt>/<dd>`                 | `* term` / indented body             |
| `<math>latex</math>`             | `$latex$` (LaTeX source preserved; only 49 occurrences corpus-wide) |
| `<table>`                        | rows as lines, cells ` | ` separated |
| entities (`&mdash;` etc.)        | decoded to characters                |
| `<img>`, `<icon>`                | dropped                              |

Rationale for the two link forms: `[bvplus]` is minimal when the display
text is the topic name (the overwhelmingly common case); the
markdown-style `[chop it](bvchop)` form preserves distinct display text
without inventing syntax agents haven't seen.

## index.tsv

One line per topic: `natural-name<TAB>KEY<TAB>short` (short: first 200
chars, whitespace-flattened, entity-decoded).  8 MB; a `grep -i` over it
answers "is there something for X?" in ~12 ms.  Sorted by natural name.

## What was measured (2026-08-30, allcerts master-de9b73f manual)

- 77,274 topics; conversion time ~90 s single-threaded in-image.
- v1 corpus (mangled links): topics/ 438 MB, index 8 MB; 38 MB tar.zst.
- v2 corpus (this design): topics/ 382 MB, index 7.8 MB; **34 MB tar.zst**;
  1 dangling link corpus-wide; zero mangled keys outside file names and
  Key: headers; 404 surviving literal entities (legitimate, e.g. the
  xdoc::entities topic and code samples).
- Discovery grep over index.tsv: 12 ms.  Full-text `rg` over all topic
  bodies: 0.28 s.  SQLite FTS5 was also built and measured (3 ms ranked
  queries, 358 MB) and **rejected**: ripgrep at 0.28 s makes a second
  query system not worth its size, tooling requirement, and freshness
  risk.

## Explicit non-goals / rejected alternatives

- **SQLite/FTS index**: rejected, see above.  Can be revisited if corpora
  grow 10x.
- **Serving raw HTML to agents**: modern models read HTML, but markup
  inflates tokens and corrupts grep hits/snippets; rejected.
- **`rendered-doc-combined.lsp` as source**: higher-fidelity official
  renderer, but not built by plain `make regression` (extra build cost)
  and single-file output needs splitting anyway.  Kept as a future
  fidelity upgrade that would not change this format contract.
- **In-session `(include-book "doc/top")` as the lookup path**: measured
  at ~57 s ACL2 time / ~3.0 GB RSS on 2 cores.  Viable as a *separate*
  warm "doc session" (authoritative, and interactively-defined topics
  with documentation become immediately :doc-able), but never in the
  working session (world pollution changes proof behavior), unavailable
  in kcerts, and unavailable before ACL2 starts.  Also note the doc/top
  world is *documentation-shaped, not definition-shaped*: some libraries
  contribute doc-only books, so a symbol can be documented there yet
  undefined (verified: `bvplus` has a topic but no function in that
  world) — the doc session can describe such symbols but cannot evaluate
  or prove with them.  Complementary, not competing; see PLAN.md.
- **Aggressive math simplification** (e.g. `\frac{a}{b}` → `a/b`):
  rejected as lossy/ambiguous; LaTeX source is agent-legible as-is.

## Coverage boundary

The corpus covers exactly `doc/top`'s include set (the manual's world) —
not the full regression set.  Books certified but not included by
`doc/top` (package conflicts, deliberate exclusions) appear in neither
this corpus nor a doc session.  Topics defined by an agent's own new
books are covered by neither; that is the in-session `:doc` niche.
