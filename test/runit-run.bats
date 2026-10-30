# shellcheck disable=SC2154  # bats/common-setup export the harness vars
load 'test_helper/common-setup'
_common_setup
bats_require_minimum_version 1.5.0

# Running a script runs its top level exactly ONCE, as sourcing it would:
# `jbx SPEC` sources it, and `jbx SPEC FUNCTION` sources it and calls
# FUNCTION. The second form used to source it first in a separate child,
# only to check that FUNCTION exists, so a script without a main guard ran
# its top level twice (just-bashit#141). Every test here counts the lines
# the fixture's top level appends to a file.

setup() {
	fixtures="${BATS_TEST_TMPDIR}/fixtures"
	count="${BATS_TEST_TMPDIR}/count"
	mkdir -p "${fixtures}"
	_serve_fixtures "${fixtures}"
	export XDG_CACHE_HOME="${BATS_TEST_TMPDIR}/cache"
	export COUNT="${count}"
	cat >"${fixtures}/tool.sh" <<-'EOF'
		hello() { echo "hello-ran:$#:$*"; }
		ls() { echo "own-ls"; }
		echo top >>"${COUNT}"
	EOF
}

# _runs -- how many times the fixture's top level ran.
_runs() {
	local n=0
	[[ -f ${count} ]] && n=$(wc -l <"${count}")
	echo $((n))
}

@test 'SPEC FUNCTION runs the top level once, then the function' {
	run just-runit https://fixture.invalid/tool.sh hello a 'b c'
	assert_success
	assert_output 'hello-ran:2:a b c'
	assert_equal "$(_runs)" 1
}

@test 'SPEC runs the top level once' {
	run just-runit https://fixture.invalid/tool.sh
	assert_success
	assert_equal "$(_runs)" 1
}

@test 'SPEC FUNCTION under -c runs the top level once' {
	run just-runit -c -p COUNT https://fixture.invalid/tool.sh hello
	assert_success
	assert_output 'hello-ran:0:'
	assert_equal "$(_runs)" 1
}

@test 'SPEC FUNCTION refuses a function the script does not define, exit 127' {
	run -127 just-runit https://fixture.invalid/tool.sh nope
	assert_failure 127
	assert_output --partial "'nope' is not a function defined by this script"
	assert_equal "$(_runs)" 1
}

@test 'SPEC FUNCTION calls a script function that shadows a command' {
	run --separate-stderr just-runit -v https://fixture.invalid/tool.sh ls
	assert_success
	assert_output 'own-ls'
	[[ ${stderr} == *"note: script function 'ls' shadows a shell command"* ]] ||
		false
	assert_equal "$(_runs)" 1
}

@test 'SPEC FUNCTION does not call the function when the top level fails' {
	# shellcheck disable=SC2016  # the fixture's own expansion
	printf 'hello() { echo ran; }\necho top >>"${COUNT}"\nfalse\n' \
		>"${fixtures}/tool.sh"
	run just-runit https://fixture.invalid/tool.sh hello
	assert_failure
	refute_output --partial 'ran'
	assert_equal "$(_runs)" 1
}
