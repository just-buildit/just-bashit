
[comment]: # (START FRONTMATTER - USER CONTENT BELOW)

[![CI](https://github.com/just-buildit/just-bashit/actions/workflows/ci.yml/badge.svg)](https://github.com/just-buildit/just-bashit/actions/workflows/ci.yml)
[![Coverage](https://img.shields.io/endpoint?url=https://just-buildit.github.io/just-bashit/coverage-badge.json)](https://just-buildit.github.io/just-bashit/coverage/)
[![shellcheck](https://img.shields.io/badge/shellcheck-enabled-brightgreen)](https://www.shellcheck.net/)
[![shfmt](https://img.shields.io/badge/shfmt-conformant-blue)](https://github.com/mvdan/sh#shfmt)
[![bats](https://img.shields.io/badge/tested%20with-bats-brightgreen)](https://github.com/bats-core/bats-core)
[![pre-commit](https://img.shields.io/badge/pre--commit-enabled-brightgreen?logo=pre-commit)](https://github.com/pre-commit/pre-commit)

[Coverage Report](https://just-buildit.github.io/just-bashit/coverage/) · [Test Report](https://github.com/just-buildit/just-bashit/actions/workflows/ci.yml)

[comment]: # (END FRONMATTER - BEGIN USER CONTENT)

# just-bashit

Evolving set of [shfmt](https://github.com/mvdan/sh#shfmt)-conformant, [bats](https://bats-core.readthedocs.io/en/stable/)-tested, [shellcheck](https://www.shellcheck.net/)-linted tools, templates, and more.

**[Documentation](https://just-buildit.github.io/just-bashit/)**

## Getting Started

A release package contains shell libraries along with a script and two function templates for developing your own tools.

```
just-bashit
    +--README.md
    +--src/
    |   +-- datetime.sh
    |   +-- environment.sh
    :   :
    |   +-- function-template.sh
    |   +-- script-template
    +--test-results/
```

Some libraries depend on others so it's best to use the whole package and source whatever you need, for example:

```bash
. just-bashit/src/datetime.sh # contains iso-8601-basic()
iso-8601-basic -d '10:32 AM EDT Jan 5 1982'
19820105T143200Z
```
