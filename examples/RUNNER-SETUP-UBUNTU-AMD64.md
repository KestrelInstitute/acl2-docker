# Setting Up an Ubuntu Server as a Self-Hosted x86-64 Runner

This guide is for `KestrelInstitute/acl2-docker` maintainers who want to run
the amd64 jobs of the **kcerts** and **allcerts** workflows
(`docker-kcerts-selfhosted.yml` and `docker-allcerts-selfhosted.yml`) on
their own Ubuntu x86-64 machine.  Those workflows build:

- `ghcr.io/kestrelinstitute/acl2-kcerts` (amd64 half): all books reachable
  from `kestrel/top` certified, with the STP and Z3 solvers included.
- `ghcr.io/kestrelinstitute/acl2-allcerts`: a linux/amd64 image in which
  **all books of the standard ACL2 regression are certified**, with STP and
  Z3 included.

(For the macOS ARM64 runner used by the multi-platform and kcerts workflows,
see [RUNNER-SETUP-MACOS-ARM64.md](RUNNER-SETUP-MACOS-ARM64.md).)

**Why self-hosted:** a large book certification is far too big for
GitHub-hosted runners (6-hour job limit, ~7 GB RAM, small disk).  These
builds want a beefy machine: many cores, lots of RAM, lots of disk.

## Prerequisites

- x86-64 machine running Ubuntu 22.04 LTS (or later).  The *host* OS version
  does not need to match the image's base (Ubuntu 24.04) - the build runs
  entirely inside Docker.
- **Docker Engine** installed (see Step 1).
- **RAM:** 32 GB or more recommended.  Each parallel certification job is an
  SBCL process; a few books are memory-hungry.  A reasonable rule of thumb is
  jobs ≈ min(cores, RAM / 4 GB); the workflow's `cert_jobs` input lets you
  set this (blank = all cores).
- **Disk:** 200+ GB free for Docker (`/var/lib/docker`) recommended.  The
  allcerts image is tens of GB, and the build additionally holds
  intermediate layers and the Docker build cache.
- Admin access to the `KestrelInstitute/acl2-docker` repository (required to
  generate the registration token).

## Step 1: Install Docker Engine

Follow the official instructions for Ubuntu:
<https://docs.docker.com/engine/install/ubuntu/>

The short version (Docker's apt repository):

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin
```

Then let the account that will run the Actions runner use Docker without sudo:

```bash
sudo usermod -aG docker $USER
# log out and back in (or run: newgrp docker), then verify:
docker run --rm hello-world
```

## Step 2: Register the machine as a runner

1. As a repo admin, go to:
   <https://github.com/KestrelInstitute/acl2-docker/settings/actions/runners/new?arch=x64&os=linux>

   GitHub displays a warning at the top of this page:
   **"Using self-hosted runners in public repositories is not recommended."**
   That warning is correct for the general case but does **not** apply to this
   repository:

   - The warning exists because, in a typical public repo, anyone can open a
     pull request from a fork, and that PR's workflow could execute
     attacker-supplied code on your self-hosted runner.
   - This repository's workflows run on `workflow_dispatch` only.  They are
     not triggered by `pull_request` or `push` events.  Only users with write
     access to `KestrelInstitute/acl2-docker` can start a build; forks cannot.
   - As long as that remains true (see the `on:` blocks in
     `.github/workflows/`), the self-hosted runner is safe to use here.

   If a future workflow change adds a `pull_request` or `push` trigger, this
   reasoning no longer holds and the runner should be reconsidered.

2. That page displays a sequence of terminal commands with a fresh
   registration token issued for your admin session already filled in.  The
   commands look roughly like this (copy them from the page so you get the
   current runner version and a valid token):

   ```bash
   # Pick any directory; ~/actions-runner is the GitHub convention.
   mkdir -p ~/actions-runner && cd ~/actions-runner

   # Download (version shown on the GitHub page)
   curl -o actions-runner-linux-x64-X.XXX.X.tar.gz -L \
     https://github.com/actions/runner/releases/download/vX.XXX.X/actions-runner-linux-x64-X.XXX.X.tar.gz
   tar xzf ./actions-runner-linux-x64-*.tar.gz

   # Register against this repo (token from the page; expires in 1 hour)
   ./config.sh --url https://github.com/KestrelInstitute/acl2-docker --token YOUR_TOKEN_HERE
   ```

3. `./config.sh` asks several questions.  **Press Enter to accept the default
   for every prompt:**

   - **Runner group** - press Enter for `Default`.
   - **Runner name** - press Enter to use the machine's hostname.
   - **Additional labels** - press Enter to skip.  The default labels
     `self-hosted, Linux, X64` are exactly what the workflows look for in
     `.github/workflows/docker-kcerts-selfhosted.yml` and
     `.github/workflows/docker-allcerts-selfhosted.yml`:
     ```yaml
     runs-on: [self-hosted, Linux, X64]
     ```
     (The macOS runner for the multi-platform workflow has different labels,
     so the two workflows can never grab each other's runners.)
   - **Work folder** - press Enter for `_work`.

   Successful registration ends with `√ Runner successfully added` and
   `√ Settings Saved.`

**You only need to do Step 2 once per machine.**  Once `./config.sh` succeeds,
the runner stores its own long-lived credentials locally and starts cleanly
with `./run.sh` (or as a service) thereafter - no further token is needed.

**Exception - long idle periods.**  GitHub automatically removes self-hosted
runners that have not connected to GitHub Actions for more than 14 days.  If
you see this message when starting the runner:

```
Failed to create a session. The runner registration has been deleted from the
server, please re-configure.
```

wipe the local configuration and re-register with a fresh token:

```bash
./config.sh remove --local
```

Then re-run Step 2.

## Step 3: Start the runner

### For occasional use (foreground)

```bash
cd ~/actions-runner
./run.sh
```

Leave the terminal open (or run it under `tmux`/`screen`).  The runner prints
"Listening for Jobs" when ready.  Press Ctrl+C to stop.

### For persistent use (systemd service)

```bash
cd ~/actions-runner
sudo ./svc.sh install    # optionally: sudo ./svc.sh install USERNAME
sudo ./svc.sh start
sudo ./svc.sh status     # verify
```

The runner survives reboots.  To stop:

```bash
sudo ./svc.sh stop
sudo ./svc.sh uninstall  # only to remove the systemd service entirely
```

See [GitHub: Configuring the self-hosted runner application as a
service](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/configuring-the-self-hosted-runner-application-as-a-service).

### The runner must be listening when you dispatch

Unless you set the runner up as a service, it is not listening by default —
someone has to start it.  A job dispatched while its runner is offline does
not fail: it sits as "Queued" for up to 24 hours and is then cancelled by
GitHub.  So if a dispatched workflow seems to hang at "Queued", check that
the runner shows "Listening for Jobs" (foreground) or that the service is
running, and check the runner's status on the repository's
Settings → Actions → Runners page ("Idle" means listening; "Offline" means
it is not).

## Step 4: Test the workflow

With the runner listening, trigger a **test build without pushing**:

```bash
gh workflow run docker-allcerts-selfhosted.yml \
  --repo KestrelInstitute/acl2-docker \
  -f push_to_registry=false
```

Or use the web UI at
<https://github.com/KestrelInstitute/acl2-docker/actions/workflows/docker-allcerts-selfhosted.yml>.

The `build-allcerts` job should be assigned to your machine.  (For the
kcerts workflow it is the `build-kcerts-amd64` job; note that dispatching
kcerts also requires the macOS ARM64 runner to be online.)  Expect the
first build to be slow (SBCL and STP are compiled from source before the
certification even starts); later builds reuse those layers from the Docker
cache.  On a large server the full regression itself takes on the order of
an hour; on a modest machine it can take many hours.

## Runner upgrades

The runner auto-updates by default when it picks up a job.  If you ever
passed `--disableupdate` to `./config.sh`, re-register without it.

## Security notes

- Self-hosted runners execute code from the workflow on your machine, with
  access to your filesystem and Docker daemon.  This is safe for
  `acl2-docker` because all workflows use `on: workflow_dispatch` only - they
  can only be triggered by users with write access to the repo.
- Do **not** add a self-hosted runner to a public repository that accepts
  pull requests from untrusted contributors, unless you understand the
  implications.
- Anyone who can write to the workflow files can run arbitrary code on your
  runner.  Restrict write access to `KestrelInstitute/acl2-docker`
  accordingly.

## Troubleshooting

### Runner doesn't pick up jobs

1. Confirm the runner is online at:
   <https://github.com/KestrelInstitute/acl2-docker/settings/actions/runners>
2. Verify the labels are exactly `self-hosted, Linux, X64` (case-sensitive).
3. Make sure the Docker daemon is running: `docker info`.

### Build fails with "permission denied ... docker.sock"

The runner's user is not in the `docker` group (see Step 1).  After
`usermod -aG docker`, restart the runner service so it picks up the group.

### Build fails with "no space left on device"

The image with certified books is large and its build cache is large.
Clean up between builds:

```bash
docker system prune          # stopped containers + dangling images
docker image prune -a        # ALSO removes unused tagged images (e.g. old
                             # certified builds) - frees a lot more
```

Note that pruning build cache or base layers means the next build redoes the
SBCL/STP compilation stages (tens of minutes) before the regression.

### Regression failures

The build is strict: any book that fails to certify fails the build, and no
image is pushed.  The failed books are listed at the end of the build step's
log (under "REGRESSION FAILED"); details for each book appear earlier in the
log - search for "CERTIFICATION FAILED".  A transiently broken ACL2 `master`
is usually fixed quickly; re-run the workflow later, or pass a known-good
commit via the `acl2_ref` input.

## References

- [kcerts workflow file](.github/workflows/docker-kcerts-selfhosted.yml)
- [allcerts workflow file](.github/workflows/docker-allcerts-selfhosted.yml)
- [`actions/runner` GitHub repository](https://github.com/actions/runner)
