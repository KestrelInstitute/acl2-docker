# Installing and Running ACL2 Docker Images

For ACL2 documentation, tutorials, and reference material, see:
- [ACL2 Documentation](https://www.cs.utexas.edu/~moore/acl2/) - Official ACL2 homepage
- [ACL2 Manual](https://acl2.org/doc/) - Searchable online documentation

Three images are available:

- **`ghcr.io/kestrelinstitute/acl2`** — lean, multi-platform (amd64 + arm64).
  Books are included as source and you certify the ones you need.
- **`ghcr.io/kestrelinstitute/acl2-kcerts`** — medium, multi-platform
  (amd64 + arm64).  All books reachable from `kestrel/top` are **already
  certified**, and the STP (Axe) and Z3 (Smtlink) solvers are included.
- **`ghcr.io/kestrelinstitute/acl2-allcerts`** — large, amd64 only.
  All books of the standard regression suite are **already certified**, and
  STP and Z3 are included.

See "The Images With Certified Books" below for the latter two.

## Quick Start

1. Pull the image
```bash
docker pull ghcr.io/kestrelinstitute/acl2:latest
```

2. Get a shell in the container. Note: the --rm flag means to clean up the container after exit.
```bash
docker run -it --rm ghcr.io/kestrelinstitute/acl2:latest bash
```

Then inside the container:

3. Certify the books you need (use -j for parallel jobs)
```bash
cd books && cert.pl -j4 std/lists/top
```

4. Run ACL2
```bash
acl2
```

Then inside ACL2:

5. Include the book you certified
```lisp
(include-book "std/lists/top" :dir :system)
```

Type `(quit)` to exit ACL2, and `exit` to leave the container.

---

## The Images With Certified Books

The `acl2-kcerts` and `acl2-allcerts` images skip the "certify the books you
need" step for their book sets, so `include-book` works immediately for any
already-certified book:

- `acl2-kcerts`: `kestrel/top` and every book it depends on (a large portion
  of the community books, including the Kestrel libraries and Axe).
  Multi-platform (amd64 + arm64).
- `acl2-allcerts`: every book in the standard `make regression` suite.
  amd64 only.

```bash
docker pull ghcr.io/kestrelinstitute/acl2-kcerts:latest
docker run -it --rm ghcr.io/kestrelinstitute/acl2-kcerts:latest
# or, for the full-regression image (amd64 only):
docker pull ghcr.io/kestrelinstitute/acl2-allcerts:latest
docker run -it --rm ghcr.io/kestrelinstitute/acl2-allcerts:latest
```

That drops you directly into ACL2, where you can immediately do, e.g.:

```lisp
(include-book "std/lists/top" :dir :system)
(include-book "kestrel/axe/top" :dir :system)
```

Books outside an image's certified set are still present as source and can
be certified in the container as usual with `cert.pl`.

Notes:

- **Size**: these images are large (certificates plus compiled books for
  their whole book set; tens of GB for allcerts).  Make sure Docker has
  enough disk before pulling.
- **Platform**: `acl2-kcerts` is multi-platform.  `acl2-allcerts` is
  linux/amd64 only; it runs on Apple Silicon via emulation, but slowly —
  on arm64 machines prefer the kcerts or lean image.
- **Solvers included** (both images):
  - **STP** (for the Axe toolkit) is installed at `/usr/local/bin/stp`.
    Axe's `defthm-stp`, `prove-with-stp`, etc. work out of the box.  The
    default `ACL2_STP_VARIETY` (2) is correct for the installed STP; you can
    export a different value if you experiment with other STP versions.
  - **Z3 with Python bindings** (for Smtlink) lives in a virtualenv at
    `/root/.venvs/smtlink` (its `bin`, containing `z3` and `python`, is on
    `PATH`).  The Smtlink configuration `/root/smtlink-config` points at that
    Python by absolute path and was in place when the Smtlink books were
    certified.
- **Which books are certified**:
  - kcerts: `kestrel/top` and its dependency tree (certified with
    `cert.pl kestrel/top`).
  - allcerts: everything in `make regression`, which is all books except
    the `SLOW_BOOKS` list in `books/GNUmakefile` (a handful of very slow
    books, e.g. the x86isa and filesystem proof developments).
- **Removed artifacts**: to keep the image (relatively) small, files not
  needed by `include-book` were deleted after certification: `.cert.out`
  proof logs, `.cert.time`, `.acl2x`, `.pcert0`/`.pcert1`, `@expansion.lsp`,
  `workxxx`, and `.port` files of certified books.  Each certified book
  retains its source, its `.cert`, and its compiled `.fasl`.  (ACL2 reads
  `.port` files only when including *uncertified* books, so certified books
  do not need them.)  If you want to see a book's proof output, just
  re-certify it in the container.
- **`CERT_PL_RM_OUTFILES=1`** is set in the image, so books you certify
  yourself also have their `.cert.out` deleted on success (failures keep
  theirs, for debugging).  `unset CERT_PL_RM_OUTFILES` to change that.
- **Updating ACL2 inside these images** (git pull + `make update`) is possible
  but rarely useful: previously certified books become stale with respect to
  the new executable.  Prefer pulling a newer image build.

---

## Setup

### Prerequisites

Install Docker for your platform:
- **Linux**: [Docker Engine](https://docs.docker.com/engine/install/)
- **macOS**: [Docker Desktop](https://www.docker.com/products/docker-desktop/) (Intel and Apple Silicon)
- **Windows**: [Docker Desktop](https://www.docker.com/products/docker-desktop/) (follow instructions to install WSL 2 if needed)

### Available Images

Images are hosted on GitHub Container Registry, in three packages:

- `ghcr.io/kestrelinstitute/acl2` — lean, books not certified.  Multi-platform
  (linux/amd64 for Linux/Windows, linux/arm64 for macOS); Docker automatically
  pulls the correct architecture.
- `ghcr.io/kestrelinstitute/acl2-kcerts` — books reachable from `kestrel/top`
  certified, STP and Z3 included.  Multi-platform.
- `ghcr.io/kestrelinstitute/acl2-allcerts` — all regression books certified,
  STP and Z3 included.  linux/amd64 only.

See "The Images With Certified Books" above for the latter two.  All packages use the
same tagging scheme:

| Tag | Description | Git Status inside image |
|-----|-------------|-------------------------|
| `latest` | Most recent master build | On `master` branch, `git pull origin master` works |
| `master-abc1234` | Built from master at commit abc1234 | On `master` branch, `git pull origin master` works |
| `commit-abc1234` | Built from specific commit abc1234 | Detached HEAD, see "Updating ACL2" section |

### Verifying Image Authenticity

The amd64 image of the lean `acl2` package includes build provenance attestation.  You can view attestation status on the [GitHub package page](https://github.com/orgs/KestrelInstitute/packages/container/package/acl2).  (The arm64 image and the `acl2-kcerts` and `acl2-allcerts` packages are built on self-hosted runners and do not have attestation.)

Alternatively, if you have the GitHub CLI, you can do this:

```bash
gh attestation verify oci://ghcr.io/kestrelinstitute/acl2:latest --owner KestrelInstitute
```

---

## Running a Container

### Mounting Local Files

To access your local files from inside the container, use the `-v` flag. In the following examples your files will be available at `/work` inside the container.

**Linux:**
```bash
docker run -it --rm -v /path/to/my-acl2-project:/work ghcr.io/kestrelinstitute/acl2:latest bash
```

**macOS:**
```bash
docker run -it --rm -v ~/my-acl2-project:/work ghcr.io/kestrelinstitute/acl2:latest bash
```

**Windows** (PowerShell):
```powershell
docker run -it --rm -v C:\Users\YourName\acl2-project:/work ghcr.io/kestrelinstitute/acl2:latest bash
```

### Memory Configuration (macOS/Windows)

For large proof efforts, you may need to increase Docker Desktop's memory limit:

1. Open Docker Desktop
2. Go to **Settings** → **Resources** → **Advanced**
3. Increase **Memory** (At least 32 GB recommended for full ACL2 regression with `-j9`)
4. Click **Apply & Restart**

---

## Working with ACL2

### Certifying Books

The image includes ACL2 ready to run, plus all ACL2 books as source code, but they have not been certified.

When you certify a book, all the books it depends on are also certified. Since many books are independent of each other, we recommend using the `-j` option based on how many cores you have free.

```bash
# Certify a specific library, such as the Kestrel ARM model
cd books
cert.pl -j4 kestrel/arm/top
```

There are also `make` targets that certify groups of books:

```bash
# Certify the "basic" books (good for testing)
make -j4 basic

# Run the full certification regression (takes several hours)
make -j4 regression
```

### Saving an Image with Certified Books

By default, `docker run --rm` discards changes when you exit. To save your certified books for reuse:

1. Start the container **without** `--rm`:
   ```bash
   docker run -it ghcr.io/kestrelinstitute/acl2:latest bash
   ```

2. Certify your books, then exit the container.

3. Find your stopped container:
   ```bash
   docker ps -a
   ```

4. Save it as a new image.
   ```bash
   docker commit --change='CMD ["acl2"]' <container-id> my-acl2-certified:v1
   ```
   When you started the container with the `bash` command, it overwrote the default
   startup command of `acl2`.  The `--change` option restores that default.

5. Run your new image.  If you omit the command at the end, it will enter ACL2 automatically:
   ```bash
   docker run -it --rm my-acl2-certified:v1
   ```

---

## Maintenance

### Updating ACL2

#### Master Builds (`master-*` tags)

Images tagged `master-abc1234` are set up with proper Git branch tracking. You can update directly in the docker container.
If you do this, you will probably want to follow the instructions above
on starting the container without `--rm` and committing the result to a new image.

First get the updates:

```bash
cd /root/acl2
git pull origin master
```

After updating, rebuild the ACL2 executable if anything going into it has changed:

```bash
make update LISP=`which sbcl`
```

You may want to certify some books before committing the new docker image.

#### Commit Builds (`commit-*` tags)

Images tagged `commit-abc1234` are in Git "detached HEAD" mode. To update to the latest master, follow these instructions.
If you do this, you will probably want to follow the instructions above
on starting the container without `--rm` and committing the result to a new image.

First get the updates:

```bash
cd /root/acl2
git fetch origin master
git checkout -B master origin/master
```

After updating, rebuild the ACL2 executable if anything going into it has changed:

```bash
make update LISP=`which sbcl`
```

You may want to certify some books before committing the new docker image.

### Checking Image Version

The `latest` tag changes over time. To see what ACL2 commit a local image contains:

```bash
docker inspect ghcr.io/kestrelinstitute/acl2:latest --format '{{index .Config.Labels "org.opencontainers.image.revision"}}'
```

Or query git inside the container:
```bash
docker run --rm ghcr.io/kestrelinstitute/acl2:latest git -C /root/acl2 rev-parse HEAD
```

---

## Troubleshooting

### ACL2 runs out of memory (exit code 137)

If you get an error that includes the message
```
  Exit code from ACL2 is 137
```
it means ACL2 ran out of memory.

Increase Docker's memory allocation (see Memory Configuration section above) or run with fewer parallel jobs when certifying books.

### "No space left on device"

Docker images and containers can consume significant disk space. Clean up unused resources:

```bash
docker system prune
```

### Container exits immediately

Make sure to use `-it` flags for interactive sessions:
- `-i` keeps STDIN open
- `-t` allocates a pseudo-TTY

### Permission denied on mounted directory

On Linux, you may need to adjust permissions or use the `--user` flag:

```bash
docker run -it --rm --user $(id -u):$(id -g) -v /path:/work ghcr.io/kestrelinstitute/acl2:latest
```

### Keeping old images when updating

When you pull a new `acl2:latest`, the previous image loses its tag.  Sometimes
it remains on disk and shows up as `<none>` in `docker images`, and sometimes it becomes inaccessible.

To keep old images available and easily identifiable, you can also pull the specific tag when
you pull `latest`. You can find the current tag in the
[GitHub Container Registry](https://ghcr.io/kestrelinstitute/acl2).
The second pull just adds the tag — it doesn't re-download the image. For example:

```bash
docker pull ghcr.io/kestrelinstitute/acl2:latest \
&& docker pull ghcr.io/kestrelinstitute/acl2:master-abc1234
```

### Cleaning up old images

After pulling a new `acl2:latest`, the previous image may appear in
`docker images` as `<none>`:

```bash
REPOSITORY                      TAG               IMAGE ID       CREATED         SIZE
ghcr.io/kestrelinstitute/acl2   latest            9255e6ca65bc   2 hours ago     2.97GB
<none>                          <none>            76fb5f3e6a6a   47 hours ago    2.97GB
```

This can happen when the old `acl2:latest` is still referenced by a stopped
container (e.g., one that was run without `--rm`).  To clean up stopped containers
and untagged images:

```bash
docker system prune
```
