# Installing and Running ACL2 Docker Images

For ACL2 documentation, tutorials, and reference material, see:
- [ACL2 Documentation](https://www.cs.utexas.edu/~moore/acl2/) - Official ACL2 homepage
- [ACL2 Manual](https://acl2.org/doc/) - Searchable online documentation

## Quick Start

```bash
# 1. Pull the image
docker pull ghcr.io/kestrelinstitute/acl2:latest

# 2. Get a shell in the container
#    Note: the --rm flag means to clean up the container after exit.
docker run -it --rm ghcr.io/kestrelinstitute/acl2:latest bash

# 3. Certify the books you need (use -j for parallel jobs)
cd books
cert.pl -j4 std/lists/top

# 4. Run ACL2
acl2

# 5. Include the book you certified
(include-book "std/lists/top" :dir :system)
```

Type `(quit)` to exit ACL2, and `exit` to leave the container.

---

## Setup

### Prerequisites

Install Docker for your platform:
- **Linux**: [Docker Engine](https://docs.docker.com/engine/install/)
- **macOS**: [Docker Desktop](https://www.docker.com/products/docker-desktop/) (Intel and Apple Silicon)
- **Windows**: [Docker Desktop](https://www.docker.com/products/docker-desktop/) (follow instructions to install WSL 2 if needed)

### Available Images

Images are hosted on GitHub Container Registry: `ghcr.io/kestrelinstitute/acl2`

| Tag | Description | Git Status |
|-----|-------------|------------|
| `latest` | Most recent master build | On `master` branch, `git pull origin master` works |
| `master-abc1234` | Built from master at commit abc1234 | On `master` branch, `git pull origin master` works |
| `commit-abc1234` | Built from specific commit abc1234 | Detached HEAD, see "Updating ACL2" section |

Images are multi-platform (linux/amd64 for Linux/Windows, linux/arm64 for macOS). Docker automatically pulls the correct architecture.

### Verifying Image Authenticity

The amd64 image includes build provenance attestation.  You can view attestation status on the [GitHub package page](https://github.com/orgs/KestrelInstitute/packages/container/package/acl2).

Alternatively, if you have the GitHub CLI, you can do this:

```bash
gh attestation verify oci://ghcr.io/kestrelinstitute/acl2:latest --owner KestrelInstitute
```

---

## Running a Container

### Mounting Local Files

To access your local files from inside the container, use the `-v` flag. Your files will be available at `/work` inside the container.

**Linux:**
```bash
docker run -it --rm -v /path/to/your/books:/work ghcr.io/kestrelinstitute/acl2:latest bash
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

The image includes ACL2 ready to run, plus all ACL2 books as source code, but they are not pre-certified.

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

After updating, rebuild the ACL2 executable:

```bash
make LISP=`which sbcl`
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

After updating, rebuild the ACL2 executable:

```bash
make LISP=`which sbcl`
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
