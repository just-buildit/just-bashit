# shellcheck disable=SC2154  # bats/common-setup export the harness vars
load 'test_helper/common-setup'
_common_setup

# `just-runit install` warms the cache for every [tools.*] source in
# bootstrap.toml, so a later `jbx <tool>` is a cache hit. It must run none of
# them. It fetched each one by running itself with -l, and -l lists a
# script's functions by SOURCING it: every tool without a main guard ran,
# its output discarded. setup-system.sh is such a tool, and this repo's own
# bootstrap.toml names it (just-bashit#117).

# A tool with no main guard -- sourcing it runs it, and running it touches
# ${ran} -- served offline, and a project whose bootstrap.toml names it.
setup() {
	fixtures="${BATS_TEST_TMPDIR}/fixtures"
	ran="${BATS_TEST_TMPDIR}/ran"
	mkdir -p "${fixtures}" "${BATS_TEST_TMPDIR}/proj"
	printf '#!/usr/bin/env bash\ntouch %q\n' "${ran}" >"${fixtures}/tool.sh"
	printf '[tools.tool]\nsource = "https://fixture.invalid/tool.sh"\n' \
		>"${BATS_TEST_TMPDIR}/proj/bootstrap.toml"
	_serve_fixtures "${fixtures}"
	export XDG_CACHE_HOME="${BATS_TEST_TMPDIR}/cache"
}

@test 'install fetches a tool into the cache and does not run it' {
	cd "${BATS_TEST_TMPDIR}/proj"
	run just-runit install
	assert_success
	assert_output --partial '1 fetched'
	refute [ -e "${ran}" ]

	# The fetch is the one jbx reads: with the network gone, the tool still
	# runs, from the cache install filled.
	rm "${fixtures}/tool.sh"
	run just-runit https://fixture.invalid/tool.sh
	assert_success
	assert [ -e "${ran}" ]
}

@test '-f caches a script, prints its path and does not run it' {
	run just-runit -f https://fixture.invalid/tool.sh
	assert_success
	refute [ -e "${ran}" ]
	assert [ -f "${output}" ]
	run cmp "${output}" "${fixtures}/tool.sh"
	assert_success
}

# This repo's own bootstrap.toml must install: every [tools.*] source is a
# SPEC just-runit resolves. Three `src/...` paths never did -- just-runit
# has no local-path SPEC -- and `install` failed on them from the day they
# landed (#119). Offline: the scripts the CDN publishes are served from the
# tree that publishes them, so the resolution is just-runit's own and only
# the bytes are local.
@test "this repo's own bootstrap.toml installs" {
	export JB_FIXTURES="${PROJECT_ROOT}/src/just_bashit"
	cp "${PROJECT_ROOT}/bootstrap.toml" "${BATS_TEST_TMPDIR}/proj/bootstrap.toml"
	cd "${BATS_TEST_TMPDIR}/proj"
	run just-runit install
	assert_success
	refute_output --partial 'failed'
}
