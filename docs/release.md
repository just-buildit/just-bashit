# Release checklist

Pushing a `v*` tag triggers the release workflow: it waits for CI to be green
on the tagged commit, publishes to PyPI, and creates the GitHub Release with
the tarball and the changelog section. Tags are pushed by `make ship`, never
by hand.

Every command below is a make target. The Makefile is the single place that
says *how* a tool runs — `make help` lists everything.

______________________________________________________________________

## 1. Files and version

- [ ] Every new `src/just_bashit/` script has the standard package header:
    ```bash
    # PACKAGE: just-bashit version 0.2.0                                         #
    ```
- [ ] Every new script is listed in `[[tool.bumpversion.files]]` in
    `pyproject.toml`, so the next bump updates it automatically.
- [ ] Every version string in the repo agrees:
    ```bash
    make version-check
    ```

______________________________________________________________________

## 2. Tests

- [ ] The full suite passes with no failures and no BW01 warnings:
    ```bash
    make test
    ```
- [ ] New scripts have a corresponding `test/<script>.bats` file.
- [ ] New functions in existing libraries have test coverage.

______________________________________________________________________

## 3. Lint

- [ ] Auto-fix what can be auto-fixed, then run the gate CI runs:
    ```bash
    make format
    make lint
    ```
- [ ] Occasionally, update the pinned hooks:
    ```bash
    uv run --group dev pre-commit autoupdate
    ```

`make lint` needs network: the drift gate fetches
[`standard.mk`](https://just-buildit.github.io/standard.mk) every run and
fails if the vendored copy differs. Never edit `standard.mk` — per-repo
variation is configuration in the `Makefile`.

______________________________________________________________________

## 4. Docs

- [ ] Every new script or library has a doc page under `docs/` or
    `docs/libraries/`.
- [ ] New doc pages are wired into `nav` in `zensical.toml`.
- [ ] Option tables, examples, and usage blocks are up to date.
- [ ] The strict build passes — it catches broken anchors the tests do not:
    ```bash
    make docs-check
    ```

______________________________________________________________________

## 5. Release

Everything green? Cut the release branch, which bumps every version manifest
in one commit:

```bash
make release-branch VERSION=0.3.0
```

- [ ] Move `## [Unreleased]` in `CHANGELOG.md` to `## [0.3.0] — YYYY-MM-DD`.
- [ ] `git commit -am 'chore: release v0.3.0'`, push, open a PR.
- [ ] Merge once CI is green.

Then tag the merged commit and watch the release through:

```bash
git checkout main && git pull
make ship VERSION=0.3.0
```

`ship` is `tag-release` (which refuses to tag anything that is not exactly
`origin/main`, and re-runs `version-check` first) followed by
`release-watch`.

______________________________________________________________________

## 6. Confirm

- [ ] The release appears at
    `https://github.com/just-buildit/just-bashit/releases`.
- [ ] The package appears at `https://pypi.org/project/just-bashit/`.
- [ ] The docs site updated at
    `https://just-buildit.github.io/just-bashit/`.
- [ ] The Pages CDN mirror serves any new `src/just_bashit/*.sh` at
    `https://just-buildit.github.io/jbs/<name>.sh` — `jbx` fetches from there,
    not from the repo.
