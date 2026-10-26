# shellcheck disable=SC2154  # bats/common-setup export the harness vars
# shellcheck disable=SC2030,SC2031  # bats runs each @test in a subshell;
# run --separate-stderr sets $stderr there, and _refuses reads it there too
load 'test_helper/common-setup'
_common_setup
bats_require_minimum_version 1.5.0

# The repository SPEC form (#136): [FORGE+]https://HOST[:PORT]/PROJECT//PATH[@REF]
# resolves to the forge's raw-file URL, then goes through the ordinary fetch.
#
# Offline: the fixture curl serves fixtures/<basename of the URL>, and a
# wrapper in front of it logs every URL curl was asked for, which is how each
# test sees exactly which raw URL a SPEC resolved to.
_repo_curl() {
	local fx="${BATS_TEST_TMPDIR}/fixtures" bin="${BATS_TEST_TMPDIR}/log-curl"
	mkdir -p "${fx}" "${bin}"
	_serve_fixtures "${fx}"
	CURL_LOG="${BATS_TEST_TMPDIR}/curl.log"
	: >"${CURL_LOG}"
	cat >"${bin}/curl" <<-EOF
		#!/usr/bin/env bash
		for a in "\$@"; do
			[[ \${a} == https://* ]] && printf '%s\n' "\${a}" >>"${CURL_LOG}"
		done
		exec "${BATS_TEST_TMPDIR}/fixture-curl/curl" "\$@"
	EOF
	chmod +x "${bin}/curl"
	PATH="${bin}:${PATH}"
	export XDG_CACHE_HOME="${BATS_TEST_TMPDIR}/cache"
	# shellcheck disable=SC2016  # the script's own text, expanded when it runs
	printf '%s\n' 'say() { echo "say:$*"; }' >"${fx}/tool.sh"
}

# Run SPEC's `say` function and assert the one URL fetched.
_resolves_to() {
	local spec="${1}" want="${2}"
	run --separate-stderr just-runit "${spec}" say hi there
	assert_success
	assert_output 'say:hi there'
	run cat "${CURL_LOG}"
	assert_output "${want}"
}

# -- the hosts --------------------------------------------------------------

@test 'github.com, default ref: the default branch, via raw.githubusercontent.com' {
	_repo_curl
	_resolves_to 'https://github.com/acme/tools//bin/tool.sh' \
		'https://raw.githubusercontent.com/acme/tools/HEAD/bin/tool.sh'
}

@test 'github.com with a tag, and a .git suffix on the repository' {
	_repo_curl
	_resolves_to 'https://github.com/acme/tools.git//tool.sh@v1.2.0' \
		'https://raw.githubusercontent.com/acme/tools/v1.2.0/tool.sh'
}

@test 'gitlab.com: nested groups, a commit SHA' {
	_repo_curl
	_resolves_to 'https://gitlab.com/acme/platform/tools//ci/tool.sh@0123abcd' \
		'https://gitlab.com/acme/platform/tools/-/raw/0123abcd/ci/tool.sh'
}

@test 'codeberg.org is Forgejo: the gitea layout' {
	_repo_curl
	_resolves_to 'https://codeberg.org/acme/tools//tool.sh@main' \
		'https://codeberg.org/acme/tools/raw/main/tool.sh'
}

@test 'bitbucket.org' {
	_repo_curl
	_resolves_to 'https://bitbucket.org/acme/tools//tool.sh' \
		'https://bitbucket.org/acme/tools/raw/HEAD/tool.sh'
}

@test 'self-hosted Gitea with an explicit port' {
	_repo_curl
	_resolves_to 'gitea+https://git.example.com:3000/ops/tools//bin/tool.sh@v2' \
		'https://git.example.com:3000/ops/tools/raw/v2/bin/tool.sh'
}

@test 'forgejo+ is gitea+' {
	_repo_curl
	_resolves_to 'forgejo+https://forge.example.com/ops/tools//tool.sh' \
		'https://forge.example.com/ops/tools/raw/HEAD/tool.sh'
}

@test 'self-managed GitLab with a port' {
	_repo_curl
	_resolves_to 'gitlab+https://gitlab.example.com:8443/a/b/c//tool.sh' \
		'https://gitlab.example.com:8443/a/b/c/-/raw/HEAD/tool.sh'
}

@test 'GitHub Enterprise Server' {
	_repo_curl
	_resolves_to 'github+https://ghe.example.com/acme/tools//tool.sh@rel-3' \
		'https://ghe.example.com/acme/tools/raw/rel-3/tool.sh'
}

# -- what stays as it was ----------------------------------------------------

@test 'a plain script URL is still fetched as given' {
	_repo_curl
	_resolves_to 'https://example.test/path/tool.sh' \
		'https://example.test/path/tool.sh'
}

@test 'gh: keeps its main default' {
	_repo_curl
	_resolves_to 'gh:acme/tools/tool.sh' \
		'https://raw.githubusercontent.com/acme/tools/main/tool.sh'
}

@test 'a repository SPEC is cached, and checked by -k, like any URL' {
	_repo_curl
	local fx="${BATS_TEST_TMPDIR}/fixtures" hash
	if command -v sha256sum >/dev/null 2>&1; then
		hash=$(sha256sum "${fx}/tool.sh" | cut -d' ' -f1)
	else
		hash=$(shasum -a 256 "${fx}/tool.sh" | cut -d' ' -f1)
	fi
	run just-runit -k "sha256:${hash}" 'https://github.com/acme/tools//tool.sh' say a
	assert_success
	assert_output 'say:a'
	run just-runit 'https://github.com/acme/tools//tool.sh' say b
	assert_success
	assert_output 'say:b'
	run grep -c tool.sh "${CURL_LOG}"
	assert_output 1
	run just-runit -r -k "sha256:0000" 'https://github.com/acme/tools//tool.sh' say c
	assert_failure
	refute_output --partial 'say:c'
}

# -- refusals ------------------------------------------------------------------

_refuses() {
	local spec="${1}" why="${2}"
	run --separate-stderr just-runit "${spec}" say x
	assert_failure
	refute_output --partial 'say:'
	[[ ${stderr} == *"${why}"* ]] || fail "stderr lacks '${why}': ${stderr}"
	[[ ! -s ${CURL_LOG} ]] || fail "fetched despite the refusal: $(cat "${CURL_LOG}")"
}

@test 'an unknown host without a forge is refused, naming the fix' {
	_repo_curl
	_refuses 'https://git.example.com/ops/tools//tool.sh' \
		'name it, e.g. gitea+https://git.example.com/'
}

@test 'an unknown forge is refused' {
	_repo_curl
	_refuses 'svn+https://git.example.com/ops/tools//tool.sh' "unknown forge 'svn'"
}

@test 'http, ssh:// and scp-style SSH are refused' {
	_repo_curl
	_refuses 'http://github.com/acme/tools//tool.sh' 'HTTPS only'
	_refuses 'gitea+http://git.example.com/ops/tools//tool.sh' 'HTTPS only'
	_refuses 'ssh://git@github.com/acme/tools//tool.sh' 'HTTPS only'
	_refuses 'git@github.com:acme/tools//tool.sh' 'SSH repository URLs are not supported'
}

@test 'credentials are refused and never echoed' {
	_repo_curl
	_refuses 'https://bob:s3cret-token@github.com/acme/tools//tool.sh' \
		'credentials in a repository URL are refused (github.com)'
	[[ ${stderr} != *s3cret* ]] || fail "the secret was echoed: ${stderr}"
}

@test 'a missing, absolute or climbing path is refused' {
	_repo_curl
	_refuses 'https://github.com/acme/tools//' 'no script path'
	_refuses 'https://github.com/acme/tools///etc/tool.sh' 'no script path'
	_refuses 'https://github.com/acme/tools//a/../tool.sh' "no empty or '..' segments"
}

@test 'a repository that is not OWNER/REPO is refused, GitLab groups aside' {
	_repo_curl
	_refuses 'https://github.com/acme/tools/extra//tool.sh' 'OWNER/REPO'
	_refuses 'https://gitlab.com/solo//tool.sh' 'GROUP/.../PROJECT'
}

@test 'a ref with a slash, or an empty ref, is refused' {
	_repo_curl
	_refuses 'https://github.com/acme/tools//tool.sh@feature/x' 'pin a tag or commit SHA'
	_refuses 'https://github.com/acme/tools//tool.sh@' 'empty ref'
}

@test 'Bitbucket Server is refused' {
	_repo_curl
	_refuses 'bitbucket+https://bb.example.com/acme/tools//tool.sh' \
		'only Bitbucket Cloud'
}
