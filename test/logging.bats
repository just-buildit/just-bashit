load 'test_helper/common-setup'
source 'src/logging.sh'
source 'src/format.sh'
_common_setup

@test 'log-wait help' {
	run log-wait -h
	# shellcheck disable=SC2154
	assert_output --regexp "${HELP_REGEX}"
}

@test 'log-wait -g' {
	run log-wait -g
	assert_output --regexp "$(
		echo "Invalid option: -g"
		# shellcheck disable=SC2154
		echo "${HELP_REGEX}"
	)"
}

@test 'log-wait' {
	run log-wait
	assert_output -- "DURATION must be >= 0."
	assert_failure
}

@test 'log-wait NaN' {
	run log-wait fty43
	assert_output -- "DURATION must be >= 0."
	assert_failure
}

@test 'log-wait -1' {
	run log-wait -1
	assert_output -- "DURATION must be >= 0."
	assert_failure
}

@test 'log-wait measure' {
	TIMEFORMAT=%R
	EXPECTED=1.2
	MEASURED=$({ time log-wait "${EXPECTED}"; } 2>&1)
	assert [ "${MEASURED:0:3}" == "${EXPECTED}" ]
}

@test 'log help' {
	run log -h
	# shellcheck disable=SC2154
	assert_output --regexp "${HELP_REGEX}"
}

@test 'log -g' {
	run log -g
	assert_output --regexp "$(
		echo "Invalid option: -g"
		# shellcheck disable=SC2154
		echo "${HELP_REGEX}"
	)"
}

# Makes some helpers to avoid code duplication
expected_log() {
	local TYPE=${1:-'INFO'}       # First arg is type, default 'INFO'
	local -i RESOLUTION=${2:-'0'} # Next is fractional timestamp digits
	local -i COLORS=${3:-'1'}     # Next is colors
	shift 3                       # Get rid of first two arguments - rest are used as message
	local RES=''
	local -A CODES=([INFO]=37 [WARNING]=33 [ERROR]=31 [SUCCESS]=32 [DEBUG]=33)
	((RESOLUTION)) && RES='\.[0-9]{'"${RESOLUTION}"'}'
	local BGN='(^\$)'"(')"
	local ESC='(\\e|\\E|\\033|\\x1b|\\x1B|27|\^\[)'
	local FMT='(\[1\;'"${CODES[${TYPE}]}"'m)'
	local TAG='(\[[0-9]{8}T[0-9]{6}'"${RES}"'Z::'"${TYPE}"'\])::'
	local MSG="${*}"
	local END='\[0m'
	local EXPECTED="${BGN}${ESC}${FMT}${TAG}${MSG}${ESC}${END}"
	((COLORS)) || EXPECTED="${TAG}${*}"
	echo "${EXPECTED}"
}

expected_log_helper() {
	options=('-' '-m' '-u' '-n')
	digits=(0 3 6 9)
	type=${1:-'INFO'}
	colors=${2:-'AUTO'}
	for i in "${!options[@]}"; do
		opts="${options["${i}"]}"
		opts+='t'
		if [ "${colors}" == 'ON' ]; then
			run printf %q "$(log -c "${colors}" "${opts}" "${type}" my message)"
			assert_output --regexp "$(expected_log "${type}" "${digits["${i}"]}" 1 my message)"
		else
			run log -c "${colors}" "${opts}" "${type}" my message
			assert_output --regexp "$(expected_log "${type}" "${digits["${i}"]}" 0 my message)"
		fi
	done
}

@test 'log -c AUTO' {
	run log -c AUTO
	assert_output --regexp "$(expected_log INFO 0 0)"
}

@test 'log -c AUTO my message' {
	run log -c AUTO my message
	assert_output --regexp "$(expected_log INFO 0 0 my message)"
}

@test "log option -c AUTO -t INFO my message" {
	expected_log_helper INFO 'AUTO'
}

@test "log option -c AUTO -t WARNING my message" {
	expected_log_helper WARNING 'AUTO'
}
@test "log option -c AUTO -t ERROR my message" {
	expected_log_helper ERROR 'AUTO'
}
@test "log option -c AUTO -t SUCCESS my message" {
	expected_log_helper SUCCESS 'AUTO'
}
@test "log option -c AUTO -t DEBUG my message" {
	expected_log_helper DEBUG 'AUTO'
}

@test 'log -c ON' {
	run printf %q "$(log -c ON)"
	assert_output --regexp "$(expected_log INFO 0 1)"
}

@test 'log -c ON my message' {
	run printf %q "$(log -c ON my message)"
	assert_output --regexp "$(expected_log INFO 0 1 my message)"
}

@test "log option -c ON -t INFO my message" {
	expected_log_helper INFO ON
}

@test "log option -c ON -t WARNING my message" {
	expected_log_helper WARNING ON
}
@test "log option -c ON -t ERROR my message" {
	expected_log_helper ERROR ON
}
@test "log option -c ON -t SUCCESS my message" {
	expected_log_helper SUCCESS ON
}
@test "log option -c ON -t DEBUG my message" {
	expected_log_helper DEBUG ON
}
@test 'log -c OFF' {
	run log -c OFF
	assert_output --regexp "$(expected_log INFO 0 0)"
}

@test 'log -c OFF my message' {
	run log -c OFF my message
	assert_output --regexp "$(expected_log INFO 0 0 my message)"
}

@test "log option -c OFF -t INFO my message" {
	expected_log_helper INFO OFF
}

@test "log option -c OFF -t WARNING my message" {
	expected_log_helper WARNING OFF
}
@test "log option -c OFF -t ERROR my message" {
	expected_log_helper ERROR OFF
}
@test "log option -c OFF -t SUCCESS my message" {
	expected_log_helper SUCCESS OFF
}
@test "log option -c OFF -t DEBUG my message" {
	expected_log_helper DEBUG OFF
}

@test 'log' {
	run log
	assert_output --regexp "$(expected_log INFO 0 0)"
}

@test 'log my message' {
	run log my message
	assert_output --regexp "$(expected_log INFO 0 0 my message)"
}

@test "log option -t INFO my message" {
	expected_log_helper INFO
}

@test "log option -t WARNING my message" {
	expected_log_helper WARNING
}
@test "log option -t ERROR my message" {
	expected_log_helper ERROR
}
@test "log option -t SUCCESS my message" {
	expected_log_helper SUCCESS
}
@test "log option -t DEBUG my message" {
	expected_log_helper DEBUG
}
