# ACL2 Docker Images

Prebuilt Docker images of the [ACL2](https://www.cs.utexas.edu/~moore/acl2/)
theorem prover on SBCL, published to the GitHub Container Registry in three
packages.

**To install and run an image, go to [INSTALL.md](INSTALL.md).**

This page describes what the images contain, how they are tagged, and how
they are built, for anyone who wants to build ACL2 images themselves.

## This Repository

- `Dockerfile` — a multi-stage build that compiles SBCL and ACL2 from source,
  with three build targets: `runtime`, `kcerts`, and `allcerts`.
- `INSTALL.md` — installing and running the images, including from Claude
  cloud sessions.
- `tools/` — the extractor that turns the built xdoc manual into the
  agent-friendly documentation corpus shipped in the `allcerts` image (see
  [tools/DESIGN.md](tools/DESIGN.md)).
- `examples/` — snapshots of the GitHub Actions workflows that build the
  official images, plus the self-hosted runner setup guides they rely on.
  These are reference material, not active workflows; see "Example
  workflows" below.

The official images are built by GitHub Actions workflows that live in a
private companion repository, `KestrelInstitute/acl2-docker-ci`; see "How the
official images are built" below.

## The Three Images

| Image | Platforms | Contents |
|-------|-----------|----------|
| `ghcr.io/kestrelinstitute/acl2` | linux/amd64 + linux/arm64 | SBCL + ACL2 + books as source (not certified) |
| `ghcr.io/kestrelinstitute/acl2-kcerts` | linux/amd64 + linux/arm64 | Everything in the lean image, **plus all books reachable from `kestrel/top` certified**, plus the **STP** solver (for Axe) and **Z3** (for Smtlink) |
| `ghcr.io/kestrelinstitute/acl2-allcerts` | linux/amd64 only | Everything in the lean image, **plus all books of the standard `make regression` suite certified**, plus **STP** and **Z3**, plus the xdoc agent corpus |

All three use the same Dockerfile: the lean image is the `runtime` build
target, `kcerts` extends `runtime` (via a `cert-base` stage that adds the
solvers), and `allcerts` extends `kcerts` — its regression skips the
already-certified kestrel books and certifies the rest.  Because of that
layering, an allcerts build produces the linux/amd64 kcerts image along the
way (and pushes it, as `acl2-kcerts:<tag>-amd64`), the two images with
certified books share their kestrel layers, and pulling both costs little
more than pulling allcerts alone.  The images with certified books are much
larger than the lean one because they contain the `.cert` files and compiled
books for their respective book sets; artifacts not needed by `include-book`
(such as `.cert.out` files) are removed during the build.

### Image Tagging

All images use the same tagging scheme (in their respective packages):

- **Master build (the default)**: tagged `master-abc1234` AND `latest`
  - Git is set up for easy updates: `git pull origin master`
  - The `latest` tag always points to the most recent master build
- **Specific ref**: tagged `commit-abc1234` only
  - Git is in detached HEAD mode (see INSTALL.md for updating)

The kcerts package additionally holds per-architecture tags
(`master-abc1234-amd64`, `master-abc1234-arm64`); these are the carriers
from which the multi-platform manifest is assembled and can be ignored.

### Builds are Strict

If any book fails to certify, the kcerts/allcerts build **fails and nothing
is pushed**. Certification runs with keep-going (`make -k` /
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
# Lean image, latest ACL2 master
docker build --target runtime -t acl2 .

# Lean image, a specific ACL2 commit (detached HEAD inside the image)
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

## How the Official Images are Built

Each image has a GitHub Actions workflow that is triggered by hand
(`workflow_dispatch` only), takes an ACL2 ref and a parallelism setting as
inputs, builds the corresponding Dockerfile target, and pushes it under the
tags described above.  The jobs run on:

| Job | Runner |
|-----|--------|
| Lean amd64 | GitHub-hosted |
| Lean arm64 | Self-hosted Apple Silicon Mac |
| kcerts amd64 | Self-hosted Ubuntu x86-64 server |
| kcerts arm64 | Self-hosted Apple Silicon Mac |
| allcerts amd64 | Self-hosted Ubuntu x86-64 server |

The workflows live in the private repository `KestrelInstitute/acl2-docker-ci`
rather than here.  They check out this repository's Dockerfile at a chosen
ref and build from it, so this repository remains the complete description
of the images.  Two reasons for the split: GitHub advises against attaching
self-hosted runners to public repositories, and the Actions logs of a public
repository are readable by any GitHub user and reveal details of the
self-hosted machines (hostname, OS, kernel, file-system paths).  Kestrel
staff who need to trigger a build or set up a runner should look there.

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

The images are not signed with GitHub artifact attestations: that feature is
available only to public repositories, and the self-hosted builds could
never have it in any case.  To pin an image, use its digest (see "Verifying
Image Authenticity" in INSTALL.md).

## Technical Details

### Why Apple Silicon for ARM64?

GitHub's ARM64 runners use Ampere/Neoverse CPUs that don't support
floating-point exception traps — an optional feature per the ARM
specification. ACL2 requires FP traps for proper error handling. Apple
Silicon supports FP traps, so ARM64 images are built on a self-hosted Mac.

### What's in the images kcerts and allcerts

- Certified books:
  - **kcerts**: `kestrel/top` and every book it depends on (certified with
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
