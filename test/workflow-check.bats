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

# The fixture is this repo as far as check 5 is concerned: it has no remote,
# so its own slug comes from GITHUB_REPOSITORY, as it does in Actions.
_gate() {
	GITHUB_REPOSITORY="${OWN_SLUG-just-buildit/just-bashit}" \
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

# Check 4: every job a pull request runs feeds `CI passed`, the required
# check. coverage did not, and went red on main for #142 while the merge went
# through. The fixture's aggregate is named ci-passed, as the real one is.
_with_ci_passed() {
	cat >>"${REPO}/.github/workflows/ci.yml" <<'YAML'

  extra:
    runs-on: ubuntu-latest
    steps:
      - run: true

  ci-passed:
    needs: [build, consume, extra]
    if: always()
    runs-on: ubuntu-latest
    steps:
      - run: true

  after:
    needs: ci-passed
    runs-on: ubuntu-latest
    steps:
      - run: true
YAML
}

@test 'every pull-request job feeding CI passed, or after it, passes' {
	_with_ci_passed
	_gate
	assert_success
}

@test 'a pull-request job CI passed does not wait for fails (the coverage bug)' {
	_with_ci_passed
	_edit "${REPO}/.github/workflows/ci.yml" \
		-e 's/needs: \[build, consume, extra\]/needs: [build, consume]/'
	_gate
	assert_failure
	assert_output --partial "job 'extra' runs on pull requests"
}

@test 'a transitive wait into CI passed counts' {
	_with_ci_passed
	_edit "${REPO}/.github/workflows/ci.yml" \
		-e 's/needs: \[build, consume, extra\]/needs: [consume, extra]/'
	_gate
	assert_success
}

# Check 5: every checkout of THIS repo fetches the submodules, read per step,
# whatever the job runs. The lint job's had none, and test-lint-gates died on
# a missing test/bats/bin/bats (#258). Asking which jobs "run bats" was a
# spelling chase (`make -C . test`, a direct bats call), so it is not asked.
_with_job() {
	local steps="$1"
	cat >>"${REPO}/.github/workflows/ci.yml" <<YAML

  suite:
    runs-on: ubuntu-latest
    steps:
${steps}
      - run: true
YAML
}

@test 'a checkout of this repo without the submodules fails' {
	_with_job '      - uses: actions/checkout@v7'
	_gate
	assert_failure
	assert_output --partial "job 'suite' checks out this repo without"
}

@test 'a checkout of this repo with the submodules passes' {
	_with_job $'      - uses: actions/checkout@v7\n        with:\n          submodules: recursive'
	_gate
	assert_success
	assert_output --partial '1 checkout(s) of this repo fetch submodules'
}

@test 'submodules: true counts, and a name: before uses: is the same step' {
	_with_job $'      - name: Check out\n        uses: actions/checkout@v7\n        with:\n          submodules: true'
	_gate
	assert_success
}

@test "another repo's checkout with submodules does not cover this one's" {
	# Credited per step: the second checkout is of another repository.
	_with_job $'      - uses: actions/checkout@v7\n      - uses: actions/checkout@v7\n        with:\n          repository: o/other\n          submodules: recursive'
	_gate
	assert_failure
	assert_output --partial "job 'suite' checks out this repo without"
}

@test "another repo's checkout alone needs no submodules" {
	_with_job $'      - uses: actions/checkout@v7\n        with:\n          repository: o/other'
	_gate
	assert_success
}

@test 'whatever the job runs: no step that runs bats is needed to require them' {
	# The old rule asked which jobs ran `make test`; this one does not ask.
	_with_job $'      - uses: actions/checkout@v7\n      - run: echo nothing here runs bats'
	_gate
	assert_failure
	assert_output --partial "job 'suite' checks out this repo without"
}

@test 'only a named exemption skips the rule, and only for its own job' {
	# changes.yml:changes is exempt (canonical's vendored workflow).
	cat >"${REPO}/.github/workflows/changes.yml" <<'YAML'
name: changes
on: push
jobs:
  changes:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
YAML
	_gate
	assert_success
	cat >>"${REPO}/.github/workflows/changes.yml" <<'YAML'
  other:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
YAML
	_gate
	assert_failure
	assert_output --partial "changes.yml: job 'other' checks out this repo without"
	refute_output --partial "job 'changes'"
}

# H1: `repository:` makes a checkout another repo's only when it is a literal
# slug other than this one. This repo named by expression or by its own
# slug, in any case, is still this repo; an expression that cannot be read
# counts as this repo too, so a doubt fails closed.
@test 'a checkout naming this repo by expression is still this repo' {
	_with_job $'      - uses: actions/checkout@v7\n        with:\n          repository: ${{ github.repository }}'
	_gate
	assert_failure
	assert_output --partial "job 'suite' checks out this repo without"
}

@test "a checkout naming this repo's own slug, in any case, is still this repo" {
	_with_job $'      - uses: actions/checkout@v7\n        with:\n          repository: Just-Buildit/Just-Bashit'
	_gate
	assert_failure
	assert_output --partial "job 'suite' checks out this repo without"
}

@test 'an expression the check cannot read counts as this repo' {
	_with_job $'      - uses: actions/checkout@v7\n        with:\n          repository: ${{ inputs.repo }}'
	_gate
	assert_failure
	assert_output --partial "job 'suite' checks out this repo without"
}

@test 'with no slug to compare against, a literal one counts as this repo' {
	OWN_SLUG='' _with_job $'      - uses: actions/checkout@v7\n        with:\n          repository: o/other'
	OWN_SLUG='' _gate
	assert_failure
	assert_output --partial "job 'suite' checks out this repo without"
}

# H2: the spellings of `submodules:` YAML allows all count.
@test 'submodules is read quoted, commented and in a flow mapping' {
	local with
	for with in \
		$'        with:\n          submodules: "recursive"' \
		$'        with:\n          submodules: \'true\'' \
		$'        with:\n          submodules: recursive  # bats' \
		'        with: {submodules: recursive, fetch-depth: 0}'; do
		setup
		_with_job "      - uses: actions/checkout@v7"$'\n'"${with}"
		_gate
		assert_success
	done
}

@test 'submodules: false is not submodules' {
	_with_job $'      - uses: actions/checkout@v7\n        with:\n          submodules: false'
	_gate
	assert_failure
}

# An alias pulls a step's keys from elsewhere -- an anchor in an exempt job,
# say -- which a line reader cannot follow, so a checkout using one is
# refused rather than guessed at.
@test 'a checkout step that uses a YAML alias is refused' {
	_with_job $'      - uses: actions/checkout@v7\n        with: *checkout_with'
	_gate
	assert_failure
	assert_output --partial 'has a checkout step that uses a'
}

# J1, as a class: a key-like string in a NON-key position is never a key.
# Three review rounds each found one more position; this case walks them
# all. The base is this repo's checkout, BARE, which must stay red: an
# injected `submodules: recursive` in any of these places must not credit
# it, and an injected `repository: o/other` must not make it someone
# else's. Each site is one shape YAML has for text that is not a key.
@test 'a key in a comment, a quoted value, a block scalar or another step is never read' {
	local co='      - uses: actions/checkout@v7'
	local -a sites=(
		"${co}"$'\n        with:\n          fetch-depth: 0  # INJ'
		"${co}"$'\n        with: {fetch-depth: 0}  # INJ'
		"${co}"$'\n        with:\n          # INJ\n          fetch-depth: 0'
		$'      - name: "INJ"\n        uses: actions/checkout@v7'
		$'      - name: "check out, INJ"\n        uses: actions/checkout@v7'
		"${co}"$'\n        with:\n          ref: \'INJ\''
		"${co}"$'\n        with:\n          ref: |\n            INJ'
		"${co}"$'\n        with:\n          ref: >-\n            INJ'
		"${co}"$'\n      - run: |\n          INJ\n          - uses: actions/checkout@v7\n            with:\n              INJ'
		"${co}"$'\n      - run: >\n          echo\n          INJ'
		"${co}"$'\n      - uses: actions/setup-python@v5\n        with:\n          INJ'
	)
	local inj site steps passed=()
	for inj in 'submodules: recursive' 'repository: o/other'; do
		for site in "${sites[@]}"; do
			setup
			steps="${site//INJ/${inj}}"
			_with_job "${steps}"
			_gate
			if [[ ${status} -eq 0 || ${output} != *"job 'suite' checks out this repo without"* ]]; then
				passed+=("[${inj}] ${steps}")
			fi
		done
	done
	# The same bare checkout with its steps as a flow sequence: refused for
	# its form, whatever is injected, never passed.
	for inj in 'submodules: recursive' 'repository: o/other'; do
		setup
		printf 'name: flow\non: push\njobs:\n  suite:\n    runs-on: ubuntu-latest\n    steps: [{uses: actions/checkout@v7, with: {%s}}]\n' \
			"${inj}" >"${REPO}/.github/workflows/flow.yml"
		_gate
		if [[ ${status} -eq 0 || ${output} != *'steps of job suite is a YAML flow collection'* ]]; then
			passed+=("[${inj}] steps: [{uses: actions/checkout@v7, with: {${inj}}}]")
		fi
	done
	((${#passed[@]} == 0)) || fail "read as a key (or as foreign):"$'\n'"$(printf '%s\n---\n' "${passed[@]}")"
}

# K1, as a class: the parser walks jobs, each job, its steps and each step as
# BLOCK YAML, so a FLOW collection at one of those levels is refused by name,
# the way an alias is; a flow value inside a step (`with: {...}`) is still
# read. _flow_job WORKFLOW_BODY writes a workflow whose jobs: block is given.
_flow_wf() {
	printf 'name: flow\non: push\n%s\n' "$1" >"${REPO}/.github/workflows/flow.yml"
}

@test 'jobs written as a flow mapping is refused' {
	_flow_wf 'jobs: {suite: {runs-on: ubuntu-latest, steps: [{uses: actions/checkout@v7}]}}'
	_gate
	assert_failure
	assert_output --partial 'flow.yml: jobs is a YAML flow collection'
	assert_output --partial 'write jobs as a block list/mapping'
}

@test 'a job written as a flow mapping is refused' {
	_flow_wf $'jobs:\n  suite: {runs-on: ubuntu-latest, steps: [{uses: actions/checkout@v7}]}'
	_gate
	assert_failure
	assert_output --partial 'flow.yml: job suite is a YAML flow collection'
	assert_output --partial 'write suite as a block list/mapping'
}

@test 'steps written as a flow sequence is refused (K1)' {
	_flow_wf $'jobs:\n  suite:\n    runs-on: ubuntu-latest\n    steps: [{uses: actions/checkout@v7}]'
	_gate
	assert_failure
	assert_output --partial 'flow.yml: steps of job suite is a YAML flow collection'
	assert_output --partial 'write steps as a block list/mapping'
}

@test 'a flow step holding nested flow is refused; a flat one is read' {
	_with_job '      - {uses: actions/checkout@v7, with: {submodules: true}}'
	_gate
	assert_failure
	assert_output --partial 'a step of job suite is a YAML flow collection'
	assert_output --partial 'write that step as a block list/mapping'
	setup
	# Flat, it is read like any step: this bare checkout of this repo is red
	# for its submodules, not refused for its form.
	_with_job '      - {uses: actions/checkout@v7}'
	_gate
	assert_failure
	assert_output --partial "job 'suite' checks out this repo without"
	refute_output --partial 'flow collection'
}

@test 'with: as a flow mapping is still read, not refused' {
	_with_job $'      - uses: actions/checkout@v7\n        with: {submodules: recursive}'
	_gate
	assert_success
	refute_output --partial 'flow collection'
}
