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

# The bootstrap must survive curl < 7.71, which lacks --retry-all-errors —
# RHEL/Oracle/Rocky/Alma 8 ship curl 7.61, a large downstream audience where an
# unknown flag would abort every fetch ("option --retry-all-errors: is
# unknown"). With that curl shimmed, the fetch must degrade to plain --retry and
# fail for a NORMAL reason, never the unknown-flag abort.
@test "fetch degrades on a curl without --retry-all-errors (EL8 curl 7.61)" {
	local shim="${BATS_TEST_TMPDIR}/bin"
	mkdir -p "${shim}"
	cat >"${shim}/curl" <<'EOF'
#!/usr/bin/env bash
# Emulate curl 7.61: --retry-all-errors is an unknown option.
for a in "$@"; do
	if [[ $a == --retry-all-errors ]]; then
		echo "curl: option --retry-all-errors: is unknown" >&2
		exit 2
	fi
done
# A real fetch (writes with -o) fails like an unreachable host so the run ends
# in "fetch failed"; incidental best-effort probes (no -o) succeed quietly.
for a in "$@"; do [[ $a == -o ]] && exit 7; done
exit 0
EOF
	chmod +x "${shim}/curl"
	PATH="${shim}:${PATH}" run just-runit \
		"https://just-buildit.github.io/__el8_curl_compat_test__.sh"
	assert_failure
	refute_output --partial 'option --retry-all-errors: is unknown'
	assert_output --partial 'fetch failed'
}
