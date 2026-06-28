# shellcheck disable=SC2154  # bats/common-setup export the harness vars
load 'test_helper/common-setup'
_common_setup

# A non-200 fetch must fail CLOSED: jbx must never cache or execute the HTTP
# error body as if it were the script. Regression for the recurring CI failure
# "install-deps.sh: line 1: 400:: command not found" — an error page (a 404, or
# a raw.githubusercontent rate-limit response on a shared runner IP) silently
# became the "script" because _fetch_to fetched with `curl -sSL` and no --fail.
@test "fetch fails closed on a non-200 URL (never runs the error body)" {
	run just-runit "https://just-buildit.github.io/__just_runit_fetch_fail_test__.sh"
	assert_failure
	refute_output --partial 'command not found'
	assert_output --partial 'fetch failed'
}
