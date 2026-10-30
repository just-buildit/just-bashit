# shellcheck disable=SC2154  # bats and test/setup_suite.bash export the harness vars
load 'test_helper/common-setup'
source 'src/just_bashit/network.sh'
_common_setup

# test-internet-access is a network probe, but its tests must not be: they
# called live example.com, and a 503 from its CDN turned an unrelated PR red
# (#147). Every probe here is answered by a fake curl, wget or ping, so each
# test states the answer it gets -- up, a 503, a hang, no tool at all -- and
# asserts what the probe does with it. test/setup_suite.bash refuses any
# probe that slips past them to the real network.

# _fake_net TOOL=ANSWER... -- run with only the named fake tools; the real
# curl, wget and ping are off PATH. ANSWER is what the tool reports:
#   up    the site answers 200
#   503   the site answers 503 (curl exits 22 as --fail does, wget 8, ping 1)
#   hang  the site never answers; the tool sleeps until `timeout` kills it
# Each call is appended to $CALLS as "TOOL ARGS...".
_fake_net() {
	local fakes="${BATS_TEST_TMPDIR}/fakes" spec tool answer
	mkdir -p "${fakes}"
	export CALLS="${BATS_TEST_TMPDIR}/calls"
	: >"${CALLS}"
	for spec in "$@"; do
		tool="${spec%%=*}" answer="${spec#*=}"
		{
			echo '#!/usr/bin/env bash'
			printf 'tool=%q answer=%q\n' "${tool}" "${answer}"
			cat <<-'EOF'
				echo "${tool} $*" >>"${CALLS}"
				case "${answer}" in
				up) echo "HTTP/2 200" >&2 ;;
				503)
					echo "HTTP/2 503" >&2
					case "${tool}" in curl) exit 22 ;; wget) exit 8 ;; *) exit 1 ;; esac
					;;
				hang) exec sleep 30 ;;
				esac
			EOF
		} >"${fakes}/${tool}"
		chmod +x "${fakes}/${tool}"
	done
	local farm
	farm="$(_bin_without curl wget ping)"
	# The probe runs each tool under GNU timeout, which macOS has only from
	# Homebrew's coreutils -- outside the system dirs the farm is built from.
	# Linked alone, so its directory's other programs stay off PATH.
	[[ -e ${farm}/timeout ]] || ln -s "$(command -v timeout)" "${fakes}/timeout"
	PATH="${fakes}:${farm}"
}

@test 'test-internet-access help' {
	run test-internet-access -h
	assert_output --regexp "${HELP_REGEX}"
}

@test 'with no URL, probes the default sites and succeeds on the first answer' {
	_fake_net curl=up
	run test-internet-access
	assert_success
	# The first default site answered, so nothing else was tried.
	run cat "${CALLS}"
	assert_output --regexp '^curl --max-time 20 .* https://example\.com$'
}

@test '-v reports the sites, the timeout and the success' {
	_fake_net curl=up
	run test-internet-access -v
	assert_success
	assert_output --partial 'URL: https://example.com https://pypi.org https://google.com'
	assert_output --partial 'Timeout: 20 seconds'
	assert_output --partial 'CONNECTION SUCCESS!'
}

@test '-t sets numeric timeout' {
	_fake_net curl=up
	run test-internet-access -t 30
	assert_success
	run cat "${CALLS}"
	assert_output --regexp '^curl --max-time 30 '
}

@test '-t with invalid value shows error' {
	run test-internet-access -t abc
	assert_output --partial "Invalid Value"
}

@test 'unknown option shows error' {
	run test-internet-access -z
	assert_output --partial "Invalid option"
}

@test 'custom URL argument replaces the defaults' {
	_fake_net curl=up
	run test-internet-access https://site.test
	assert_success
	run cat "${CALLS}"
	assert_output --regexp '^curl .* https://site\.test$'
}

@test 'a 503 from the only tool and site is a failure, and -v shows it' {
	_fake_net curl=503
	run test-internet-access -v -t 30 https://site.test
	assert_failure
	assert_output --partial 'URL: https://site.test'
	assert_output --partial 'Timeout: 30 seconds'
	assert_output --partial 'HTTP/2 503'
	refute_output --partial 'CONNECTION SUCCESS!'
}

@test 'a 503 from curl falls back to wget, then ping' {
	_fake_net curl=503 wget=503 ping=up
	run test-internet-access https://site.test
	assert_success
	run cut -d' ' -f1 "${CALLS}"
	assert_output "$(printf 'curl\nwget\nping')"
}

@test '-t with multiple custom URLs tries each in turn' {
	_fake_net curl=503
	run test-internet-access -t 30 https://one.test https://two.test
	assert_failure
	run cat "${CALLS}"
	assert_line --index 0 --regexp ' https://one\.test$'
	assert_line --index 1 --regexp ' https://two\.test$'
}

@test '-v reports command availability' {
	_fake_net wget=up
	run test-internet-access -v https://site.test
	assert_success
	assert_output --partial 'curl command not found!'
	assert_output --partial 'wget command found!'
	assert_output --partial 'ping command not found!'
}

@test 'fails when none of curl, wget and ping is installed' {
	_fake_net
	run test-internet-access -v https://site.test
	assert_failure
	assert_output --partial 'curl command not found!'
	assert_output --partial 'wget command not found!'
	assert_output --partial 'ping command not found!'
}

@test 'times out and fails when the host never answers' {
	_fake_net curl=hang
	local begin=${SECONDS}
	run test-internet-access -t 1 https://site.test
	assert_equal "${status}" 124
	# timeout killed the hung probe; it did not wait out the fake's 30 s.
	((SECONDS - begin < 10))
}

# The gate the fakes above stand behind: setup_suite.bash's trap is first on
# PATH and refuses, and logs, a probe of a real site. The log is put back
# afterwards, so this one deliberate probe does not fail the suite.
@test 'the suite egress trap refuses a live probe' {
	assert_equal "$(command -v curl)" "${JB_EGRESS_TRAP}/curl"
	cp "${JB_EGRESS_LOG}" "${BATS_TEST_TMPDIR}/log"
	run test-internet-access -t 5 https://site.test
	local log
	log="$(cat "${JB_EGRESS_LOG}")"
	cp "${BATS_TEST_TMPDIR}/log" "${JB_EGRESS_LOG}"
	assert_failure
	[[ ${log} == *"network.bats: curl "*" https://site.test"* ]]
}
