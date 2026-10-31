# shellcheck disable=SC2154  # bats/common-setup export the harness vars
load 'test_helper/common-setup'
_common_setup

# A bare name resolves through the default namespace's aliases.toml first and
# probes https://just-buildit.github.io/NAME.sh only when the file was read
# and does not list it (just-bashit#164). A fetch of aliases.toml that failed
# used to read as "not listed": `jbx install-deps` probed the org root, found
# its mirror copy of install-deps.sh, cached it alone and died sourcing
# toml.sh. Every case here gets its own fixture directory and its own cache,
# since jbx caches by URL and a second answer for one URL would be read from
# the first one's cache.

# _case NAME -- a fresh fixture directory served by _serve_fixtures, and a
# cache of its own, for one case of a test.
_case() {
	CASE_FX="${BATS_TEST_TMPDIR}/${1}/fixtures"
	CASE_CACHE="${BATS_TEST_TMPDIR}/${1}/cache"
	mkdir -p "${CASE_FX}" "${CASE_CACHE}"
	_serve_fixtures "${CASE_FX}"
}

_aliases_key() {
	printf '%s' https://just-buildit.github.io | sha256sum | cut -d' ' -f1
}

@test 'an aliases.toml that cannot be fetched is refused, naming the URL' {
	_case unreachable
	echo 6 >"${CASE_FX}/aliases.toml.curl-exit"
	# The probe would succeed: the bug ran this.
	echo 'echo "ran the probed root copy"' >"${CASE_FX}/tool.sh"
	XDG_CACHE_HOME="${CASE_CACHE}" run just-runit tool
	assert_failure
	assert_output --partial 'could not fetch https://just-buildit.github.io/aliases.toml'
	assert_output --partial 'Could not resolve host: just-buildit.github.io'
	refute_output --partial 'ran the probed root copy'
	run grep -c 'tool.sh' "${JB_FIXTURES_LOG}"
	assert_output 0
}

@test 'the aliases.toml fetch is bounded by the shared retries' {
	_case retries
	printf '[aliases]\n' >"${CASE_FX}/aliases.toml"
	local log="${BATS_TEST_TMPDIR}/args" shim="${BATS_TEST_TMPDIR}/argshim"
	mkdir -p "${shim}"
	printf '#!/usr/bin/env bash\n[[ " $* " == *aliases.toml* ]] && echo "$*" >>%q\nexec %q "$@"\n' \
		"${log}" "$(command -v curl)" >"${shim}/curl"
	chmod +x "${shim}/curl"
	PATH="${shim}:${PATH}" XDG_CACHE_HOME="${CASE_CACHE}" run just-runit tool
	run cat "${log}"
	assert_output --partial '--retry 3'
	assert_output --partial '--fail'
}

@test 'an HTTP error page for aliases.toml is refused and not cached' {
	_case error-page
	# No aliases.toml fixture: the server answers 404.
	echo 'echo "ran the probed root copy"' >"${CASE_FX}/tool.sh"
	XDG_CACHE_HOME="${CASE_CACHE}" run just-runit tool
	assert_failure
	assert_output --partial 'could not fetch https://just-buildit.github.io/aliases.toml'
	assert_output --partial 'error: 404'
	refute_output --partial 'ran the probed root copy'
	run find "${CASE_CACHE}" -name 'aliases-*'
	assert_output ''
}

@test 'a 200 that is not an aliases file is refused and not cached' {
	_case portal
	echo '<html>sign in to the wifi</html>' >"${CASE_FX}/aliases.toml"
	echo 'echo "ran the probed root copy"' >"${CASE_FX}/tool.sh"
	XDG_CACHE_HOME="${CASE_CACHE}" run just-runit tool
	assert_failure
	assert_output --partial 'no [aliases] table'
	refute_output --partial 'ran the probed root copy'
	run find "${CASE_CACHE}" -name 'aliases-*'
	assert_output ''
}

@test 'a name absent from a good aliases.toml still falls to the probe' {
	_case absent
	printf '[aliases]\nother = "https://fixture.invalid/other.sh"\n' \
		>"${CASE_FX}/aliases.toml"
	echo 'echo "ran the probed script"' >"${CASE_FX}/tool.sh"
	XDG_CACHE_HOME="${CASE_CACHE}" run just-runit tool
	assert_success
	assert_output 'ran the probed script'
}

# Point 4 of #164: a cached aliases.toml past its TTL answers when the refetch
# fails, with a warning, because it was fetched and checked in full -- out of
# date, but not wrong, where the probe is. -r and -n ask for a fresh copy, so
# under them the failure is refused.
_stale_cache() {
	local cache="${1}/just-runit" key
	key="$(_aliases_key)"
	mkdir -p "${cache}"
	printf '[aliases]\ntool = "https://fixture.invalid/aliased.sh"\n' \
		>"${cache}/aliases-${key}.toml"
	printf 'ts=1\nurl=https://just-buildit.github.io/aliases.toml\n' \
		>"${cache}/aliases-${key}.meta"
}

@test 'a stale cached aliases.toml answers when the refetch fails, loudly' {
	_case stale
	_stale_cache "${CASE_CACHE}"
	echo 6 >"${CASE_FX}/aliases.toml.curl-exit"
	echo 'echo "ran the aliased script"' >"${CASE_FX}/aliased.sh"
	echo 'echo "ran the probed root copy"' >"${CASE_FX}/tool.sh"
	XDG_CACHE_HOME="${CASE_CACHE}" run just-runit tool
	assert_success
	assert_line 'ran the aliased script'
	assert_output --partial 'warning: could not refetch https://just-buildit.github.io/aliases.toml'
	# The timestamp is left stale, so the next run tries again.
	run cat "${CASE_CACHE}/just-runit/aliases-$(_aliases_key).meta"
	assert_line 'ts=1'
}

@test 'a stale cached aliases.toml is not used under -r' {
	_case stale-refresh
	_stale_cache "${CASE_CACHE}"
	echo 6 >"${CASE_FX}/aliases.toml.curl-exit"
	echo 'echo "ran the aliased script"' >"${CASE_FX}/aliased.sh"
	XDG_CACHE_HOME="${CASE_CACHE}" run just-runit -r tool
	assert_failure
	assert_output --partial 'could not fetch https://just-buildit.github.io/aliases.toml'
	refute_output --partial 'ran the aliased script'
}

@test 'a cached error page is never used as aliases.toml' {
	_case cached-page
	local cache="${CASE_CACHE}/just-runit" key
	key="$(_aliases_key)"
	mkdir -p "${cache}"
	# What a jbx without --fail cached: fresh by its timestamp, but a page.
	echo '<html>503</html>' >"${cache}/aliases-${key}.toml"
	printf 'ts=%s\nurl=https://just-buildit.github.io/aliases.toml\n' \
		"$(date +%s)" >"${cache}/aliases-${key}.meta"
	echo 6 >"${CASE_FX}/aliases.toml.curl-exit"
	echo 'echo "ran the probed root copy"' >"${CASE_FX}/tool.sh"
	XDG_CACHE_HOME="${CASE_CACHE}" run just-runit tool
	assert_failure
	assert_output --partial 'could not fetch https://just-buildit.github.io/aliases.toml'
	refute_output --partial 'ran the probed root copy'
}

# Point 3 of #164: the org root serves a copy of install-deps.sh, which
# sources toml.sh and pkg.sh from its own directory. Reached by its URL --
# hardcoded, or probed because aliases.toml stopped listing it -- it is run
# through the co-fetch from jbs/, so its libraries sit beside it. The
# fixtures are the real libraries and the real install-deps.sh.
@test 'a just-bashit script at the org root runs beside its libraries' {
	_case root-copy
	cp "${PROJECT_ROOT}"/src/just_bashit/*.sh "${CASE_FX}/"
	XDG_CACHE_HOME="${CASE_CACHE}" \
		run just-runit https://just-buildit.github.io/install-deps.sh --help
	assert_success
	assert_output --partial 'Usage: install-deps.sh'
	refute_output --partial 'No such file'
	run grep -cx 'https://just-buildit.github.io/jbs/toml.sh' "${JB_FIXTURES_LOG}"
	assert_output 1
}

@test 'a standalone script at the org root is run as fetched' {
	_case root-standalone
	echo 'echo "ran standalone"' >"${CASE_FX}/standalone.sh"
	XDG_CACHE_HOME="${CASE_CACHE}" \
		run just-runit https://just-buildit.github.io/standalone.sh
	assert_success
	assert_output 'ran standalone'
	run grep -c '/jbs/' "${JB_FIXTURES_LOG}"
	assert_output 0
}

# get-jb.sh downloads just-runit itself; without --fail a 404 page would be
# installed as jbx.
@test 'get-jb.sh refuses an HTTP error instead of installing the page' {
	_case get-jb
	local home="${BATS_TEST_TMPDIR}/home"
	mkdir -p "${home}"
	# It is sourced, so its exit is the trailing unset's; the outcome is
	# what it printed and what it left in ~/.local/bin.
	HOME="${home}" run bash "${PROJECT_ROOT}/src/just_bashit/get-jb.sh"
	assert_output --partial 'failed to download jb'
	refute [ -e "${home}/.local/bin/just-runit" ]
}
