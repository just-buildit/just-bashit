# shellcheck disable=SC2154  # BATS_TEST_TMPDIR, PROJECT_ROOT set by common-setup
load 'test_helper/common-setup'
_common_setup

# ---------------------------------------------------------------------------
# `make test` leaves out the bats files tagged `lint`, and `make lint` runs
# them. A lint-tagged file tests a gate that needs python3, which the
# portability matrix's images (debian, arch, alpine, windows/ucrt64)
# deliberately lack: run there, it failed on `python3: No such file or
# directory` (just-bashit#258). This file runs in the matrix, so it is what
# notices when the suite's filter stops excluding them.
# ---------------------------------------------------------------------------

@test 'make test runs the suite without the lint-tagged files' {
	# MAKEFLAGS cleared: a `make test BATS_ARGS=...` running this file passes
	# its own override down (MAKEFLAGS and the environment), and the
	# default is what is under test.
	run env -u MAKEFLAGS -u MFLAGS -u MAKELEVEL -u BATS_ARGS make -s -C "${PROJECT_ROOT}" \
		--no-print-directory -n test
	assert_success
	assert_output --partial "--filter-tags '!lint' test"
}

@test 'the lint-tagged files are exactly the ones make lint runs' {
	local bats="${PROJECT_ROOT}/test/bats/bin/bats" all lint suite
	all="$("${bats}" --count "${PROJECT_ROOT}/test")"
	lint="$("${bats}" --count --filter-tags lint "${PROJECT_ROOT}/test")"
	suite="$("${bats}" --count --filter-tags '!lint' "${PROJECT_ROOT}/test")"
	((lint > 0)) || fail "no test is tagged lint"
	assert_equal "$((suite + lint))" "${all}"
	run grep -Fx 'test-lint-gates: ## Run the bats tests of lint-side gates (file_tags=lint)' \
		"${PROJECT_ROOT}/Makefile"
	assert_success
	run grep -E '^\s+entry: make -s test-lint-gates\s*$' \
		"${PROJECT_ROOT}/.pre-commit-config.yaml"
	assert_success
}
