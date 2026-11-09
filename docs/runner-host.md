# runner-host

Host GitHub Actions jobs for an org on a Mac, each in a throwaway Tart VM.

```bash
jb-runner-host image      # build the clean image (once, and to upgrade)
jb-runner-host install    # LaunchDaemon: run jobs from boot (uses sudo)
jb-runner-host status     # daemon, VMs, and the org's registered runners
jb-runner-host uninstall  # remove the daemon and any job VMs (uses sudo)
```

The script is `src/just_bashit/runner-host.sh`. It needs macOS on Apple
silicon, [Tart](https://github.com/cirruslabs/tart/releases), `curl` and `jq`.

## Why a VM per job

A self-hosted runner gets no container and no fresh machine of its own, and
`container:` jobs are Linux-only. A runner on the bare host would run every
job as the account someone also uses for their own macOS testing.

So each job gets a fresh VM:

1. `image` clones a Cirrus Labs macOS base image, pinned by digest, and
    installs a pinned actions/runner (checked against its SHA-256) and the
    `JB_RUNNER_BREW` packages. It saves the result as `jb-base`.
1. `run`, which the LaunchDaemon runs, loops: it mints a registration
    token, clones `jb-base`, boots the clone headless, registers an
    `--ephemeral` runner in it, runs exactly one job, and deletes the VM.
    A failed job still deletes its VM. VMs left behind by a crash or reboot
    are deleted when `run` starts.

One VM runs at a time, with 4 cores and 8 GB by default. That leaves the host
usable, and stays within Apple's licence, which allows two macOS VMs per Mac.

## The token

`run` needs a fine-grained personal access token. Its resource owner is the
org, with the Organization permission **Self-hosted runners: Read and write**.
Save it, mode 600, at `~/.config/jb-runner/token`. `run` and `install` refuse
a token file another account can read, one owned by another user, or a
symlink.

The token never enters a VM. It reaches `curl` as a header on stdin, so no
`ps` on the host can see it. Each VM gets only a short-lived registration
token, also on stdin.

## Before it takes jobs from public repos

A fork PR on a self-hosted runner runs a stranger's code on your machine.
Keep the org runner group's **Allow public repositories** setting off until
every workflow keeps fork PRs on GitHub-hosted runners
([just-buildit.github.io#203](https://github.com/just-buildit/just-buildit.github.io/issues/203)).
Until then, the runner registers and sits idle.

That gate treats a label shaped like a GitHub-hosted image name (`ubuntu-*`,
`macos-*`, `windows-*`) as GitHub-hosted. So `run` and `install` refuse such a
label, after trimming spaces: a runner carrying `macos-latest` would take fork
jobs.

## Network

A job can reach the internet and nothing private. Measured from inside a job
VM on 2026-11-08 (Tart 2.41.1, Softnet 0.24.1):

| Target                                             | Tart's default NAT | Softnet, as `run` boots it |
| -------------------------------------------------- | ------------------ | -------------------------- |
| This Mac, through the VM's gateway (ssh, rapportd) | reachable          | blocked                    |
| This Mac's LAN address, the router                 | reachable          | blocked                    |
| Tailnet nodes (100.64.0.0/10), ssh                 | reachable          | blocked                    |
| The internet (github.com over HTTPS)               | reachable          | reachable                  |

Tart's default network NATs the VM through this Mac, so a job could reach
everything the Mac can. So every VM boots with `--net-softnet-block` over
the RFC 1918 ranges and 100.64.0.0/10 (`JB_RUNNER_NET_BLOCK`). Softnet already
drops other non-global IPv4. Blocking the private ranges also closes the
gateway, which is this Mac and picks a fresh private subnet each boot. That
gateway would otherwise answer DNS, so `image` sets the VM's resolvers to
`JB_RUNNER_DNS` (1.1.1.1, 8.8.8.8). The host has no IPv6, and a VM gets no
IPv6 route.

Softnet needs root to create the VM's network, so it is installed setuid root.
It drops privileges after setup. Tart runs whichever `softnet` is first on its
PATH, so `run` puts `JB_RUNNER_SOFTNET` (`/usr/local/bin/softnet`) first. A
`softnet` someone drops in `~/.local/bin` is never used. `run` and `image`
refuse to start, rather than fall back to the open network, unless that file:

- is a real file (not a symlink), setuid, and owned by root;
- is writable by no group or other, and so is every directory above it. A
    sticky root-owned directory such as `/tmp` is allowed.

A setuid-root binary that anyone else can replace is a root escalation. Install a release pinned by
its SHA-256, from
[cirruslabs/softnet](https://github.com/cirruslabs/softnet/releases):

```bash
sudo install -o root -g wheel -m 4755 softnet /usr/local/bin/softnet
```

## Configuration

Every setting is an environment variable. `--help` lists them all. `install`
writes the values it was run with into the LaunchDaemon, so the daemon runs
the configuration you tested. Run `install` as the runner's user, not under
`sudo`: it calls `sudo` itself, and refuses to run as root.

VM and runner names carry the host's short name (`jb-job-<host>-<time>`), so
two Macs registering to one org never replace each other's runners. `run` and
`image` take a lock (`JB_RUNNER_LOCK`), so a manual `run --once` cannot sweep
the daemon's live VM, and `image` cannot replace the image under a clone. A
lock left by a killed process, or by one from before a reboot, is taken over.

Each job puts `~/.local/bin` first in the runner's `.path`, after `config.sh`
writes it.
Nothing else is baked in for CI: workflows install uv and Python with their
usual setup actions, into the runner's tool cache.
`JB_RUNNER_VERSION` and `JB_RUNNER_SHA256` pin actions/runner. Runners are
registered with `--disableupdate`, and GitHub stops sending jobs to a runner
more than 30 days behind the latest release. So re-pin and re-run `image` at
least monthly.

The daemon logs to `~/Library/Logs/jb-runner.log`.
