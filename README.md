<!-- START FRONTMATTER - USER CONTENT BELOW -->

[![CI](https://github.com/just-buildit/just-bashit/actions/workflows/ci.yml/badge.svg)](https://github.com/just-buildit/just-bashit/actions/workflows/ci.yml)
[![Coverage](https://img.shields.io/endpoint?url=https://just-buildit.github.io/just-bashit/coverage-badge.json)](https://just-buildit.github.io/just-bashit/coverage/)
[![shellcheck](https://img.shields.io/badge/shellcheck-enabled-brightgreen)](https://www.shellcheck.net/)
[![shfmt](https://img.shields.io/badge/shfmt-conformant-blue)](https://github.com/mvdan/sh#shfmt)
[![bats](https://img.shields.io/badge/tested%20with-bats-brightgreen)](https://github.com/bats-core/bats-core)
[![pre-commit](https://img.shields.io/badge/pre--commit-enabled-brightgreen?logo=pre-commit)](https://github.com/pre-commit/pre-commit)

[Coverage Report](https://just-buildit.github.io/just-bashit/coverage/) · [Test Report](https://just-buildit.github.io/just-bashit/test-report/)

<!-- END FRONMATTER - BEGIN USER CONTENT -->

# just-bashit

**One curl. Any machine. Your shell.**

Turns a bare Linux, macOS or WSL box into a dev box, taking only the parts
you choose. Get `jbx` (only `bash` and `curl` needed), then read the plan
before anything changes:

```bash
. <(curl -sSL https://just-buildit.github.io/get-jb.sh)   # jbx, in this shell
jbx setup-system --dry-run                                # the plan, no changes
```

Then take the lot, or just the parts you want:

```bash
jbx setup-system                   # everything below
jbx setup-system -s shell,ssh,git  # only these
jbx setup-system -x claude,pwsh    # all but these
```

| Step     | What you get                                        |
| -------- | --------------------------------------------------- |
| `deps`   | compiler, make, cmake, git, curl, ssh, gpg, age     |
| `shell`  | bash config, one source line in `~/.bashrc`         |
| `ssh`    | permissions fixed; a host key only if you have none |
| `git`    | defaults only where you haven't set one             |
| `tools`  | uv, plus pre-commit hooks in a repo that has them   |
| `pwsh`   | PowerShell 7 + PSScriptAnalyzer                     |
| `claude` | Claude Code                                         |

`certs` and `sshd` run only when you name them; on native Windows `sshd`
and `folders` run by default.
[Every step in full](https://just-buildit.github.io/just-bashit/setup-system/) ·
[Setting up a new machine](https://just-buildit.github.io/just-bashit/guides/new-machine/)

shellcheck-clean, shfmt-formatted, and 500+ bats tests on Debian, Arch,
Fedora, Alpine, macOS and Windows for every change.

**[Documentation](https://just-buildit.github.io/just-bashit/)**

## Install

The commands above are the install. On Windows, from PowerShell — no bash
window to open:

```powershell
irm https://just-buildit.github.io/get-jb.ps1 | iex   # jbx, as a PowerShell function
jbx setup-system --dry-run
```

Or as a Python tool:

```bash
uv tool install just-bashit   # or: pip install just-bashit
```

That puts `jb`, `jbx` (ephemeral runner — fetch a script, call a function,
discard) and `jb-inspect` on `PATH`.

Nothing needs installing to *use* a script. `jbx` fetches on demand:

```bash
jbx install-deps                              # install this repo's packages
jbx make-run mk-var -C ~/doppler DOCS_BUILD_CMD
```

## Getting Started

A release package contains shell libraries along with script and function
templates for developing your own tools.

```
just-bashit
    +--README.md
    +--src/just_bashit/
    |   +-- datetime.sh
    |   +-- environment.sh
    :   :
    |   +-- function-template.sh
    |   +-- script-template
    +--test-results/
```

Some libraries depend on others so it's best to use the whole package and source whatever you need, for example:

```bash
. just-bashit/src/just_bashit/datetime.sh # contains iso-8601-basic()
iso-8601-basic -d '10:32 AM EDT Jan 5 1982'
19820105T143200Z
```

## Ask a repo what its commands are

`make-run` resolves a repository's targets and command variables from that
repository's own `Makefile`, so nothing downstream has to carry a second copy
of a command that will drift from it:

```bash
jbx make-run mk-var -C ~/doppler DOCS_BUILD_CMD
# uv run --group docs zensical build --clean --strict

jbx make-run mk-run -C ~/doppler docs   # run it, whatever it is
```

An **undefined** variable is an error, never an empty string — see
[the docs](https://just-buildit.github.io/just-bashit/libraries/make-run/).
