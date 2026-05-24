load 'test_helper/common-setup'
source 'src/environment.sh'
_common_setup

@test 'set-bashrc help' {
	run set-bashrc -h
	# shellcheck disable=SC2154
	assert_output --regexp "${HELP_REGEX}"
}

@test 'set-bashrc unknown option -k' {
	run set-bashrc -k
	assert_output --regexp "$(
		echo "Invalid option: -k"
		# shellcheck disable=SC2154
		echo "${HELP_REGEX}"
	)"
}

@test 'set-bashrc no input' {
	run set-bashrc
	# shellcheck disable=SC2154
	assert_output --partial "Not enough arguments"
	assert_output --regexp "${HELP_REGEX}"
}

@test 'set-bashrc entry' {
	run set-bashrc 'MY_NEW_LINE'
	run bash -c "awk '/^MY_NEW_LINE$/' ~/.bashrc | grep ."
	assert_success
}

@test 'set-bashrc key-value' {
	run set-bashrc 'MY_KEY' 'MY_VALUE'
	run bash -c "awk '/^export MY_KEY=MY_VALUE$/' ~/.bashrc | grep ."
	assert_success
}

@test 'unset-bashrc -h' {
	run unset-bashrc -h
	# shellcheck disable=SC2154
	assert_output --regexp "${HELP_REGEX}"
}

@test 'unset-bashrc unknown option -k' {
	run unset-bashrc -k
	assert_output --regexp "$(
		echo "Invalid option: -k"
		# shellcheck disable=SC2154
		echo "${HELP_REGEX}"
	)"
}

@test 'unset-bashrc no input' {
	run unset-bashrc
	# shellcheck disable=SC2154
	assert_output --partial "Not enough arguments"
	assert_output --regexp "${HELP_REGEX}"
}

@test 'unset-bashrc entry' {
	run unset-bashrc 'MY_NEW_LINE'
	run bash -c "awk '/^MY_NEW_LINE$/' ~/.bashrc | grep . |&"
	assert_failure
}

@test 'unset-bashrc key-value' {
	run unset-bashrc 'MY_KEY' 'MY_VALUE'
	run bash -c "awk '/^export MY_KEY=MY_VALUE$/' ~/.bashrc | grep . |&"
	assert_failure
}
