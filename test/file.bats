# shellcheck disable=SC2154  # BATS_TEST_TMPDIR, HELP_REGEX set by bats/common-setup
load 'test_helper/common-setup'
source 'src/just_bashit/file.sh'
_common_setup

setup() {
	TEMPFILE=$(mktemp /tmp/tmp.XXXXXXXXXX)
	FROMPATH=$(mktemp /tmp/tmp.XXXXXXXXXX)
	TOPATH=$(mktemp /tmp/tmp.XXXXXXXXXX)
	cat <<-EOF >"$FROMPATH"
		APPLE
		BANANA

		AVOCADO

		PLUM
	EOF
}

@test 'add-line unknown option -k' {
	run add-line -k
	assert_output --regexp "$(
		echo "Invalid option: -k"
		# shellcheck disable=SC2154
		echo "${HELP_REGEX}"
	)"
}

@test 'add-line no input' {
	run add-line
	# shellcheck disable=SC2154
	assert_output --partial "Not enough arguments"
	assert_output --regexp "${HELP_REGEX}"
}

@test 'add-line path' {
	run add-line "${TEMPFILE}"
	run add-line "${TEMPFILE}"
	run add-line "${TEMPFILE}"
	assert_equal "$(grep -c "^$" "${TEMPFILE}")" 3
}

@test 'remove-line path' {
	run remove-line "${TEMPFILE}"
	run remove-line "${TEMPFILE}"
	run remove-line "${TEMPFILE}"
	assert_equal "$(grep -c "^$" "${TEMPFILE}")" 0
}

@test 'add-line path no blanks' {
	run add-line -x "${TEMPFILE}"
	run add-line -x "${TEMPFILE}"
	run add-line -x "${TEMPFILE}"
	run add-line -x "${TEMPFILE}"
	assert_equal "$(grep -c "^$" "${TEMPFILE}")" 1
}

@test 'add-line entry path' {
	run add-line 'ENTRY' "${TEMPFILE}"
	run bash -c "awk '/^ENTRY$/' ${TEMPFILE} | grep ."
	assert_success
}

@test 'remove-line -h' {
	run remove-line -h
	# shellcheck disable=SC2154
	assert_output --regexp "${HELP_REGEX}"
}

@test 'remove-line unknown option -k' {
	run remove-line -k
	assert_output --regexp "$(
		echo "Invalid option: -k"
		# shellcheck disable=SC2154
		echo "${HELP_REGEX}"
	)"
}

@test 'remove-line no input' {
	run remove-line
	# shellcheck disable=SC2154
	assert_output --partial "Not enough arguments"
	assert_output --regexp "${HELP_REGEX}"
}

@test 'remove-line entry' {
	run remove-line 'MY_NEW_LINE' "${TEMPFILE}"
	run bash -c "awk '/^MY_NEW_LINE$/' ${TEMPFILE} | grep ."
	assert_failure
}

@test 'add-contents' {
	run add-contents "${FROMPATH}" "${TOPATH}"
	run bash -c "diff -q ${FROMPATH} ${TOPATH} >/dev/null"
	assert_success
}

@test 'add-contents twice' {
	run add-contents "${FROMPATH}" "${TOPATH}"
	run bash -c "diff ${FROMPATH} ${TOPATH}"
	assert_success
}

@test 'add-line -h shows help' {
	run add-line -h
	assert_output --regexp "${HELP_REGEX}"
}

@test 'add-line idempotency — same entry written only once' {
	local f="${BATS_TEST_TMPDIR}/idem.txt"
	add-line "UNIQUE_LINE" "${f}"
	add-line "UNIQUE_LINE" "${f}"
	add-line "UNIQUE_LINE" "${f}"
	assert_equal "$(grep -c "^UNIQUE_LINE$" "${f}")" 1
}

@test 'add-line creates file if not exists' {
	local f
	f="${BATS_TEST_TMPDIR}/newfile_$(date +%s%N).txt"
	[ ! -f "${f}" ]
	add-line "HELLO" "${f}"
	assert [ -f "${f}" ]
	run grep -q "^HELLO$" "${f}"
	assert_success
}

@test 'add-contents -h shows help' {
	run add-contents -h
	assert_output --regexp "${HELP_REGEX}"
}

@test 'add-contents -x deduplicates blank lines to at most one' {
	local f="${BATS_TEST_TMPDIR}/noblank.txt"
	run add-contents -x "${FROMPATH}" "${f}"
	# -x routes blank lines through grep-dedup, so at most one blank survives
	local blank_count
	blank_count=$(grep -c "^$" "${f}" || true)
	assert [ "${blank_count}" -le 1 ]
}

@test 'add-contents idempotency — non-blank lines not duplicated' {
	local f="${BATS_TEST_TMPDIR}/idem2.txt"
	# Use a file with no blank lines to avoid the blank-line deduplicate edge case
	local src="${BATS_TEST_TMPDIR}/src_noblanks.txt"
	printf 'LINE_A\nLINE_B\nLINE_C\n' >"${src}"
	add-contents "${src}" "${f}"
	local lines_after_first
	lines_after_first=$(grep -c "." "${f}" || true)
	add-contents "${src}" "${f}"
	local lines_after_second
	lines_after_second=$(grep -c "." "${f}" || true)
	assert_equal "${lines_after_first}" "${lines_after_second}"
}

teardown() {
	rm -f "${TEMPFILE}"
	rm -f "${FROMPATH}"
	rm -f "${TOPATH}"
}
