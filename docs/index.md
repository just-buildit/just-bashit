---
title: ""
hide:
  - title
---

<p class="jb-wordmark"><img src="assets/logo-wordmark.svg" alt="just-bashit"></p>

<p class="jb-tagline">One curl. Any machine. Your shell.</p>

<p class="jb-lede">A bare Linux, macOS or WSL box becomes a working dev
machine in one command, and every script runs straight from a URL with
nothing installed.</p>

```bash
. <(curl -sSL https://just-buildit.github.io/get-jb.sh)   # jbx, in this shell
jbx setup-system                                          # the rest of the box
```

<div class="jb-cards">
  <div class="jb-card">
    <h3>Any box &rarr; your box</h3>
    <p>Packages, compiler, shell config, git, uv, PowerShell and Claude Code.
    One ssh key per machine, reused across every WSL distro and checked
    against GitHub. It ends by listing exactly what is installed, and
    applies the changes to the shell you ran it from.</p>
    <a href="setup-system/">setup-system &rarr;</a>
  </div>
  <div class="jb-card">
    <h3>Run it, don't install it</h3>
    <p><code>jbx</code> fetches a script by name or URL, calls one function
    and discards it. Cached, hash-pinnable, and nothing left on
    <code>PATH</code>.</p>
    <a href="just-runit/">jbx &rarr;</a>
  </div>
  <div class="jb-card">
    <h3>Bash you can trust</h3>
    <p>shellcheck-clean, shfmt-formatted, and 500+ bats tests on Debian,
    Arch, Fedora, Alpine, macOS and Windows for every change.</p>
    <a href="https://github.com/just-buildit/just-bashit/actions/workflows/ci.yml">CI &rarr;</a>
  </div>
</div>

[![CI](https://github.com/just-buildit/just-bashit/actions/workflows/ci.yml/badge.svg)](https://github.com/just-buildit/just-bashit/actions/workflows/ci.yml)
[![Coverage](https://img.shields.io/endpoint?url=https://just-buildit.github.io/just-bashit/coverage-badge.json)](https://just-buildit.github.io/just-bashit/coverage/)
[![shellcheck](https://img.shields.io/badge/shellcheck-enabled-brightgreen)](https://www.shellcheck.net/)
[![shfmt](https://img.shields.io/badge/shfmt-conformant-blue)](https://github.com/mvdan/sh#shfmt)
[![bats](https://img.shields.io/badge/tested%20with-bats-brightgreen)](https://github.com/bats-core/bats-core)
[![pre-commit](https://img.shields.io/badge/pre--commit-enabled-brightgreen?logo=pre-commit)](https://github.com/pre-commit/pre-commit)
[![GitHub release](https://img.shields.io/github/v/release/just-buildit/just-bashit)](https://github.com/just-buildit/just-bashit/releases)

[Coverage Report](https://just-buildit.github.io/just-bashit/coverage/) · [Test Report](https://just-buildit.github.io/just-bashit/test-report/)

## Quick Start

On any Linux, macOS or WSL box (only `bash` and `curl` needed):

```bash
. <(curl -sSL https://just-buildit.github.io/get-jb.sh)
jbx setup-system --dry-run      # read the plan first
jbx setup-system
```

The whole walk-through, and how to check it worked, is
[Setting up a new machine](guides/new-machine.md).

To use the libraries in your own scripts, unpack a release and source what
you need. They depend on each other, so keep the package whole:

```bash
tar xf just-bashit.tar.gz
. just-bashit/src/just_bashit/datetime.sh
iso-8601-basic
# 20260522T143200Z
```

## CLI Tools

| Tool                                | Purpose                                                           |
| ----------------------------------- | ----------------------------------------------------------------- |
| [bootstrap.toml](bootstrap-toml.md) | The manifest — system packages and fetched tools                  |
| [just-runit](just-runit.md)         | Ephemeral runner — fetch a script, call a function, discard       |
| [install-deps](install-deps.md)     | Install packages declared in a `bootstrap.toml` / `jb-deps.toml`  |
| [setup-system](setup-system.md)     | Take a fresh machine to a working one — packages, shell, ssh, git |
| [inspect](inspect.md)               | Snapshot installed package versions into a `.versions` file       |

## Guides

- [Setting up a new machine](guides/new-machine.md) — bare OS to a working
    shell, what lands on disk, and how to check it worked

## Libraries

| Library                                 | Functions                                               |
| --------------------------------------- | ------------------------------------------------------- |
| [datetime](libraries/datetime.md)       | `iso-8601-basic`                                        |
| [environment](libraries/environment.md) | `set-bashrc` `unset-bashrc` `check-command-exists`      |
| [file](libraries/file.md)               | `add-line` `remove-line` `add-contents`                 |
| [format](libraries/format.md)           | `trim-from` `color-echo`                                |
| [logging](libraries/logging.md)         | `log` `log-wait`                                        |
| [make-run](libraries/make-run.md)       | `mk-var` `mk-vars` `mk-run` `mk-has` `mk-origin`        |
| [match](libraries/match.md)             | `is-number`                                             |
| [network](libraries/network.md)         | `test-internet-access`                                  |
| [path](libraries/path.md)               | `get-scriptpath` `set-scriptpath`                       |
| [pkg](libraries/pkg.md)                 | `get-pkg-mgr` `get-pkg-version`                         |
| [toml](libraries/toml.md)               | `toml_get` `toml_discover_groups` `toml_discover_tools` |

## Platform Support

Tested on every release across six platforms:

| Platform              | Package manager |
| --------------------- | --------------- |
| Debian (latest)       | apt             |
| Arch Linux (latest)   | pacman          |
| Fedora (latest)       | dnf             |
| Alpine Linux (latest) | apk             |
| macOS (latest)        | brew            |
| Windows (MSYS2 bash)  | winget          |

## Templates

See [Templates](templates.md) for copy-paste starting points: a full-featured
function template with getopts, a minimalist variant, an executable script
template with strict mode and exit traps, and the opinionated bash
configuration [setup-system](setup-system.md) installs.
