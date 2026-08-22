# just-bashit — configuration for standard.mk.
#
# Shared targets live in standard.mk, vendored verbatim from
# https://just-buildit.github.io/standard.mk and never edited here — `make
# lint` fetches canonical and fails on any difference. Everything below is
# configuration: feature flags, command variables, and the tool dispatch that
# .pre-commit-config.yaml calls into.
#
# Adopting the standard elsewhere is one command:
#     curl -fsSL -o standard.mk https://just-buildit.github.io/standard.mk

# ── feature flags ─────────────────────────────────────────────────────────────
# No HAS_PYTHON: the wheel is packaging metadata built by release.yml, and
# there is no Python test suite for `test-python` to mean.
HAS_DOCS     = 1
HAS_COVERAGE = 1
HAS_RELEASE  = 1

# ── paths and tools ───────────────────────────────────────────────────────────
# Recursive `=`, not `:=`: DEV_RUN is defined by standard.mk, which is
# included at the bottom of this file.
BATS            ?= $(shell command -v bats 2>/dev/null || echo test/bats/bin/bats)
MDFORMAT         = $(DEV_RUN) mdformat
BUMP_MY_VERSION  = $(DEV_RUN) bump-my-version
REPORT_PATH      = test-results
TESTHELPER_PATH  = test/test_helper
ARTIFACT         = just-bashit.tar.gz

# ── test ──────────────────────────────────────────────────────────────────────
# The tarball is the release artifact CI uploads, so it is built by the same
# target that produces the report it contains.
define TEST_CMD
mkdir -p $(REPORT_PATH)
$(BATS) --report-formatter junit --output $(REPORT_PATH) \
    --print-output-on-failure test
tar -czf $(ARTIFACT) src $(REPORT_PATH)
rm -f $(TESTHELPER_PATH)/bats-*/*.json
endef

TEST_FAST_CMD = $(BATS) --abort test

# ── lint dispatch ─────────────────────────────────────────────────────────────
# mdformat is a Python tool, so pyproject.toml's dev group names it and
# uv.lock pins it — including its plugins, which as a pre-commit
# `additional_dependencies` list drifted silently while the config still read
# as pinned. shellcheck and shfmt are binaries with no PyPI-locked version to
# own, so they keep their pinned `rev:` in .pre-commit-config.yaml, the same
# exception clang-format takes.
LINT_TOOLS = mdformat

# Markdown that is not ours: the bats submodules under test/ ship their own.
MD_EXCLUDE_RE = ^test/

# The file list is built here rather than with `mdformat --exclude`, which
# needs Python 3.13+. mdformat 1.x needs 3.10, so on an older interpreter the
# target reports and exits 0 instead of breaking `make lint` for everyone.
define LINT_mdformat
@if $(MDFORMAT) --version >/dev/null 2>&1; then \
    files=$$(git ls-files '*.md' | grep -Ev '$(MD_EXCLUDE_RE)'); \
    if [ -n "$$files" ]; then $(MDFORMAT) $$files; fi; \
else \
    echo "mdformat unavailable (needs Python >=3.10) — skipping"; \
fi
endef

# ── docs coverage ─────────────────────────────────────────────────────────────
# A repo-local target, so it needs naming here or help-check reports a rule
# that help does not list.
#
# Dispatched from .pre-commit-config.yaml rather than DOCS_CHECK_PRE_CMDS: CI
# runs `make test`, `make coverage` and `make lint` — not `make docs-check` —
# so a docs gate hung off docs-check would be local-only, which is how a rule
# nobody enforces sits on main indefinitely.
LOCAL_TARGETS += docs-coverage

docs-coverage: ## Verify every shipped script is documented and in the nav
	@bash scripts/docs_coverage.sh

# ── all ───────────────────────────────────────────────────────────────────────
# Lint first: shellcheck and shfmt are seconds, the bats suite is minutes.
#
# This needs standard.mk at or past just-buildit/just-buildit.github.io#14. In
# earlier copies the gates dumped make's database with a goal-less
# `$(MAKE) -rpn`, which -n executes, so any default goal reaching `lint` made
# them re-enter themselves without bound. `standard-check` will tell you if
# this copy predates the fix.
ALL_DEPS = lint test

# ── clean ─────────────────────────────────────────────────────────────────────
CLEAN_PATHS = $(ARTIFACT) $(REPORT_PATH) site

# `make test` writes junit XML inside the bats-assert/bats-support checkouts;
# restoring them is what makes the submodules clean again. Guarded, so a
# clone without submodules still cleans instead of erroring.
define CLEAN_CMD
@for d in bats-assert bats-support; do \
    if [ -e "$(TESTHELPER_PATH)/$$d/.git" ]; then \
        git -C "$(TESTHELPER_PATH)/$$d" restore .; \
    fi; \
done
endef

# ── coverage ──────────────────────────────────────────────────────────────────
# Measured 69% on the kcov job. Set near the floor rather than far below it:
# a threshold of 40 would have let a 29-point regression through in silence,
# which is the difference between a gate and a decoration.
COVERAGE_MIN = 60

# kcov creates its own output directory but not the parent, and says so as
# three cascading errors ("Can't write helper", "Can't start/attach", "Can't
# open directory") that name everything except the missing mkdir. The old
# `coverage: $(REPORT_PATH)` order-only prerequisite is what used to do this.
define COVERAGE_CMD
mkdir -p $(REPORT_PATH)
kcov --include-pattern=/src --exclude-pattern=/test \
    $(REPORT_PATH)/coverage $(BATS) test
endef

# CI's coverage job runs `make coverage` only to produce the report the
# badge step reads from — nothing there calls `coverage-gate`, so the
# threshold is not enforced. GATES_PROVISION says so explicitly; without it,
# gates-check flags ci.yml's `make coverage` as unreachable from `gates`.
GATES_PROVISION = install-deps coverage

# A report is not a gate; this is the gate. sed rather than `grep -oP`, which
# is GNU-only and would fail on the macOS runner.
define COVERAGE_GATE_CMD
@xml=$$(find $(REPORT_PATH)/coverage -name cobertura.xml 2>/dev/null | head -1); \
 if [ -z "$$xml" ]; then \
     echo "ERROR: no coverage report — run 'make coverage' first"; exit 1; \
 fi; \
 rate=$$(sed -n 's/.*line-rate="\([0-9.]*\)".*/\1/p' "$$xml" | head -1); \
 pct=$$(awk "BEGIN { printf \"%d\", $$rate * 100 }"); \
 echo "coverage: $$pct% (minimum $(COVERAGE_MIN)%)"; \
 if [ "$$pct" -lt $(COVERAGE_MIN) ]; then \
     echo "ERROR: coverage $$pct% is below the $(COVERAGE_MIN)% minimum"; \
     exit 1; \
 fi
endef

# ── release ───────────────────────────────────────────────────────────────────
BUMP_VERSION_CMD = $(BUMP_MY_VERSION) bump --new-version $(VERSION) \
    --no-commit --no-tag patch

# Every place a version string lives. version-check requires all of them to
# agree with each other, and with VERSION= when one is given — the gate that
# catches a manifest bumpversion was never told about.
define VERSION_PROBES
pyproject.toml|sed -n 's/^version = "\(.*\)"/\1/p' pyproject.toml | head -1
bootstrap.toml|sed -n 's/^version *= *"\(.*\)"/\1/p' bootstrap.toml | head -1
just-runit|sed -n 's/^_VERSION="\(.*\)"/\1/p' src/just_bashit/just-runit
src/ headers|grep -h '^# PACKAGE' src/just_bashit/*.sh | sed 's/.*version \([0-9.]*\).*/\1/' | sort -u
endef

# Select the run BY TAG, and wait for it to exist.
#
# `--limit 1` alone is a race: `ship` is `tag-release` then `release-watch`, and
# the push returns before GitHub has created the workflow run, so the newest
# row is still the PREVIOUS release. Shipping v0.4.1 watched the run that had
# failed the night before and reported the release as failed while it went on
# to succeed — a watcher that can report the wrong run is worse than none,
# because the failure it invents is indistinguishable from a real one.
#
# A tag-triggered run carries the tag in headBranch, so --branch pins it to
# exactly this release. The wait covers creation latency, which is a second or
# two; 60s of headroom costs nothing on the happy path and turns "no run yet"
# into a clear error rather than an empty run ID.
define RELEASE_WATCH_CMD
@tag="v$(VERSION)"; id=""; \
 for _ in $$(seq 1 30); do \
     id=$$(gh run list --workflow=release.yml --branch "$$tag" \
           --limit 1 --json databaseId -q '.[0].databaseId' 2>/dev/null); \
     [ -n "$$id" ] && break; \
     sleep 2; \
 done; \
 if [ -z "$$id" ]; then \
     echo "ERROR: no release run for $$tag after 60s"; \
     echo "  check: gh run list --workflow=release.yml --branch $$tag"; \
     exit 1; \
 fi; \
 echo "Watching release run $$id ($$tag)"; \
 gh run watch --exit-status "$$id"
endef

include standard.mk
