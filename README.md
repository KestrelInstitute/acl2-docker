# ACL2 Docker Build Infrastructure

**If you are looking for a Docker image with ACL2 in it, please see the [INSTALL.md](INSTALL.md) page.**

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

Images are built via GitHub Actions workflow dispatch. Only repository maintainers can trigger builds.

### Workflow Inputs

| Input | Description |
|-------|-------------|
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
