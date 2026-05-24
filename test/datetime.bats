load 'test_helper/common-setup'
source 'src/datetime.sh'
_common_setup

@test 'iso-8601-basic help' {
	run iso-8601-basic -h
	# shellcheck disable=SC2154
	assert_output --regexp "${HELP_REGEX}"
}

@test 'iso-8601-basic unknown uption -u' {
	run iso-8601-basic -k
	assert_output --regexp "$(
		echo "Invalid option: -k"
		# shellcheck disable=SC2154
		echo "${HELP_REGEX}"
	)"
}

@test 'iso-8601-basic' {
	run iso-8601-basic
	assert_output --regexp "[0-9]{8}T[0-9]{6}Z"
}

@test 'iso-8601-basic -m' {
	run iso-8601-basic -m
	assert_output --regexp "[0-9]{8}T[0-9]{6}.[0-9]{3}Z"
}

@test 'iso-8601-basic -u' {
	run iso-8601-basic -u
	assert_output --regexp "[0-9]{8}T[0-9]{6}.[0-9]{6}Z"
}

@test 'iso-8601-basic -n' {
	run iso-8601-basic -n
	assert_output --regexp "[0-9]{8}T[0-9]{6}.[0-9]{9}Z"
}

@test 'iso-8601-basic -d' {
	run iso-8601-basic -d '7:15:31 PM EDT April 1, 1987'
	assert_output --regexp "19870401T231531Z"
}
