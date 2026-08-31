#!/usr/bin/env python3
"""xdoc_extract.py — build the agent corpus from a built xdoc manual.

Usage: xdoc_extract.py MANUAL_DIR OUT_DIR

Converts xdata.js + xindex.js into:
  OUT_DIR/topics/KEY.txt   one markdown-flavored text file per topic
  OUT_DIR/index.tsv        natural-name <TAB> KEY <TAB> short
  OUT_DIR/AGENT-README.md  usage notes for agents

See DESIGN.md for the format contract.  Python 3 stdlib only.
"""
import html
import json
import os
import re
import sys
import time
from html.parser import HTMLParser

SYMBOLISH = re.compile(r"^[A-Za-z0-9!$%&*+/<=>?@^_~.:#\[\]{}|'`\\-]+$")
UNQUALIFIED_PKGS = {"ACL2", "COMMON-LISP", "ACL2-PC"}


def natural_name(key, upper, pkg):
    """Compute the natural (agent-facing) name for a topic."""
    name = html.unescape(upper)
    if not SYMBOLISH.match(name):
        # Title-style topic ("ARM AArch32 ..."): keep display casing form.
        return html.unescape(name)
    name = name.lower()
    if pkg and pkg.upper() not in UNQUALIFIED_PKGS:
        return f"{pkg.lower()}::{name}"
    return name


class Render(HTMLParser):
    """xdoc HTML -> markdown-flavored text (see DESIGN.md table)."""

    def __init__(self, natmap):
        super().__init__(convert_charrefs=True)
        self.natmap = natmap
        self.out = []
        self.pre_depth = 0      # inside <pre>: suppress inline markup
        self.math = False
        self.see_target = None  # xdoc KEY of the open <see>
        self.see_text = []      # display text of the open <see>
        self.dangling = 0

    # -- helpers ---------------------------------------------------------
    def emit(self, s):
        if self.see_target is not None:
            self.see_text.append(s)
        else:
            self.out.append(s)

    # -- tags ------------------------------------------------------------
    def handle_starttag(self, tag, attrs):
        if tag == "see":
            self.see_target = dict(attrs).get("topic", "")
            self.see_text = []
        elif tag in ("pre", "code"):
            self.pre_depth += 1
            if self.pre_depth == 1:
                self.out.append("\n```\n")
        elif tag == "math":
            self.math = True
            self.emit("$")
        elif self.pre_depth:
            pass  # no markup inside code blocks
        elif tag in ("v", "tt"):
            self.emit("`")
        elif tag in ("h1", "h2", "h3", "h4", "h5"):
            self.out.append("\n\n" + "#" * int(tag[1]) + " ")
        elif tag in ("p", "ul", "ol", "dl", "blockquote", "table"):
            self.emit("\n\n")
        elif tag == "li":
            self.emit("\n- ")
        elif tag == "dt":
            self.emit("\n* ")
        elif tag == "dd":
            self.emit("\n    ")
        elif tag == "tr":
            self.emit("\n")
        elif tag in ("td", "th"):
            self.emit(" | ")
        elif tag == "br":
            self.emit("\n")

    def handle_endtag(self, tag):
        if tag == "see":
            text = "".join(self.see_text).strip()
            key = self.see_target
            self.see_target = None
            if self.pre_depth:
                # inside a code block: plain text, keep code copy-pasteable
                self.out.append(text)
                return
            nat = self.natmap.get(key)
            if nat is None:
                self.dangling += 1
                nat = key  # dangling: keep the key, still greppable
            if text.lower().replace(" ", "-") in (
                    nat, nat.split("::")[-1], nat.lower()):
                self.out.append(f"[{nat}]")
            elif not text:
                self.out.append(f"[{nat}]")
            else:
                self.out.append(f"[{text}]({nat})")
        elif tag in ("pre", "code"):
            if self.pre_depth == 1:
                self.out.append("\n```\n")
            self.pre_depth = max(0, self.pre_depth - 1)
        elif tag == "math":
            self.math = False
            self.emit("$")
        elif self.pre_depth:
            pass
        elif tag in ("v", "tt"):
            self.emit("`")
        elif tag in ("h1", "h2", "h3", "h4", "h5", "p"):
            self.emit("\n")

    def handle_data(self, data):
        if self.math:
            # LaTeX source, lightly cleaned (keep ^ _ \frac etc. as-is)
            data = data.replace("\\displaystyle", "")
        self.emit(data)


def render(natmap, html_text):
    p = Render(natmap)
    try:
        p.feed(html_text)
        p.close()
    except Exception:
        return html_text, 0  # fall back to raw on parser hiccup
    text = "".join(p.out)
    text = re.sub(r"[ \t]+\n", "\n", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip(), p.dangling


AGENT_README = """\
# ACL2 documentation corpus (for agents)

One plain-text file per xdoc topic, generated from the built ACL2 manual.
No tools needed beyond grep and file reads.

- **Find a topic by name or keyword** (name<TAB>file-key<TAB>one-liner):
  `grep -i 'tail recursion' index.tsv`
- **Read a topic**: open `topics/<KEY>.txt` using the KEY from column 2.
- **Full-text search across all topics** (~0.3 s):
  `grep -ril 'floating point exception' topics/` (or `rg`)
- Cross-references appear as `[name]` or `[text](name)`; look the name up
  in column 1 of index.tsv to get its file.
- Names are ACL2-style (`bvplus`, `fty::defbitstruct`) and match what you
  would type in an ACL2 session (`:doc bvplus`) or in code.
- Coverage: every topic in the manual built from this ACL2 commit.  Books
  outside doc/top's include set, and anything you define yourself, are
  not here — use `:doc` in a live ACL2 session for those.
"""


def main(manual, out):
    t0 = time.time()
    os.makedirs(f"{out}/topics", exist_ok=True)

    idx_raw = open(f"{manual}/xindex.js", encoding="utf-8").read()
    xindex = json.loads(idx_raw[idx_raw.index("["):idx_raw.rindex("]") + 1])
    # key -> (displayName, UPPERNAME, short-html)
    index = {e[0]: (e[1], e[2], e[4]) for e in xindex}
    del idx_raw, xindex
    print(f"index loaded: {len(index)} topics ({time.time()-t0:.1f}s)")

    data_raw = open(f"{manual}/xdata.js", encoding="utf-8").read()
    xdata = json.loads(data_raw[data_raw.index("{"):data_raw.rindex("}") + 1])
    del data_raw
    print(f"data loaded: {len(xdata)} topics ({time.time()-t0:.1f}s)")

    natmap = {}
    for key, entry in xdata.items():
        upper = index.get(key, (key, key, ""))[1]
        natmap[key] = natural_name(key, upper, entry[2])

    dangling_total = 0
    rows = []
    for key, (parents, src, pkg, long_html) in xdata.items():
        nat = natmap[key]
        short_html = index.get(key, ("", "", ""))[2]
        short, d1 = render(natmap, short_html)
        body, d2 = render(natmap, long_html)
        dangling_total += d1 + d2
        # parents in xdata are display names (not keys); keep them plain
        parent_line = ", ".join(parents)
        text = (f"# {nat}\n"
                f"Key: {key} | Package: {pkg}\n"
                f"Source: {src}\n"
                f"Parents: {parent_line}\n\n"
                f"{short}\n\n{body}\n")
        safe = re.sub(r"[^A-Za-z0-9_.-]", "_", key)
        with open(f"{out}/topics/{safe}.txt", "w", encoding="utf-8") as f:
            f.write(text)
        flat_short = re.sub(r"\s+", " ", short)[:200]
        rows.append((nat, safe, flat_short))

    rows.sort(key=lambda r: r[0])
    with open(f"{out}/index.tsv", "w", encoding="utf-8") as tsv:
        for nat, safe, flat_short in rows:
            tsv.write(f"{nat}\t{safe}\t{flat_short}\n")

    with open(f"{out}/AGENT-README.md", "w", encoding="utf-8") as f:
        f.write(AGENT_README)

    print(f"wrote {len(rows)} topics, {dangling_total} dangling links "
          f"({time.time()-t0:.1f}s)")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
