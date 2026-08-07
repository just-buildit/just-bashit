# make-run

Source: `src/just_bashit/make-run.sh`

Ask a repository what its commands actually are, instead of transcribing
them. A repo bases its `Makefile` on
[`standard.mk`](https://just-buildit.github.io/standard.mk), which defines
the sanctioned defaults with `?=`; the repo then overrides what it must.
`make-run` reads the result of that layering, so there is no second copy to
vendor and nothing to keep in sync.

The problem it removes is drift. A skill doc said `make docs` runs
`uv run zensical build --clean`, the sanctioned default was
`uv run --group dev zensical build --clean --strict`, and doppler — which
overrides `ZENSICAL` — actually ran `uv run --group docs ...`. Three answers,
two wrong, and nothing to make them disagree out loud.

```bash
jbx make-run mk-var -C ~/doppler DOCS_BUILD_CMD
# uv run --group docs zensical build --clean --strict
```

______________________________________________________________________

## Functions

| Function                       | Answers                                      |
| ------------------------------ | -------------------------------------------- |
| `mk-var [-C DIR] NAME`         | What is `NAME` set to, fully expanded?       |
| `mk-vars [-C DIR] [REGEX]`     | What is every file-defined variable set to?  |
| `mk-run [-C DIR] TARGET [...]` | Run `TARGET` with the repo's own recipe      |
| `mk-has [-C DIR] TARGET`       | Does the repo define `TARGET`? (predicate)   |
| `mk-origin [-C DIR] NAME`      | Where did make get `NAME` — file, default, … |

Every function takes `-C DIR` (default: the current directory) and `-h`.
Nothing is built and no recipe is run, except by `mk-run`, which is the one
function that is supposed to.

______________________________________________________________________

## Usage

`make-run.sh` is a library: it must be sourced, and it calls no other
just-bashit library. Either run it ephemerally through
[`jbx`](../just-runit.md), which sources the script and invokes the named
function:

```bash
jbx make-run mk-var -C ~/doppler DOCS_BUILD_CMD
jbx make-run mk-has -C ~/doppler docs && echo "doppler builds docs"
jbx just-bashit:make-run -l          # list the functions it defines
```

or source it into a shell that needs several of the functions:

```bash
. just-bashit/src/just_bashit/make-run.sh

mk-run -C ~/doppler docs
```

______________________________________________________________________

## The load-bearing rule: undefined is not empty

`mk-var` **fails** when a variable was never defined, and **succeeds
printing an empty line** when it was defined as empty:

```bash
mk-var -C ~/doppler DOCS_CHECK_CMD   # legitimately empty → exit 0, blank line
mk-var -C ~/doppler DOSC_BUILD_CMD   # typo, undefined    → exit 1, message
# make-run: DOSC_BUILD_CMD is not defined in /home/you/doppler
```

Collapsing those two states is how a wrong command reads as a blank one — a
caller publishes an empty string where a real command belongs and nothing
looks broken. `mk-var` asks make's own `$(origin)` first, which is the only
reliable way to tell the two apart. `mk-origin` exposes that answer directly:

```bash
mk-origin -C ~/doppler DOCS_BUILD_CMD   # file
mk-origin -C ~/doppler CC               # default
mk-origin -C ~/doppler NOPE             # undefined
```

The same rule applies one level down. An unparseable makefile fails loudly
rather than handing back an empty database: `make -pRrq` exits 1 in question
mode, which is normal and ignored, and 2 when it cannot read the makefiles
at all, which is reported.

______________________________________________________________________

## Examples

### Read one command

```bash
mk-var -C ~/doppler DOCS_BUILD_CMD
# uv run --group docs zensical build --clean --strict
```

### Read a whole family of them

`mk-vars` takes no built-in list of "interesting" variables — such a list
would be exactly the hand-maintained copy this library exists to abolish.
Filter by name with an ERE instead, and note that all values resolve in a
single `make` invocation:

```bash
mk-vars -C ~/doppler '_CMD$'
# DOCS_BUILD_CMD=uv run --group docs zensical build --clean --strict
# TEST_CMD=ctest --test-dir build --output-on-failure
```

### Run a target without knowing its recipe

```bash
mk-run -C ~/doppler docs
```

`mk-run docs` runs whatever *that* repo means by `docs`, so a caller never
needs to know the command and therefore can never drift from it. The target
is verified to exist first, so a rename fails with a useful message instead
of make's `No rule to make target`. Arguments after the target pass straight
through to make:

```bash
mk-run -C ~/doppler test -j8
```

### Branch on whether a repo supports something

```bash
if mk-has -C "${repo}" docs-check; then
    mk-run -C "${repo}" docs-check
fi
```

`mk-has` reads make's target database rather than dry-running, so a target
with a missing prerequisite still answers honestly instead of erroring.

______________________________________________________________________

## Requirements

- **GNU make 3.81 or later.** The library expands its queries through a
    throwaway sentinel makefile passed alongside the repo's own via `-f`,
    rather than `--eval`, which arrived in 3.82 — macOS still ships 3.81 as
    `/usr/bin/make`, so an `--eval` implementation passes every Linux runner
    and fails only on the platform most likely to be running an old make.
- **A makefile in `DIR`.** `GNUmakefile`, `makefile`, or `Makefile`, in
    make's own search order. Anything else exits 1 with
    `make-run: no makefile in DIR`.
- `standard.mk` is not required. Any makefile can be queried; the defaults
    layering is simply what makes the answers worth asking for.

______________________________________________________________________

## What it does not do

Nothing is built by `mk-var`, `mk-vars`, `mk-has`, or `mk-origin`. The
sentinel target is `.PHONY` with a no-op recipe, so make neither reports it
up to date nor runs any real recipe — the expansion happens at recipe run
time, which is what lets `$(info ...)` observe fully-layered values.
Evaluating the same expression while the makefiles are still being read
yields nothing, because the variables do not exist yet.
