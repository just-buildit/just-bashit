---
title: ""
hide:
  - title
---

<div style="text-align:center; background:linear-gradient(135deg,#0d1b2a,#1a3050); border-radius:24px; padding:3rem 2rem; margin:1.5rem 0; border:1px solid #1e3a5f">
  <img src="assets/logo-wordmark.svg" alt="just-bashit" style="width:90%;max-width:560px">
</div>

Evolving set of [shfmt](https://github.com/mvdan/sh#shfmt)-conformant,
[bats](https://bats-core.readthedocs.io/en/stable/)-tested,
[shellcheck](https://www.shellcheck.net/)-linted bash tools, templates, and
more.

[![CI](https://github.com/just-buildit/just-bashit/actions/workflows/ci.yml/badge.svg)](https://github.com/just-buildit/just-bashit/actions/workflows/ci.yml)
[![Coverage](https://img.shields.io/endpoint?url=https://just-buildit.github.io/just-bashit/coverage-badge.json)](https://just-buildit.github.io/just-bashit/coverage/)
[![shellcheck](https://img.shields.io/badge/shellcheck-enabled-brightgreen)](https://www.shellcheck.net/)
[![shfmt](https://img.shields.io/badge/shfmt-conformant-blue)](https://github.com/mvdan/sh#shfmt)
[![bats](https://img.shields.io/badge/tested%20with-bats-brightgreen)](https://github.com/bats-core/bats-core)
[![pre-commit](https://img.shields.io/badge/pre--commit-enabled-brightgreen?logo=pre-commit)](https://github.com/pre-commit/pre-commit)
[![GitHub release](https://img.shields.io/github/v/release/just-buildit/just-bashit)](https://github.com/just-buildit/just-bashit/releases)

[Coverage Report](https://just-buildit.github.io/just-bashit/coverage/) · [Test Report](https://just-buildit.github.io/just-bashit/test-report/)

## Quick Start

Download the latest release, extract it, and source whatever you need:

```bash
tar xf just-bashit.tar.gz
. just-bashit/src/datetime.sh
iso-8601-basic
# 20260522T143200Z
```

Because libraries depend on each other, it's simplest to unpack the whole
package and source individual files from it.

## Libraries

| Library | Functions |
|---|---|
| [datetime](libraries/datetime.md) | `iso-8601-basic` |
| [environment](libraries/environment.md) | `set-bashrc` `unset-bashrc` `check-command-exists` |
| [file](libraries/file.md) | `add-line` `remove-line` `add-contents` |
| [format](libraries/format.md) | `trim-from` `color-echo` |
| [logging](libraries/logging.md) | `log` `log-wait` |
| [match](libraries/match.md) | `is-number` |
| [network](libraries/network.md) | `test-internet-access` |
| [path](libraries/path.md) | `get-scriptpath` `set-scriptpath` |

## Templates

See [Templates](templates.md) for copy-paste starting points: a full-featured
function template with getopts, a minimalist variant, and an executable script
template with strict mode and exit traps.
