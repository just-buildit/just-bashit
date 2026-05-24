load 'test_helper/common-setup'
source 'src/network.sh'
_common_setup

@test 'test-internet-access help' {
	run test-internet-access -h
	# shellcheck disable=SC2154
	assert_output --regexp "${HELP_REGEX}"
}

@test 'test-internet-access' {
	run test-internet-access
	assert_success
}

@test 'test-internet-access -v' {
	run test-internet-access -v
	assert_success
}

@test '-t sets numeric timeout' {
	run test-internet-access -t 30
	assert_success
}

@test '-t with invalid value shows error' {
	run test-internet-access -t abc
	assert_output --partial "Invalid Value"
}

@test 'unknown option shows error' {
	run test-internet-access -z
	assert_output --partial "Invalid option"
}

@test 'custom URL argument' {
	run test-internet-access https://example.com
	assert_success
}

@test '-v shows URL and Timeout in output' {
	run test-internet-access -v -t 30 https://example.com
	assert_success
	assert_output --partial "URL:"
	assert_output --partial "Timeout:"
}

@test '-v reports available commands' {
	run test-internet-access -v https://example.com
	assert_success
	assert_output --regexp "(curl|wget|ping) command found"
}

@test '-t with multiple custom URLs' {
	run test-internet-access -t 30 https://example.com https://google.com
	assert_success
}
