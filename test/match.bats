load 'test_helper/common-setup'
source 'src/just_bashit/match.sh'
_common_setup

@test 'is-number help' {
	run is-number -h
	# shellcheck disable=SC2154
	assert_output --regexp "${HELP_REGEX}"
}
@test 'is-number invalid option' {
	run is-number -g
	assert_failure
}
@test 'is-number five' {
	run is-number five
	assert_failure
}
@test 'is-number -5' {
	run is-number -5
	assert_failure
}
@test 'is-number +5' {
	run is-number +5
	assert_failure
}
@test 'is-number -s -5' {
	run is-number -s -5
	assert_success
}
@test 'is-number -s +5' {
	run is-number -s +5
	assert_success
}
@test 'is-number 5' {
	run is-number 5
	assert_success
}
@test 'is-number 5.' {
	run is-number 5.
	assert_success
}
@test 'is-number .5' {
	run is-number .5
	assert_success
}

@test 'is-number 22.5' {
	run is-number 22.5
	assert_success
}

@test 'is-number 0' {
	run is-number 0
	assert_success
}

@test 'is-number -s 0' {
	run is-number -s 0
	assert_success
}

@test 'is-number empty string' {
	run is-number ""
	assert_failure
}
