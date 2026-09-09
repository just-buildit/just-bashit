# shellcheck disable=SC2154  # BATS_TEST_TMPDIR, PROJECT_ROOT set by common-setup
load 'test_helper/common-setup'
_common_setup

# ---------------------------------------------------------------------------
# workflow_check.sh — the gate one level above gates-home-check.
#
# The defect it exists to catch shipped: deploy-docs downloaded
# test-report-xml while declaring only `needs: [coverage, lint]`, and main
# went red on two commits whose pull requests were both green. Every case
# below is that bug or one of its neighbours.
#
# Fixtures are built here rather than pointed at the real workflows, so
# nothing depends on ci.yml keeping its current shape.
# ---------------------------------------------------------------------------

setup() {
	REPO="${BATS_TEST_TMPDIR}/repo"
	mkdir -p "${REPO}/.github/workflows" "${REPO}/scripts"
	cp "${PROJECT_ROOT}/scripts/workflow_check.sh" "${REPO}/scripts/"

	cat >"${REPO}/.github/workflows/ci.yml" <<'YAML'
name: CI
on:
  push:
    branches: ["main"]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Make the thing
        run: make
      - uses: actions/upload-artifact@v7
        with:
          name: the-thing
          path: out/

  consume:
    needs: [build]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/download-artifact@v8
        with:
          name: the-thing
YAML
	: >"${REPO}/.github/no-pre-merge-run"
}

_gate() {
	WORKFLOW_CHECK_ROOT="${REPO}" run bash "${REPO}/scripts/workflow_check.sh"
}

_edit() {
	local f="$1"
	shift
	sed "$@" "${f}" >"${f}.new" && mv "${f}.new" "${f}"
}

@test 'a workflow whose hand-offs are all awaited passes' {
	_gate
	assert_success
	assert_output --partial "all awaited"
}

@test 'a download from a job not in needs fails (the deploy-docs bug)' {
	_edit "${REPO}/.github/workflows/ci.yml" 's/^    needs: \[build\]$//'
	_gate
	assert_failure
	assert_output --partial "not in its needs closure"
	assert_output --partial "the-thing"
}

@test 'a transitive wait counts as waiting' {
	# consume -> middle -> build. Nothing is racing; the gate must not say
	# it is.
	_edit "${REPO}/.github/workflows/ci.yml" 's/^    needs: \[build\]$/    needs: [middle]/'
	cat >>"${REPO}/.github/workflows/ci.yml" <<'YAML'

  middle:
    needs: [build]
    runs-on: ubuntu-latest
    steps:
      - run: true
YAML
	_gate
	assert_success
}

@test 'a download nothing uploads fails' {
	# Rename the UPLOAD only. A plain sed renames both sides -- they are
	# identically indented -- which leaves them consistent and proves
	# nothing. That mistake is why this test exists in this shape.
	awk '!done && /name: the-thing$/ {
		sub(/the-thing/, "renamed-thing"); done = 1
	} { print }' "${REPO}/.github/workflows/ci.yml" \
		>"${REPO}/.github/workflows/ci.new"
	mv "${REPO}/.github/workflows/ci.new" "${REPO}/.github/workflows/ci.yml"
	_gate
	assert_failure
	assert_output --partial "which no job in this workflow uploads"
}

@test 'an undeclared main-only job fails' {
	cat >>"${REPO}/.github/workflows/ci.yml" <<'YAML'

  deploy:
    needs: [consume]
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - run: true
YAML
	_gate
	assert_failure
	assert_output --partial "runs only on the default branch"
	assert_output --partial "deploy"
}

@test 'a declared main-only job passes' {
	cat >>"${REPO}/.github/workflows/ci.yml" <<'YAML'

  deploy:
    needs: [consume]
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - run: true
YAML
	printf 'deploy\n' >"${REPO}/.github/no-pre-merge-run"
	_gate
	assert_success
}

@test 'a stale declaration fails, so the list can only shrink' {
	printf 'gone-job\n' >"${REPO}/.github/no-pre-merge-run"
	_gate
	assert_failure
	assert_output --partial "may only shrink"
}

@test 'comments and blank lines in the declaration file are ignored' {
	cat >>"${REPO}/.github/workflows/ci.yml" <<'YAML'

  deploy:
    needs: [consume]
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - run: true
YAML
	printf '# why this one is allowed\n\ndeploy\n' \
		>"${REPO}/.github/no-pre-merge-run"
	_gate
	assert_success
}

@test 'a step name is not mistaken for an artifact name' {
	# Step names appear BEFORE their uses:, so the window that captures an
	# artifact name must not reach backwards into one.
	_gate
	assert_success
	refute_output --partial "Make the thing"
}

@test 'parsing nothing is an error, not a pass' {
	# A parser that silently reads no jobs would bless any workflow.
	printf 'name: empty\non: push\n' \
		>"${REPO}/.github/workflows/ci.yml"
	_gate
	assert_failure
	assert_output --partial "broken parser"
}
