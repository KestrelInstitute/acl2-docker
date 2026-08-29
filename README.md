# ACL2 Docker Build Infrastructure

**This page is about how to build Docker images with ACL2.**  
**If you are looking for how to install and run a Docker image that contains ACL2, please go to the [INSTALL.md](INSTALL.md) page.**

---

## About This Repository

This repository contains build infrastructure for creating ACL2 Docker images. It includes:

- `Dockerfile` - Multi-stage build that compiles SBCL and ACL2 from source, with three build targets (`runtime`, `kcerts`, and `allcerts`)
- Three GitHub Actions workflows for automated builds (see below)
- Build provenance attestation for supply chain security, in the case of GitHub-hosted builds

## The Three Images

| Image | Platforms | Contents | Workflow |
|-------|-----------|----------|----------|
| `ghcr.io/kestrelinstitute/acl2` | linux/amd64 + linux/arm64 | SBCL + ACL2 + books as source (not certified) | `docker-multiplatform-selfhosted.yml` |
| `ghcr.io/kestrelinstitute/acl2-kcerts` | linux/amd64 + linux/arm64 | Everything in the lean image, **plus all books reachable from `kestrel/top` certified**, plus the **STP** solver (for Axe) and **Z3** (for Smtlink) | `docker-kcerts-selfhosted.yml` |
| `ghcr.io/kestrelinstitute/acl2-allcerts` | linux/amd64 only | Everything in the lean image, **plus all books of the standard `make regression` suite certified**, plus **STP** and **Z3** | `docker-allcerts-selfhosted.yml` |

All three use the same Dockerfile: the lean image is the `runtime` build
target, `kcerts` extends `runtime` (via a `cert-base` stage that adds the
solvers), and `allcerts` extends `kcerts` — its regression skips the
already-certified kestrel books and certifies the rest.  Because of that
layering, an allcerts build produces the linux/amd64 kcerts image along the
way (and pushes it, as `acl2-kcerts:<tag>-amd64`), the two images with certified books
share their kestrel layers, and pulling both costs little more than pulling
allcerts alone.  The images with certified books are much larger than the lean one
because they contain the `.cert` files and compiled books for their
respective book sets; artifacts not needed by `include-book` (such as
`.cert.out` files) are removed during the build.

### Where the builds run

| Job | Runner | Notes |
|-----|--------|-------|
| Lean amd64 | GitHub-hosted | With SLSA attestation |
| Lean arm64 | Self-hosted Apple Silicon Mac | See [RUNNER-SETUP-MACOS-ARM64.md](RUNNER-SETUP-MACOS-ARM64.md) |
| kcerts amd64 | Self-hosted Ubuntu x86-64 server | See [RUNNER-SETUP-UBUNTU-AMD64.md](RUNNER-SETUP-UBUNTU-AMD64.md) |
| kcerts arm64 | Self-hosted Apple Silicon Mac | Same runner as lean arm64 |
| allcerts amd64 | Self-hosted Ubuntu x86-64 server | Same runner as kcerts amd64 |

## Building Images

Images are built via GitHub Actions workflow dispatch. Only repository maintainers (users with write access) can trigger builds.

Before you dispatch:

- **Multi-platform (lean) workflow**: the self-hosted ARM64 Mac runner must be online, with Docker Desktop running.
- **kcerts workflow**: BOTH self-hosted runners must be online (the Ubuntu x86-64 runner with Docker Engine, and the ARM64 Mac with Docker Desktop). Each certifies the kestrel/top book set for its architecture.
- **allcerts workflow**: the self-hosted Ubuntu x86-64 runner must be online, with Docker Engine running. This build runs a full book regression, so expect it to take on the order of an hour on a large server (much longer on a small machine or with a cold Docker cache).

You can dispatch a workflow two ways:

- **Web UI** — Go to the Actions tab and select the workflow
  ([multi-platform](https://github.com/KestrelInstitute/acl2-docker/actions/workflows/docker-multiplatform-selfhosted.yml),
  [kcerts](https://github.com/KestrelInstitute/acl2-docker/actions/workflows/docker-kcerts-selfhosted.yml),
  or
  [allcerts](https://github.com/KestrelInstitute/acl2-docker/actions/workflows/docker-allcerts-selfhosted.yml)).
  Click the **"Run workflow"** button on the right side of the banner above the runs list. A small form appears with the inputs described in "Workflow Inputs" below. Fill it in and click the green **"Run workflow"** button at the bottom of the form to start the build.
- **`gh` CLI** — Use `gh workflow run <workflow-file>` with `-f name=value` flags for inputs. See "Example Commands" below.

### Workflow Inputs

| Input | Workflows | Description |
|-------|-----------|-------------|
| `Use workflow from` | both | The branch/tag/SHA of *this* (`acl2-docker`) repo whose workflow definition to run. Default: `Branch: main`. Leave as-is unless you are testing workflow changes on a different branch. Note: this selects the *workflow* version, not the ACL2 version. |
| `ACL2 ref/commit to build` | both | Usually left blank (builds latest master). Enter a commit hash/branch/tag for a specific version. |
| `Extra tag` | both | Usually left blank. The `latest` tag is added automatically for master builds. |
| `Parallel certification jobs` | kcerts, allcerts | Usually left blank (uses all cores on the runner). Set lower if a runner's RAM is limited (rule of thumb: jobs ≈ RAM / 4 GB). For kcerts, the same value applies on both runners. |
| `Push to registry?` | both | Defaults to checked. Uncheck to test build without pushing. |

### Image Tagging

All images use the same tagging scheme (in their respective packages):

- **Empty input (default)**: Builds latest master → tagged `master-abc1234` AND `latest`
  - Git is set up for easy updates: `git pull origin master`
  - The `latest` tag always points to the most recent master build
- **Specific ref**: Builds that commit → tagged `commit-abc1234` only
  - Git is in detached HEAD mode (see INSTALL.md for updating)

The kcerts package additionally holds per-architecture tags
(`master-abc1234-amd64`, `master-abc1234-arm64`); these are the carriers
from which the multi-platform manifest is assembled and can be ignored.
(The `-amd64` one is also pushed by the allcerts workflow, since the
allcerts build passes through the kcerts stage.  A useful dispatch order
for a given commit is therefore: allcerts first, then kcerts — the kcerts
amd64 job will hit the Ubuntu runner's Docker cache, leaving only the Mac's
arm64 build and the manifest as new work.)

### Builds are Strict

If any book fails to certify, the kcerts/allcerts build **fails and nothing
is pushed**. Certification runs with keep-going (`make -k` /
`cert.pl --keep-going`), so all failing books are reported in one run: the
end of the build log lists them (under "CERTIFICATION FAILED"), and details
for each appear earlier in the log. ACL2 `master` is usually kept green, so
failures should be rare; re-run later or pass a known-good `acl2_ref`.

### Example Commands

```bash
# Lean multi-platform image, latest master (recommended)
gh workflow run docker-multiplatform-selfhosted.yml \
  -f push_to_registry=true

# Lean multi-platform image, specific commit
gh workflow run docker-multiplatform-selfhosted.yml \
  -f acl2_ref=abc1234def5678 \
  -f push_to_registry=true

# kcerts image (kestrel/top books certified, both platforms), latest master
gh workflow run docker-kcerts-selfhosted.yml \
  -f push_to_registry=true

# allcerts image (full regression certified, amd64), latest master
gh workflow run docker-allcerts-selfhosted.yml \
  -f push_to_registry=true

# allcerts image, limiting parallelism (e.g. runner has 128 cores but 256 GB RAM is shared)
gh workflow run docker-allcerts-selfhosted.yml \
  -f cert_jobs=32 \
  -f push_to_registry=true
```

## Self-Hosted Runners

Two different self-hosted runners are used:

- **ARM64 (Apple Silicon Mac)** — used by the `build-arm64` job of the
  multi-platform workflow and the `build-kcerts-arm64` job of the kcerts
  workflow. GitHub-hosted ARM64 runners cannot build ACL2
  (see "Why Self-Hosted Runner for ARM64?" below). Setup:
  [RUNNER-SETUP-MACOS-ARM64.md](RUNNER-SETUP-MACOS-ARM64.md). Runner labels:
  `self-hosted, macOS, ARM64`.
- **x86-64 (Ubuntu server)** — used by the `build-kcerts-amd64` job of the
  kcerts workflow and the `build-allcerts` job of the allcerts workflow. A
  large book certification needs far more time, RAM, and disk than
  GitHub-hosted runners provide. Setup:
  [RUNNER-SETUP-UBUNTU-AMD64.md](RUNNER-SETUP-UBUNTU-AMD64.md). Runner
  labels: `self-hosted, Linux, X64`.

The label sets are disjoint, so the workflows can never pick up each other's
runners. In both cases, registration is: visit the repo's Settings → Actions
→ Runners → "New self-hosted runner" page (as an admin), run the generated
commands on the machine, and accept the default labels.

## Technical Details

### Why Self-Hosted Runner for ARM64?

GitHub's ARM64 runners use Ampere/Neoverse CPUs that don't support floating-point exception traps - an optional hardware limitation per the ARM specification. ACL2 requires FP traps for proper error handling. Apple Silicon supports FP traps, so we use a self-hosted Mac runner for ARM64 builds.

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
- Certification artifacts **not** needed by `include-book` are removed:
  `.cert.out`, `.cert.time`, `.acl2x`, `.pcert0`/`.pcert1`, `@expansion.lsp`,
  and `workxxx` files, plus `.port` files for certified books (ACL2 only
  reads `.port` files when including *uncertified* books). What remains for
  each book: the source, its `.cert` file, and its compiled `.fasl` file.

### Build Attestation

The lean amd64 image includes SLSA Level 2+ build provenance attestation, verifiable with:

```bash
gh attestation verify oci://ghcr.io/kestrelinstitute/acl2:latest --owner KestrelInstitute
```

The ARM64 image and the kcerts/allcerts images are built on self-hosted runners and do not have attestation.

## License

The build infrastructure in this repository is provided under the same license as ACL2 (BSD 3-Clause).

## Links

- [ACL2 Homepage](https://www.cs.utexas.edu/~moore/acl2/)
- [ACL2 Documentation](https://acl2.org/doc/)
- [ACL2 Source Repository](https://github.com/acl2/acl2)
- [Kestrel Institute](https://www.kestrel.edu/)
