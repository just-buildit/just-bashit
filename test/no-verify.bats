# shellcheck disable=SC2154  # bats/common-setup export the harness vars
load 'test_helper/common-setup'
_common_setup
bats_require_minimum_version 1.5.0

# --no-verify skips TLS certificate checks on jbx's own downloads, for a
# network whose proxy re-signs TLS with a CA the box does not trust. It is
# the one long option, so it is parsed before getopts, and only among the
# options before SPEC: an argument after SPEC is the script's.
#
# The fixture curl serves the files under fixtures/; a wrapper in front of it
# logs every argument list curl was called with, one call per line, which is
# what these tests read.
_logging_curl() {
	local fx="${BATS_TEST_TMPDIR}/fixtures" bin="${BATS_TEST_TMPDIR}/log-curl"
	mkdir -p "${fx}" "${bin}"
	_serve_fixtures "${fx}"
	CURL_LOG="${BATS_TEST_TMPDIR}/curl.log"
	cat >"${bin}/curl" <<-EOF
		#!/usr/bin/env bash
		printf '%s\n' "\$*" >>"${CURL_LOG}"
		exec "${BATS_TEST_TMPDIR}/fixture-curl/curl" "\$@"
	EOF
	chmod +x "${bin}/curl"
	PATH="${bin}:${PATH}"
	export XDG_CACHE_HOME="${BATS_TEST_TMPDIR}/cache"
	# shellcheck disable=SC2016  # the script's own text, expanded when it runs
	echo 'echo "args:$*"' >"${fx}/tool.sh"
}

_sha_of() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "${1}" | cut -d' ' -f1
	else
		shasum -a 256 "${1}" | cut -d' ' -f1
	fi
}

# Every logged call that fetched something, i.e. not the --help probe.
_fetch_calls() {
	grep -v -- '--help' "${CURL_LOG}"
}

@test '--no-verify passes --insecure to curl, and warns' {
	_logging_curl
	run --separate-stderr just-runit --no-verify https://example.test/tool.sh
	assert_success
	assert_output 'args:'
	[[ ${stderr} == *'--no-verify: TLS certificates are not checked'* ]]
	run _fetch_calls
	assert_output --partial '--insecure'
	while IFS= read -r call; do
		[[ ${call} == *--insecure* ]] || fail "a fetch without --insecure: ${call}"
	done < <(_fetch_calls)
}

@test 'without --no-verify, curl verifies' {
	_logging_curl
	run --separate-stderr just-runit https://example.test/tool.sh
	assert_success
	[[ ${stderr} != *'--no-verify'* ]]
	run grep -c -- '--insecure' "${CURL_LOG}"
	assert_output 0
}

@test '--no-verify after SPEC belongs to the script, not to jbx' {
	_logging_curl
	run --separate-stderr just-runit https://example.test/tool.sh --no-verify
	assert_success
	assert_output 'args:--no-verify'
	run grep -c -- '--insecure' "${CURL_LOG}"
	assert_output 0
}

@test '--no-verify combines with -n and a -k HASH, clustered or not' {
	_logging_curl
	local hash
	hash=$(_sha_of "${BATS_TEST_TMPDIR}/fixtures/tool.sh")
	run --separate-stderr just-runit -nk "sha256:${hash}" --no-verify \
		https://example.test/tool.sh
	assert_success
	assert_output 'args:'
	run --separate-stderr just-runit --no-verify -n -k "sha256:${hash}" \
		https://example.test/tool.sh
	assert_success
	assert_output 'args:'
	run grep -c -- '--insecure' "${CURL_LOG}"
	refute_output 0
}

@test 'a -k value spelled like the flag is the value' {
	_logging_curl
	run --separate-stderr just-runit -k --no-verify https://example.test/tool.sh
	assert_failure
	run grep -c -- '--insecure' "${CURL_LOG}"
	assert_output 0
}

@test '--no-verify reaches the alias lookup and the jbs bundle' {
	_logging_curl
	local fx="${BATS_TEST_TMPDIR}/fixtures"
	cp "${PROJECT_ROOT}"/src/just_bashit/*.sh "${fx}/"
	echo 'echo probe ran' >"${fx}/probe.sh"
	printf '[aliases]\nprobe-alias = "https://just-buildit.github.io/jbs/probe.sh"\n' \
		>"${fx}/aliases.toml"
	run --separate-stderr just-runit --no-verify probe-alias
	assert_success
	assert_output 'probe ran'
	run grep -c 'aliases.toml' "${CURL_LOG}"
	refute_output 0
	while IFS= read -r call; do
		[[ ${call} == *--insecure* ]] || fail "a fetch without --insecure: ${call}"
	done < <(_fetch_calls)
}

# A bare name not in aliases.toml is looked up with a HEAD probe, which is a
# download too. The fixture curl answers it with nothing, so the name does not
# resolve, but the probe was still made, and with --insecure.
@test '--no-verify reaches the HEAD probe a bare name is resolved with' {
	_logging_curl
	printf '[aliases]\n' >"${BATS_TEST_TMPDIR}/fixtures/aliases.toml"
	run --separate-stderr just-runit --no-verify not-an-alias
	assert_failure
	run grep -c -- '--head' "${CURL_LOG}"
	refute_output 0
	while IFS= read -r call; do
		[[ ${call} == *--insecure* ]] || fail "a probe without --insecure: ${call}"
	done < <(grep -- '--head' "${CURL_LOG}")
}

@test 'just-runit install --no-verify fetches every tool with it' {
	_logging_curl
	local proj="${BATS_TEST_TMPDIR}/proj"
	mkdir -p "${proj}"
	printf '[tools.tool]\nsource = "https://example.test/tool.sh"\n' \
		>"${proj}/bootstrap.toml"
	cd "${proj}"
	run just-runit install --no-verify
	assert_success
	assert_output --partial '1 fetched'
	run grep -c -- '--insecure' "${CURL_LOG}"
	refute_output 0
}

@test 'just-runit install refuses an unknown argument' {
	_logging_curl
	local proj="${BATS_TEST_TMPDIR}/proj"
	mkdir -p "${proj}"
	printf '[tools.tool]\nsource = "https://example.test/tool.sh"\n' \
		>"${proj}/bootstrap.toml"
	cd "${proj}"
	run just-runit install --insecure
	assert_failure
	assert_output --partial "unknown argument '--insecure'"
}
