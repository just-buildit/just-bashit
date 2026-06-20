load 'test_helper/common-setup'
source 'src/just_bashit/path.sh'
_common_setup

@test 'get-scriptpath help' {
	run get-scriptpath -h
	# shellcheck disable=SC2154
	assert_output --regexp "${HELP_REGEX}"
}

@test 'get-scriptpath' {
	run get-scriptpath
	assert_output --regexp '.*(\/git-bash-ed|csad_git-bash-ed_)*\/src'
}

@test 'set-scriptpath help' {
	run set-scriptpath -h
	# shellcheck disable=SC2154
	assert_output --regexp "${HELP_REGEX}"
}

SCRIPTPATH=""
@test 'set-scriptpath cmd' {
	# shellcheck disable=SC2119
	eval "$(set-scriptpath)"
	assert_equal "${SCRIPTPATH}" "$(get-scriptpath)"
}
