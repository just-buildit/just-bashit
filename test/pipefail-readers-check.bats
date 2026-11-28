# shellcheck disable=SC2154  # BATS_TEST_TMPDIR, PROJECT_ROOT set by common-setup
load 'test_helper/common-setup'
_common_setup

# ---------------------------------------------------------------------------
# pipefail-readers-check -- no pipeline under pipefail ends in a reader that
# stops early (grep -q, head, sed 1q, awk exit). The producer then takes
# SIGPIPE and the pipeline fails though the reader got its answer; under `!`
# the answer flips. just-runit's `! printf ... | grep -qx "${lib}"` and
# setup-system's `! { ssh-add -L | grep -qF ...; }` were both that shape.
#
# The rules are canonical's vendored scripts/pipefail-readers.py, tested
# there; these cases test the wiring: the target reads this repo's shell,
# and goes red naming a file that breaks the rule.
#
# Tagged `lint`: the gate needs python3, which the portability matrix's
# images deliberately lack, so `make test` leaves these out and `make lint`
# runs them (test-lint-gates, in the lint job), where the gate itself runs.
# ---------------------------------------------------------------------------

# bats file_tags=lint

@test 'pipefail-readers-check passes on this repo, having read its shell' {
	run make -s -C "${PROJECT_ROOT}" pipefail-readers-check
	assert_success
	[[ ${output} =~ pipefail-readers:\ ([0-9]+)\ file ]] ||
		fail "no file count in: ${output}"
	# just-runit, setup-system.sh, inspect.sh and the workflows at least: a
	# list that shrank to a handful has stopped reading the shell it guards.
	((BASH_REMATCH[1] >= 10)) || fail "read only ${BASH_REMATCH[1]} file(s)"
}

@test 'pipefail-readers-check goes red on a pipe into grep -q, naming it' {
	local f="${BATS_TEST_TMPDIR}/bad.sh"
	printf '#!/bin/bash\nset -euo pipefail\n! printf "a\\n" | grep -qx a\n' >"${f}"
	run make -s -C "${PROJECT_ROOT}" pipefail-readers-check \
		PIPEFAIL_READERS_FILES="${f}"
	assert_failure
	assert_output --partial "${f}:3: ! printf"
}

@test 'pipefail-readers-check refuses to pass having read nothing' {
	local f="${BATS_TEST_TMPDIR}/plain.sh"
	printf '#!/bin/bash\nx | head -1\n' >"${f}"
	run make -s -C "${PROJECT_ROOT}" pipefail-readers-check \
		PIPEFAIL_READERS_FILES="${f}"
	assert_failure
	assert_output --partial 'scanned no file'
}

@test 'the list holds this repo shell and leaves the vendored files to canonical' {
	# shellcheck disable=SC2016  # make expands $(...), not the shell
	run make -s -C "${PROJECT_ROOT}" --no-print-directory \
		--eval 'print-pf: ; @printf "%s\n" $(PIPEFAIL_READERS_FILES)' print-pf
	assert_success
	assert_line src/just_bashit/just-runit
	assert_line src/just_bashit/setup-system.sh
	assert_line .github/workflows/ci.yml
	refute_line scripts/release-watch.sh
	refute_line .github/workflows/changes.yml
}
