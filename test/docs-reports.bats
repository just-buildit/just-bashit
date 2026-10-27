#!/usr/bin/env bats
# shellcheck disable=SC2154  # BATS_TEST_TMPDIR, PROJECT_ROOT set by common-setup
load 'test_helper/common-setup'
_common_setup

# ---------------------------------------------------------------------------
# docs-reports.sh -- deploy-docs' "Which run's reports" step, the path taken
# when the test matrix was skipped (TESTED != success).
#
# That path only runs on a push to main whose matrix was skipped, so it is
# exercised for real on a release: v0.11.0's release PR was a pure version
# bump, ran no matrix, uploaded no test-report-xml, and deploy-docs went red
# trying to download it (gh-151). `gh` is a stub here: it prints the value
# the real call's --jq would, taken from files under $STUB, so each case
# fixes exactly what GitHub would have answered.
# ---------------------------------------------------------------------------

setup() {
	STUB="${BATS_TEST_TMPDIR}/stub"
	mkdir -p "${STUB}/arts"
	cat >"${STUB}/gh" <<'SH'
#!/usr/bin/env bash
# api .../commits/SHA/pulls        -> $STUB/pr_head
# run list ... --commit H          -> $STUB/pr_run
# run list ... --branch main       -> $STUB/main_runs
# api .../actions/runs/ID/artifacts -> $STUB/arts/ID (a count; "err" fails)
args="$*"
fail() { echo "gh: HTTP 500" >&2; exit 1; }
case "$args" in
*"/pulls"*) [ -e "$STUB/fail_pulls" ] && fail; cat "$STUB/pr_head" ;;
*"run list"*"--commit"*) cat "$STUB/pr_run" ;;
*"run list"*"--branch main"*) cat "$STUB/main_runs" ;;
*"/artifacts"*)
	id="${args#*actions/runs/}"
	id="${id%%/*}"
	[ "$(cat "$STUB/arts/$id")" = err ] && fail
	cat "$STUB/arts/$id" ;;
*) echo "stub gh: unexpected: $args" >&2; exit 99 ;;
esac
SH
	chmod +x "${STUB}/gh"
	: >"${STUB}/pr_head" && : >"${STUB}/pr_run" && : >"${STUB}/main_runs"
	export STUB GH="${STUB}/gh"
	export GITHUB_REPOSITORY=o/r GITHUB_SHA=abc123 GITHUB_RUN_ID=999
	export TESTED=skipped
	export GITHUB_OUTPUT="${BATS_TEST_TMPDIR}/out"
	: >"${GITHUB_OUTPUT}"
}

_step() { run bash "${PROJECT_ROOT}/scripts/docs-reports.sh"; }

@test "matrix ran: uses this run's own reports, asks GitHub nothing" {
	TESTED=success _step
	assert_success
	run cat "${GITHUB_OUTPUT}"
	assert_output "run-id=999"
}

@test "skipped, the PR's run has the reports: uses the PR's run" {
	echo prhead >"${STUB}/pr_head"
	echo 500 >"${STUB}/pr_run"
	echo 2 >"${STUB}/arts/500"
	_step
	assert_success
	assert_output --partial "merged PR's head prhead, run 500"
	run cat "${GITHUB_OUTPUT}"
	assert_output "run-id=500"
}

@test "skipped, the PR's run has none (release bump): falls back to main" {
	echo prhead >"${STUB}/pr_head"
	echo 500 >"${STUB}/pr_run"
	echo 0 >"${STUB}/arts/500"
	printf '400\n300\n200\n' >"${STUB}/main_runs"
	echo 0 >"${STUB}/arts/400"
	echo 2 >"${STUB}/arts/300"
	echo 2 >"${STUB}/arts/200"
	_step
	assert_success
	assert_output --partial "most recent main run that has them: 300"
	run cat "${GITHUB_OUTPUT}"
	assert_output "run-id=300"
}

@test "skipped, no PR found at all: still falls back to main" {
	echo 300 >"${STUB}/main_runs"
	echo 2 >"${STUB}/arts/300"
	_step
	assert_success
	run cat "${GITHUB_OUTPUT}"
	assert_output "run-id=300"
}

@test "an artifact holding only one of the two reports is not enough" {
	echo 300 >"${STUB}/main_runs"
	echo 1 >"${STUB}/arts/300"
	_step
	assert_success
	run cat "${GITHUB_OUTPUT}"
	assert_output "run-id="
}

@test "no run has the reports: deploys without them, warns, succeeds" {
	echo prhead >"${STUB}/pr_head"
	echo 500 >"${STUB}/pr_run"
	echo 0 >"${STUB}/arts/500"
	printf '400\n300\n' >"${STUB}/main_runs"
	echo 0 >"${STUB}/arts/400"
	echo 0 >"${STUB}/arts/300"
	_step
	assert_success
	assert_output --partial "::warning::"
	assert_output --partial "WITHOUT the test and coverage reports"
	run cat "${GITHUB_OUTPUT}"
	assert_output "run-id="
}

@test "no runs to look at at all: warns, succeeds" {
	_step
	assert_success
	assert_output --partial "::warning::"
}

@test "API error listing the PRs: fails" {
	: >"${STUB}/fail_pulls"
	_step
	assert_failure
	assert_output --partial "::error::"
}

@test "API error reading a run's artifacts: fails, never a silent skip" {
	echo 300 >"${STUB}/main_runs"
	echo err >"${STUB}/arts/300"
	_step
	assert_failure
	assert_output --partial "::error::cannot list the artifacts of run 300"
}

@test "ci.yml's deploy-docs calls the script and guards each report step" {
	wf="${PROJECT_ROOT}/.github/workflows/ci.yml"
	run grep -c "bash scripts/docs-reports.sh" "${wf}"
	assert_output 1
	# the three report steps must not run when no run-id was found
	run grep -c "if: steps.reports.outputs.run-id != ''" "${wf}"
	assert_output 3
}
