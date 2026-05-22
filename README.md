# ACL2 Docker Build Infrastructure

**This page is about how to build Docker images with ACL2.**  
**If you are looking for how to install and run a Docker image that contains ACL2, please go to the [INSTALL.md](INSTALL.md) page.**

---

## About This Repository

This repository contains build infrastructure for creating multi-platform ACL2 Docker images. It includes:

- `Dockerfile` - Multi-stage build that compiles SBCL and ACL2 from source
- GitHub Actions workflow for automated builds
- Build provenance attestation for supply chain security, in the case of GitHub-hosted builds

## Supported Platforms

| Platform | Architecture | Notes |
|----------|--------------|-------|
| Linux | x86-64 (amd64) | Built on GitHub-hosted runner |
| Linux | ARM64 (aarch64) | Built on self-hosted Apple Silicon runner |

Both platforms are combined into a single multi-platform image. Docker automatically selects the correct architecture when you pull.

## Image Contents

- **Ubuntu 24.04** base image
- **SBCL 2.6.1** built from source with ACL2-recommended flags as well as `--fancy` for core compression
- **ACL2** (latest master or specified commit)
- All ACL2 books (source only, not certified)
- Build tools: make, gcc, perl (for certifying books)

## Building Images

Images are built via GitHub Actions workflow dispatch. Only repository maintainers (users with write access) can trigger builds.

Before you dispatch:

- A self-hosted ARM64 runner must be online (the runner host must be running `./run.sh` or `./svc.sh start`).
- Docker Desktop must be running on the self-hosted host — the `build-arm64` job uses it to build the Linux ARM64 image.

See "Self-Hosted ARM64 Runner" below and [RUNNER-SETUP.md](RUNNER-SETUP.md) for details.

You can dispatch the workflow two ways:

- **Web UI** — Go to the [workflow page](https://github.com/KestrelInstitute/acl2-docker/actions/workflows/docker-multiplatform-selfhosted.yml) (Actions tab → "Build ACL2 Docker (Multi-Platform)"). Click the **"Run workflow"** button on the right side of the banner above the runs list. A small form appears with the inputs described in "Workflow Inputs" below. Fill it in and click the green **"Run workflow"** button at the bottom of the form to start the build.
- **`gh` CLI** — Use `gh workflow run docker-multiplatform-selfhosted.yml` with `-f name=value` flags for inputs. See "Example Commands" below.

### Workflow Inputs

| Input | Description |
|-------|-------------|
| `Use workflow from` | The branch/tag/SHA of *this* (`acl2-docker`) repo whose workflow definition to run. Default: `Branch: main`. Leave as-is unless you are testing workflow changes on a different branch. Note: this selects the *workflow* version, not the ACL2 version. |
| `ACL2 ref/commit to build` | Usually left blank (builds latest master). Enter a commit hash/branch/tag for a specific version. |
| `Extra tag` | Usually left blank. The `latest` tag is added automatically for master builds. |
| `Push to registry?` | Defaults to checked. Uncheck to test build without pushing. |

### Image Tagging

- **Empty input (default)**: Builds latest master → tagged `master-abc1234` AND `latest`
  - Git is set up for easy updates: `git pull origin master`
  - The `latest` tag always points to the most recent master build
- **Specific ref**: Builds that commit → tagged `commit-abc1234` only
  - Git is in detached HEAD mode (see INSTALL.md for updating)

### Example Commands

```bash
# Build latest master (recommended)
gh workflow run docker-multiplatform-selfhosted.yml \
  -f push_to_registry=true

# Build a specific commit
gh workflow run docker-multiplatform-selfhosted.yml \
  -f acl2_ref=abc1234def5678 \
  -f push_to_registry=true
```

## Self-Hosted ARM64 Runner

The `build-arm64` job in the workflow runs on a maintainer's Apple Silicon Mac
registered as a GitHub Actions self-hosted runner. This is necessary because
GitHub-hosted ARM64 runners cannot build ACL2 (see "Why Self-Hosted Runner for
ARM64?" below).

A registered runner already exists, so day-to-day builds do not require any
local setup. If you are a new `KestrelInstitute/acl2-docker` maintainer and
want to enable ARM64 builds on your own Mac (for example as a backup, or so
that you can trigger builds without coordinating with another maintainer), see
[RUNNER-SETUP.md](RUNNER-SETUP.md). The short version: visit the repo's
Settings → Actions → Runners → "New self-hosted runner" page, which generates
install commands with a fresh registration token; run them on your Mac;
accept the default labels (`self-hosted, macOS, ARM64`).

## Technical Details

### Why Self-Hosted Runner for ARM64?

GitHub's ARM64 runners use Ampere/Neoverse CPUs that don't support floating-point exception traps - an optional hardware limitation per the ARM specification. ACL2 requires FP traps for proper error handling. Apple Silicon supports FP traps, so we use a self-hosted Mac runner for ARM64 builds.

### Build Attestation

The amd64 image includes SLSA Level 2+ build provenance attestation, verifiable with:

```bash
gh attestation verify oci://ghcr.io/kestrelinstitute/acl2:latest --owner KestrelInstitute
```

The ARM64 image is built on a self-hosted runner and does not have attestation.

## License

The build infrastructure in this repository is provided under the same license as ACL2 (BSD 3-Clause).

## Links

- [ACL2 Homepage](https://www.cs.utexas.edu/~moore/acl2/)
- [ACL2 Documentation](https://acl2.org/doc/)
- [ACL2 Source Repository](https://github.com/acl2/acl2)
- [Kestrel Institute](https://www.kestrel.edu/)
