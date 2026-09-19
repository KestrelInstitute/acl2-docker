# ACL2 Docker Images

Prebuilt Docker images of the [ACL2](https://www.cs.utexas.edu/~moore/acl2/)
theorem prover on SBCL, published to the GitHub Container Registry in four
packages.

**To install and run an image, go to [INSTALL.md](INSTALL.md).**

This page is for anyone who wants to build ACL2 images themselves: it
describes what the images contain and how they are tagged, how to build
them on your own machine, and the two ways we automate building them — on
GitHub's free hosted runners and on our own self-hosted machines — with
enough detail to reproduce either.

## This Repository

- `Dockerfile` — a multi-stage build that compiles SBCL and ACL2 from
  source.  Its build targets are `runtime` (lean), `cert-base` (solvers
  installed, no books certified), `kcerts`, and `allcerts`.
- `INSTALL.md` — installing and running the images, including from Claude
  Cowork and ChatGPT Work cloud sessions.
- `.github/workflows/` — the nightly build that runs on GitHub-hosted
  runners: `nightly-kcerts-amd64.yml`, and the reusable
  `allcerts-chunked.yml` it calls (with `.github/actions/certify-chunk`
  and `tools/certify-chunk.sh`), which fits a long certification into
  GitHub's per-job time limit.
- `examples/` — snapshots of the GitHub Actions workflows behind the other
  three packages, plus the self-hosted runner setup guides they rely on.
  These are reference material, not active workflows.
- `tools/` — also holds the extractor that turns the built xdoc manual
  into the agent-friendly documentation corpus shipped in the `allcerts`
  image (see [tools/DESIGN.md](tools/DESIGN.md)).

## The Four Images

| Image | Platforms | Contents | Rebuilt |
|-------|-----------|----------|---------|
| `ghcr.io/kestrelinstitute/acl2` | linux/amd64 + linux/arm64 | SBCL + ACL2 + books as source (not certified) | by hand, occasionally |
| `ghcr.io/kestrelinstitute/acl2-kcerts` | linux/amd64 + linux/arm64 | Everything in the lean image, **plus all books reachable from `kestrel/top` certified**, plus the **STP** solver (for Axe) and **Z3** (for Smtlink) | by hand, occasionally |
| `ghcr.io/kestrelinstitute/acl2-allcerts` | linux/amd64 only | Everything in the lean image, **plus all books of the standard `make regression` suite certified**, plus **STP** and **Z3**, plus the xdoc agent corpus | by hand, occasionally |
| `ghcr.io/kestrelinstitute/acl2-kcerts-nightly` | linux/amd64 only | The same contents as `acl2-kcerts` | **every night** that ACL2 master has changed |

All four use the same Dockerfile.  The lean image is the `runtime` build
target; `cert-base` extends `runtime` with the solvers; `kcerts` extends
`cert-base` by certifying the `kestrel/top` tree; and `allcerts` extends
`kcerts` — its regression skips the already-certified kestrel books and
certifies the rest.  Because of that layering, an allcerts build produces
the linux/amd64 kcerts image along the way (and pushes it, as
`acl2-kcerts:<tag>-amd64`), the two images with certified books share
their kestrel layers, and pulling both costs little more than pulling
allcerts alone.  The nightly builds `cert-base` and certifies the same
book set as `kcerts`, but does so in checkpointed steps on GitHub-hosted
runners (see "Automating Builds" below), so its layers are its own — it
shares content, not layers, with `acl2-kcerts`.  The images with certified
books are much larger than the lean one because they contain the `.cert`
files and compiled books for their book sets; artifacts not needed by
`include-book` (such as `.cert.out` files) are removed during the build.

### Image Tagging

All images use the same tagging scheme (in their respective packages):

- **Master build (the default)**: tagged `master-abc1234` AND `latest`
  - Git is set up for easy updates: `git pull origin master`
  - The `latest` tag always points to the most recent master build
- **Specific ref**: tagged `commit-abc1234` only
  - Git is in detached HEAD mode (see INSTALL.md for updating)

Two qualifications.  The kcerts package additionally holds
per-architecture tags (`master-abc1234-amd64`, `master-abc1234-arm64`);
these are the carriers from which the multi-platform manifest is assembled
and can be ignored.  The nightly package has no `commit-*` tags (it always
builds master) and additionally holds `ckpt-*` tags — internal checkpoints
of in-progress builds — which can likewise be ignored.

### Builds are Strict

If any book fails to certify, a build with certified books (kcerts,
allcerts, or the nightly) **fails and no image tag is published** — the
nightly pushes only its internal `ckpt-*` checkpoint in that case, never
`master-*` or `latest`.  Certification runs with keep-going (`make -k` /
`cert.pl --keep-going`), so all failing books are reported in one run: the
end of the build log lists them (under "CERTIFICATION FAILED"), and details
for each appear earlier in the log. ACL2 `master` is usually kept green, so
failures should be rare.

### The xdoc Corpus Release

Each allcerts build also publishes the agent-friendly documentation corpus
from the image (`books/doc/agent-corpus/`) as the
[xdoc-corpus release](https://github.com/KestrelInstitute/acl2-docker/releases/tag/xdoc-corpus)
of this repository, both under a commit-stamped name and as
`xdoc-corpus-latest.tar.zst`, for environments that cannot pull the image.
See [tools/DESIGN.md](tools/DESIGN.md).

## Building the Images Yourself

The Dockerfile is self-contained; a local build needs only Docker.  Pick a
target explicitly — `allcerts` is the last stage, so a plain `docker build .`
runs the full regression:

```bash
# lean image, latest ACL2 master
docker build --target runtime -t acl2 .

# lean image, a specific ACL2 commit (detached HEAD inside the image)
docker build --target runtime \
  --build-arg ACL2_COMMIT=abc1234def5678 --build-arg ACL2_BUILD_TYPE=commit \
  -t acl2 .

# cert-base: lean image plus STP and Z3, no books certified yet
docker build --target cert-base -t acl2-cert-base .

# kcerts: kestrel/top certified, with STP and Z3
docker build --target kcerts --build-arg CERT_JOBS=8 -t acl2-kcerts .

# allcerts: the full regression suite certified
docker build --target allcerts --build-arg CERT_JOBS=8 -t acl2-allcerts .
```

Build arguments (all have defaults in the Dockerfile):

| Argument | Meaning |
|----------|---------|
| `ACL2_COMMIT` | ACL2 commit, tag, or branch to build (default `master`) |
| `ACL2_BUILD_TYPE` | `master` (branch set up for `git pull`) or `commit` (detached HEAD) |
| `CERT_JOBS` | Parallel certification jobs for `kcerts`/`allcerts` (default: all cores) |
| `SBCL_VERSION`, `SBCL_SHA256` | SBCL release to build; change both together |
| `STP_VERSION`, `MINISAT_COMMIT` | STP release and its minisat dependency (`cert-base` and up) |
| `Z3_SOLVER_VERSION` | `z3-solver` PyPI package, which provides both `z3` and the Python bindings Smtlink uses |

Resource needs:

- **Memory.** Book certification needs roughly 4 GB per parallel job; set
  `CERT_JOBS` to about RAM / 4 GB if the default (all cores) would exceed
  that.  On macOS, give Docker Desktop plenty of memory (32 GB recommended
  for `kcerts`).
- **Time.** The lean image builds in minutes; `cert-base` adds the STP
  build (BuildKit runs it in parallel with the Lisp toolchain, so about 15
  minutes total on a 4-core machine).  Certification is the bulk of the
  work: the kestrel book set is about 6.25 CPU-hours and the rest of the
  regression about 22 more.  On a 32-core, 128 GB server, `kcerts`
  certification takes about 35 minutes and the `allcerts` regression a
  further 55 minutes (much of that time most cores are idle, waiting on
  dependencies).  On a 4-core, 16 GB machine at `CERT_JOBS=3`, `kcerts`
  takes about 2¼ hours, and the full `allcerts` regression would take
  roughly 10.
- **arm64 needs Apple Silicon.** See "Why Apple Silicon for ARM64?" below.
  On a Mac, `docker build` produces a native linux/arm64 image.

## Automating Builds: Two Styles

We build the published images two ways, and document both so that anyone
can reproduce either: a scheduled workflow in this public repository that
runs on GitHub's free hosted runners, and hand-dispatched workflows in a
private companion repository that run on our own self-hosted machines.
The trade-offs:

|  | GitHub-hosted runners, public repo | Self-hosted runners, private repo |
|--|-----------------------------------|-----------------------------------|
| Used for | `acl2-kcerts-nightly` | `acl2`, `acl2-kcerts`, `acl2-allcerts` |
| Trigger | schedule (nightly), or by hand | by hand |
| Cost | free and unmetered for public repositories | your own hardware |
| Machine | 4 vCPUs, 16 GB RAM, ~20 GB free disk (~50 GB after the workflow removes preinstalled SDKs) | whatever you own (ours: a 32-core, 128 GB server; an Apple Silicon Mac) |
| Per-job limit | 6 hours — long certifications must be split (see below) | none in practice (5 days) |
| Platforms | linux/amd64 only (GitHub's arm64 runners lack the FP traps ACL2 needs) | anything you own; arm64 via Apple Silicon |
| Visibility | everything public: trigger, logs, runner, package | logs must stay private (they reveal host details) |
| Setup | none | register and run a runner on each machine |
| Attestation-eligible | yes | no |

Choose the hosted style when you want a build anyone can inspect and
nothing to maintain, and can live with amd64 and a slower wall clock.
Choose self-hosted when you need arm64, big machines, or fast turnaround.

### Style 1: GitHub-hosted runners (the nightly)

The `acl2-kcerts-nightly` package tracks ACL2 master.
`nightly-kcerts-amd64.yml` runs every night (00:17 Pacific standard time),
and first compares ACL2 master's current commit with the one in the last
pushed nightly; when nothing has changed, the run ends there, at a cost of
a few seconds.  Otherwise it builds SBCL + that ACL2 master, certifies the
`kestrel/top` book set — the kcerts image contents — and pushes the result
as `master-<sha>` and `latest`.  It can also be dispatched by hand (with a
`force` option to rebuild an unchanged master).  Every step is publicly
visible in this repository's
[Actions history](https://github.com/KestrelInstitute/acl2-docker/actions/workflows/nightly-kcerts-amd64.yml).
The first real runs took about 2¾ hours end to end: 15 minutes for the
base image and 2¼ hours of certification at `-j3`.

Because a failed certification fails the run and publishes nothing but
the internal checkpoint, the nightly doubles as a canary for ACL2 master
plus the kestrel books on a plain public toolchain.

#### Fitting a long certification into the 6-hour job limit

GitHub-hosted jobs are killed after 6 hours, and a full regression on a
4-core runner needs about 10.  The nightly therefore runs through a
reusable workflow, `allcerts-chunked.yml`, which certifies in resumable
chunks:

1. A **base** job builds the Dockerfile's `cert-base` target and pushes it
   to ghcr as this run's checkpoint image (tag `ckpt-<run id>`).
2. **Certify** jobs run in a chain.  Each pulls the checkpoint, runs the
   certification under a time budget (`tools/certify-chunk.sh`, 5 hours by
   default), `docker commit`s the container, and pushes it back to the
   checkpoint tag.  make/cert.pl skip already-certified books, so the next
   chunk resumes where the previous one stopped, losing at most the books
   in flight when the budget expired.  Chunks after the one that finishes
   skip themselves.
3. A **finalize** job retags the checkpoint as `master-<sha>` and `latest`
   on success, or reports the failure.

The knobs are inputs of the reusable workflow: `book_target` (`kestrel`
or the full `regression`), `cert_jobs`, `chunk_minutes`, and `resume_from`
(continue an exhausted or interrupted chain from its checkpoint tag in a
new run).  To use this elsewhere, copy three files — the reusable
workflow, the `.github/actions/certify-chunk` composite action, and
`tools/certify-chunk.sh` — and write a small dispatch or schedule wrapper
like `nightly-kcerts-amd64.yml`.  For the kestrel set one chunk suffices;
the full regression would take two or three.

### Style 2: Self-hosted runners from a private repository (the dispatched builds)

Each of the `acl2`, `acl2-kcerts`, and `acl2-allcerts` packages has a
GitHub Actions workflow that is triggered by hand (`workflow_dispatch`
only), takes an ACL2 ref and a parallelism setting as inputs, builds the
corresponding Dockerfile target, and pushes it under the tags described
above.  The jobs run on:

| Job | Runner |
|-----|--------|
| lean amd64 | GitHub-hosted |
| lean arm64 | Self-hosted Apple Silicon Mac |
| kcerts amd64 | Self-hosted Ubuntu x86-64 server |
| kcerts arm64 | Self-hosted Apple Silicon Mac |
| allcerts amd64 | Self-hosted Ubuntu x86-64 server |

The workflows live in a private repository rather than here because Actions logs
of a public repository reveal various details of the self-hosted runner
machines.  The workflows check out this repository's Dockerfile at a chosen ref
and build from it, so this repository remains the complete description of the
images.  Kestrel staff who need to trigger a build or set up a runner should
look there.

For everyone else, snapshots of the three workflows are kept in
[examples/workflows/](examples/workflows/) as examples of what someone
else could set up — for instance, to build and publish these images for
their own organization.  They sit outside `.github/workflows/`, so GitHub
never runs them from this repository; each file's header comment explains
what to adapt (runner labels, registry organization).  The accompanying
runner setup guides,
[examples/RUNNER-SETUP-UBUNTU-AMD64.md](examples/RUNNER-SETUP-UBUNTU-AMD64.md)
and
[examples/RUNNER-SETUP-MACOS-ARM64.md](examples/RUNNER-SETUP-MACOS-ARM64.md),
describe how the self-hosted runners those workflows target were
configured.  The snapshots track the private repository loosely — the
live workflows there may drift ahead of these copies.

### Attestations

None of the images are signed with GitHub artifact attestations.  For the
dispatched builds the feature is unavailable in principle (it requires
GitHub-hosted runners in a public repository, which self-hosted builds can
never be); the nightly runs in exactly the setting attestations require
and could adopt them, but does not at present — its runs are publicly
logged instead.  To pin an image, use its digest (see "Verifying Image
Authenticity" in INSTALL.md).

## Technical Details

### Why Apple Silicon for ARM64?

GitHub's ARM64 runners use server-class Arm CPUs (Neoverse cores) that
don't support floating-point exception traps — an optional feature per the
ARM specification. ACL2 requires FP traps for proper error handling. Apple
Silicon supports FP traps, so ARM64 images are built on a self-hosted Mac.
This is also why the nightly is amd64 only.

### What's in the images with certified books

- Certified books:
  - **kcerts** (and **kcerts-nightly**, which has the same contents):
    `kestrel/top` and every book it depends on (certified with
    `cert.pl`).
  - **allcerts**: all books of the standard `make regression` suite (this
    is everything except the `SLOW_BOOKS` list in `books/GNUmakefile`,
    which excludes a handful of very slow books and, e.g., the x86isa and
    filesystem proof developments).
- **STP** (built from a pinned release of <https://github.com/stp/stp>),
  used by the Axe toolkit. Axe's own `teststp.bash` sanity test is run
  during the build, before certification starts.
- **Z3 with Python bindings** (the pinned `z3-solver` package in a
  virtualenv at `/root/.venvs/smtlink`, whose `bin` is appended to `PATH`),
  used by Smtlink. The Smtlink configuration file `/root/smtlink-config`
  points at the venv's Python by absolute path and is written before
  certification, so the certified Smtlink books have it baked in.
- Certification artifacts that are no longer needed are removed:
  `.cert.out`, `.cert.time`, `.pcert0`/`.pcert1`, and `workxxx` files.
  What remains for each book: the source, its `.cert` file, its compiled
  `.fasl` file, its `.port` file, and (for two-pass books) its `.acl2x`
  and `@expansion.lsp` files — the build-system files are kept because
  cert.pl needs them when certifying new books on top of the ones in the
  image (it loads included books' `.port` files, and regenerates missing
  `.acl2x` files it considers dependencies).

## License

The build infrastructure in this repository is provided under the same license as ACL2 (BSD 3-Clause).

## Links

- [ACL2 Homepage](https://www.cs.utexas.edu/~moore/acl2/)
- [ACL2 Documentation](https://acl2.org/doc/)
- [ACL2 Source Repository](https://github.com/acl2/acl2)
- [Kestrel Institute](https://www.kestrel.edu/)
