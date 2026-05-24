# Release checklist

Merging to `main` triggers an automatic GitHub Release. Run through this
checklist on your branch before merging.

---

## 1. Files and version

- [ ] Every new `src/` script has the standard package header:
  ```bash
  # PACKAGE: just-bashit version 0.1.4                                         #
  ```
- [ ] Every new `src/` script is listed in `[[tool.bumpversion.files]]` in
  `pyproject.toml` (so the next version bump updates it automatically).
- [ ] Version in `pyproject.toml` (`[project].version` and
  `[tool.bumpversion].current_version`) matches the headers in all `src/`
  files:
  ```bash
  grep 'PACKAGE: just-bashit version' src/*.sh src/just-runit src/script-template \
    | awk -F'version ' '{print $2}' | tr -d ' #' | sort -u
  # should print exactly one version number
  ```

---

## 2. Tests

- [ ] All bats tests pass with no failures and no BW01 warnings:
  ```bash
  bats test/*.bats
  ```
- [ ] New scripts have a corresponding `test/<script>.bats` file.
- [ ] New functions in existing libraries have test coverage.

---

## 3. Lint

- [ ] Update pre-commit hooks to latest versions:
  ```bash
  pre-commit autoupdate
  ```
- [ ] All pre-commit hooks pass (includes shfmt, shellcheck, and other linters):
  ```bash
  pre-commit run --all-files
  ```

---

## 4. Docs

- [ ] Every new script or library has a doc page under `docs/` or
  `docs/libraries/`.
- [ ] New doc pages are wired into `nav` in `zensical.toml`.
- [ ] Option tables, examples, and usage blocks are up to date.
- [ ] Docs build without errors:
  ```bash
  zensical build --clean
  ```

---

## 5. Version bump

When the checklist above is green, bump the version:

```bash
# patch: 0.1.4 → 0.1.5
uvx bump-my-version bump patch

# minor: 0.1.4 → 0.2.0
uvx bump-my-version bump minor

# major: 0.1.4 → 1.0.0
uvx bump-my-version bump major
```

This updates `pyproject.toml` and all `src/` headers in one commit, then
creates and pushes a `v{version}` tag.

Verify all headers are consistent after the bump:

```bash
grep 'PACKAGE: just-bashit version' src/*.sh src/just-runit src/script-template \
  | awk -F'version ' '{print $2}' | tr -d ' #' | sort -u
```

---

## 6. Merge and release

- [ ] Push the branch and open a PR — CI must be green (tests + lint).
- [ ] Merge to `main` — the `release` job creates the GitHub Release and
  uploads `just-bashit.tar.gz` automatically.
- [ ] Confirm the release appears at
  `https://github.com/just-buildit/just-bashit/releases`.
- [ ] Confirm the docs site updated at
  `https://just-buildit.github.io/just-bashit/`.
