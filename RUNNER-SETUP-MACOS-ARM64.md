# Setting Up Your Mac as a Self-Hosted ARM64 Runner

*(This file was formerly named `RUNNER-SETUP.md`.  It covers the macOS ARM64
runner used by the **multi-platform** workflow's `build-arm64` job and the
**kcerts** workflow's `build-kcerts-arm64` job (which certifies the
kestrel/top books for arm64 — give Docker Desktop plenty of memory, 32 GB
recommended, before dispatching kcerts).  For the Ubuntu x86-64 runner used
by the **kcerts** and **allcerts** workflows' amd64 jobs, see
[RUNNER-SETUP-UBUNTU-AMD64.md](RUNNER-SETUP-UBUNTU-AMD64.md).)*

This guide is for `KestrelInstitute/acl2-docker` maintainers who want to enable
ARM64 Docker builds on their own Apple Silicon Mac. Once your Mac is registered
as a self-hosted runner, the `docker-multiplatform-selfhosted.yml` workflow will
use it for the `build-arm64` job whenever you (or another maintainer) trigger a
build.

**Why you have to do this locally:** GitHub-hosted ARM64 runners use Ampere /
Neoverse server CPUs that do not implement floating-point exception traps. ACL2
requires FP traps. Apple Silicon does support them, and Docker Desktop on a Mac
runs Linux containers in a VM that uses Apple's FP hardware. See the
"Technical Details" section of [README.md](README.md) for more.

## Prerequisites

- Apple Silicon Mac (M1 / M2 / M3 / M4)
- Docker Desktop installed and running
- Admin access to the `KestrelInstitute/acl2-docker` repository (required to
  generate the registration token)
- GitHub CLI (`gh`) is convenient but not required for the runner itself

## Step 1: Make sure Docker Desktop is running

```bash
docker info | grep -i "operating system"
```

If Docker isn't running, start Docker Desktop from the Applications folder.

## Step 2: Register your Mac as a runner

1. As a repo admin, go to:
   <https://github.com/KestrelInstitute/acl2-docker/settings/actions/runners/new?arch=arm64&os=osx>

   GitHub displays a warning at the top of this page:
   **"Using self-hosted runners in public repositories is not recommended."**
   That warning is correct for the general case but does **not** apply to this
   repository:

   - The warning exists because, in a typical public repo, anyone can open a
     pull request from a fork, and that PR's workflow could execute
     attacker-supplied code on your self-hosted runner.
   - This repository's workflow runs on `workflow_dispatch` only. It is not
     triggered by `pull_request` or `push` events. Only users with write access
     to `KestrelInstitute/acl2-docker` can start a build; forks cannot.
   - As long as that remains true (see the `on:` block at the top of
     `.github/workflows/docker-multiplatform-selfhosted.yml`), the self-hosted
     runner is safe to use here.

   If a future workflow change adds a `pull_request` or `push` trigger, this
   reasoning no longer holds and the runner should be reconsidered.

2. That page displays a sequence of terminal commands with a fresh registration
   token issued for your admin session already filled in. The commands look
   roughly like this (copy them from the page so you get the current runner
   version and a valid token):

   ```bash
   # Pick any directory; ~/actions-runner is the GitHub convention but any
   # location works.
   mkdir -p ~/actions-runner && cd ~/actions-runner

   # Download (version shown on the GitHub page; e.g. 2.334.0 as of 2026-04)
   curl -o actions-runner-osx-arm64-X.XXX.X.tar.gz -L \
     https://github.com/actions/runner/releases/download/vX.XXX.X/actions-runner-osx-arm64-X.XXX.X.tar.gz
   tar xzf ./actions-runner-osx-arm64-*.tar.gz

   # Register against this repo (token from the page; expires in 1 hour)
   ./config.sh --url https://github.com/KestrelInstitute/acl2-docker --token YOUR_TOKEN_HERE
   ```

3. `./config.sh` will ask several questions. **Press Enter to accept the
   default for every prompt:**

   - **Runner group** — press Enter for `Default`.
   - **Runner name** — press Enter to use your Mac's hostname.
   - **Additional labels** — press Enter to skip. The default labels
     `self-hosted, macOS, ARM64` are exactly what the workflow looks for in
     `.github/workflows/docker-multiplatform-selfhosted.yml`:
     ```yaml
     runs-on: [self-hosted, macOS, ARM64]
     ```
   - **Work folder** — press Enter for `_work`.

   Successful registration ends with `√ Runner successfully added` and
   `√ Settings Saved.`

**You only need to do Step 2 once per machine.** Once `./config.sh` succeeds,
the runner stores its own long-lived credentials locally and starts cleanly
with `./run.sh` (or `./svc.sh start`) thereafter — no further token is needed.
The registration token shown on the GitHub page only matters during this
one-time setup; if you don't finish running `./config.sh` within an hour of
opening the page, refresh the page to get a new token.

**Exception — long idle periods.** GitHub automatically removes self-hosted
runners that have not connected to GitHub Actions for more than 14 days. If
you see this message when starting the runner:

```
Failed to create a session. The runner registration has been deleted from the
server, please re-configure. Runner registrations are automatically deleted
for runners that have not connected to the service recently.
```

you will need to re-register. You can reuse the same `~/actions-runner`
directory, but the local config files from the prior registration are still
there. To wipe the local configuration without contacting the server, do:

```bash
./config.sh remove --local
```

Then re-run Step 2 with a fresh registration token.

## Step 3: Start the runner

### For occasional use (foreground)

In a new Terminal:
```bash
cd ~/actions-runner
./run.sh
```

Leave the terminal open. The runner prints "Listening for Jobs" when ready, and
will pick up `build-arm64` jobs as the workflow dispatches them. When you are
done, press Ctrl+C to stop the runner.

### For persistent use (background service)

```bash
cd ~/actions-runner
./svc.sh install
./svc.sh start
./svc.sh status     # verify
```

The runner survives reboots. To stop:

```bash
./svc.sh stop
./svc.sh uninstall  # only if you want to remove the launchd service entirely
```

For additional `svc.sh` options, log file locations, and the underlying
launchd plist, see [GitHub: Configuring the self-hosted runner application as
a service](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/configuring-the-self-hosted-runner-application-as-a-service).

## Step 4: Test the workflow

With the runner listening, trigger the workflow (no push needed for a first
test):

```bash
gh workflow run docker-multiplatform-selfhosted.yml \
  --repo KestrelInstitute/acl2-docker
```

Or use the web UI at
<https://github.com/KestrelInstitute/acl2-docker/actions/workflows/docker-multiplatform-selfhosted.yml>.

The `build-arm64` job should be assigned to your Mac. You'll see job output
both in the Actions tab and in your runner's terminal (or in
`_diag/Runner_*.log` when running as a service).

## Runner upgrades

The runner auto-updates by default when it picks up a job, so you generally
do not need to track versions or upgrade manually. If you ever passed
`--disableupdate` to `./config.sh`, re-register without it to re-enable
auto-update.

## Security notes

- Self-hosted runners execute code from the workflow on your Mac, with access
  to your filesystem and Docker daemon. This is safe for `acl2-docker` because
  the workflow uses `on: workflow_dispatch` only — it can only be triggered by
  users with write access to the repo.
- Do **not** add a self-hosted runner to a public repository that accepts pull
  requests from untrusted contributors, unless you understand the implications.
- Anyone who can write to the workflow file can run arbitrary code on your
  runner. Restrict write access to `KestrelInstitute/acl2-docker` accordingly.

## Troubleshooting

### Runner doesn't pick up jobs

1. Confirm the runner is online at:
   <https://github.com/KestrelInstitute/acl2-docker/settings/actions/runners>
2. Verify the labels are exactly `self-hosted, macOS, ARM64` (case-sensitive).
3. Make sure Docker Desktop is running.

### Build fails with "no space left on device"

Stopped containers and untagged (dangling) intermediate images accumulate
across builds. Clear them without touching your tagged images or the build
cache:

```bash
docker system prune
```

If that doesn't free enough space, more aggressive options exist (e.g.
`docker image prune -a` removes all unused tagged images, and
`docker system prune -a` additionally wipes the build cache, costing tens of
minutes on the next build because the SBCL-from-source stage has to be
redone).

### Service won't start

```bash
cd ~/actions-runner
./svc.sh uninstall
./svc.sh install
./svc.sh start
```

### Removing the runner

Get the remove token from:
<https://github.com/KestrelInstitute/acl2-docker/settings/actions/runners>

```bash
cd ~/actions-runner
./config.sh remove --token YOUR_REMOVE_TOKEN
```

## References

- [Workflow file](.github/workflows/docker-multiplatform-selfhosted.yml) —
  the `runs-on:` label list, the `on: workflow_dispatch` trigger, and the
  `build-arm64` job referenced throughout this doc.
- [`actions/runner` GitHub repository](https://github.com/actions/runner) —
  source of the runner binary, release notes, and the
  `config.sh` / `run.sh` / `svc.sh` scripts.
