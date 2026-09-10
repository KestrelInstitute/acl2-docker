# ACL2 Docker Images

Prebuilt Docker images of the [ACL2](https://www.cs.utexas.edu/~moore/acl2/)
theorem prover on SBCL, published to the GitHub Container Registry in four
packages.

**To install and run an image, go to [INSTALL.md](INSTALL.md).**

This page describes what the images contain, how they are tagged, and how
they are built, for anyone who wants to build ACL2 images themselves.

## Two styles of building Docker images

We have two main workflows for building Docker images, although they
share some pieces.

1. Public runners triggered here, everything public here.

   Right now these are the `kcerts-nightly` images, platform linux/amd64, which
   contain certificates for all the Kestrel books and are generated nightly

   Since GitHub hosts the free runners, they don't have as many cores (4)
   or as much memory (16 GB) so they are slower.

2. Self-hosted runners triggered from a private repo, saving packages here.

   Since these use self-hosted runners on big servers, they can build fast.
   Also, we can build ACL2 on Darwin (Apple Silicon) this way and make
   multi-platform images.

   These are created on an as-needed basis.  See below for some examples.

   We document this workflow to save time for others who want to do something
   similar.

## This Repository

- `Dockerfile` — a multi-stage build that compiles SBCL and ACL2 from source.
  Its build targets are `runtime`, `kcerts`, and `allcerts`, plus the
  intermediate `cert-base` (solvers installed, no books certified), which is
  what the nightly build starts from.
- `INSTALL.md` — installing and running the images, including from Claude
  cloud sessions.
- `tools/` — the extractor that turns the built xdoc manual into the
  agent-friendly documentation corpus shipped in the `allcerts` image (see
  [tools/DESIGN.md](tools/DESIGN.md)).
- `.github/workflows/` — the workflow that builds the nightly package on
  GitHub-hosted runners (see "How the Images are Built" below).
- `examples/` — snapshots of the GitHub Actions workflows behind the other
  three packages, plus the self-hosted runner setup guides they rely on.
  These are reference material, not active workflows; see "Example
  workflows" below.

The nightly package is built by this repository's own workflow; the other three
are built by hand-dispatched workflows in a private companion repository on
self-hosted runners.  See "How the Images are Built" below for both.

## The Four Images

| Image | Platforms | Contents | Built |
|-------|-----------|----------|-------|
| `ghcr.io/kestrelinstitute/acl2` | linux/amd64 + linux/arm64 | SBCL + ACL2 + books as source (not certified) | on dispatch |
| `ghcr.io/kestrelinstitute/acl2-kcerts` | linux/amd64 + linux/arm64 | Everything in the lean image, **plus all books reachable from `kestrel/top` certified**, plus the **STP** solver (for Axe) and **Z3** (for Smtlink) | on dispatch |
| `ghcr.io/kestrelinstitute/acl2-allcerts` | linux/amd64 only | Everything in the lean image, **plus all books of the standard `make regression` suite certified**, plus **STP** and **Z3**, plus the xdoc agent corpus | on dispatch |
| `ghcr.io/kestrelinstitute/acl2-kcerts-nightly` | linux/amd64 only | The same contents as `acl2-kcerts` | **every night**, from that night's ACL2 master |

All four use the same Dockerfile.  The lean image is the `runtime` build
target; `kcerts` extends `runtime` (via a `cert-base` stage that adds the
solvers); and `allcerts` extends `kcerts` — its regression skips the
already-certified kestrel books and certifies the rest.  Because of that
layering, a dispatched allcerts build produces the linux/amd64 kcerts image
along the way (and pushes it, as `acl2-kcerts:<tag>-amd64`), the two images
with certified books share their kestrel layers, and pulling both costs
little more than pulling allcerts alone.  The nightly builds the same
`cert-base` target and certifies the same book set as `kcerts`, but does so
in checkpointed steps on GitHub-hosted runners (see "How the Images are
Built"), so its layers are its own — it shares content, not layers, with
`acl2-kcerts`.  The images with certified books are much larger than the
lean one because they contain the `.cert` files and compiled books for
their respective book sets; artifacts not needed by `include-book` (such as
`.cert.out` files) are removed during the build.

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
| `STP_VERSION`, `MINISAT_COMMIT` | STP release and its minisat dependency (`kcerts`/`allcerts`) |
| `Z3_SOLVER_VERSION` | `z3-solver` PyPI package, which provides both `z3` and the Python bindings Smtlink uses |

Resource needs:

- **Memory.** Book certification needs roughly 4 GB per parallel job; set
  `CERT_JOBS` to about RAM / 4 GB if the default (all cores) would exceed
  that.  On macOS, give Docker Desktop plenty of memory (32 GB recommended
  for `kcerts`).
- **Time.** The lean image builds in minutes.  On a 32-core, 128 GB server,
  `kcerts` certification takes about 35 minutes and the `allcerts`
  regression a further 55 minutes; smaller machines take proportionally
  longer.
- **arm64 needs Apple Silicon.** See "Why Apple Silicon for ARM64?" below.
  On a Mac, `docker build` produces a native linux/arm64 image.

## How the Images are Built

Two GitHub Actions pipelines produce the four packages: hand-dispatched
workflows in a private companion repository build `acl2`, `acl2-kcerts`,
and `acl2-allcerts` on (mostly) self-hosted runners, and a scheduled
workflow in this repository builds `acl2-kcerts-nightly` on GitHub-hosted
runners.

### Dispatched builds (private repository, self-hosted runners)

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

The workflows live in a private repository rather than here, but we show
examples of the workflows in the examples directory.  They check out this
repository's Dockerfile at a chosen ref and build from it, so this repository
remains the complete description of the images.  Two reasons for the split:
GitHub advises against attaching self-hosted runners to public repositories, and
the Actions logs of a public repository are readable by any GitHub user and
reveal details of the self-hosted machines (hostname, OS, kernel, file-system
paths).  Kestrel staff who need to trigger a build or set up a runner should
look there.

### Example workflows

Snapshots of the three workflows are kept in
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
configured.  The snapshots track the private CI repository loosely — the
live workflows there may drift ahead of these copies.

### The nightly build (this repository, GitHub-hosted runners)

The `acl2-kcerts-nightly` package tracks ACL2 master:
`nightly-kcerts-amd64.yml` runs every night (00:17 Pacific standard
time), builds SBCL + the latest ACL2 master, certifies the `kestrel/top`
book set — the kcerts image contents — entirely on GitHub's free public
amd64 runners (4 vCPUs, 16 GB RAM), and pushes the result as
`master-<sha>` and `latest`.  On nights when ACL2 master has not changed,
a small check job skips the build.  Unlike the dispatched builds, every
step of this one is publicly visible in this repository's
[Actions history](https://github.com/KestrelInstitute/acl2-docker/actions/workflows/nightly-kcerts-amd64.yml).
See INSTALL.md for how the nightly compares with `acl2-kcerts` as
something to run.

Because certification could exceed GitHub's 6-hour-per-job limit, the
build uses a reusable chunked workflow (`allcerts-chunked.yml`): a base
job builds the Dockerfile's `cert-base` target and pushes it to ghcr as a
checkpoint; certification jobs then run in a chain, each certifying under
a time budget (`tools/certify-chunk.sh`), docker-committing the
container, and pushing it back as the checkpoint the next job resumes
from (make/cert.pl skip already-certified books).  In practice the
kestrel set fits comfortably in one chunk: the first real runs took about
2¾ hours end to end — roughly 15 minutes for the base build (BuildKit
builds the solver and Lisp toolchains in parallel) and 2¼ hours of
certification at `-j3`, matching the ~6.25 CPU-hours the same book set
measures on a fast server.  A failed certification fails the run loudly
and publishes nothing but the checkpoint, so the nightly doubles as a
canary for ACL2 master + the kestrel books on a plain public toolchain.

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
