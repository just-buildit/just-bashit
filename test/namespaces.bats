# shellcheck disable=SC2154  # bats/common-setup export the harness vars
load 'test_helper/common-setup'
_common_setup

# Built-in namespaces, resolved offline. A curl stub answers every fetch and
# logs each URL it was asked for, so a test can say which URL jbx resolved
# and which probes it made. `-n` keeps the aliases.toml lookup out of the
# cache. The script itself is a stub that prints its own name.

_ns_stub() {
	local fx="${BATS_TEST_TMPDIR}/fx" bin="${BATS_TEST_TMPDIR}/ns-curl"
	mkdir -p "${fx}" "${bin}"
	export JB_NS_FX="${fx}" JB_NS_LOG="${BATS_TEST_TMPDIR}/urls"
	: >"${JB_NS_LOG}"
	cat >"${bin}/curl" <<-'EOF'
		#!/usr/bin/env bash
		dest="" url="" head=0
		while [[ $# -gt 0 ]]; do
			case "${1}" in
			-o) dest="${2}"; shift 2; continue ;;
			--head) head=1 ;;
			https://*) url="${1}" ;;
			esac
			shift
		done
		[[ -n ${url} ]] || exit 0
		echo "${url}" >>"${JB_NS_LOG}"
		f="${JB_NS_FX}/${url#https://}"
		if [[ ${head} -eq 1 ]]; then
			[[ -f ${f} ]] && printf 200 || printf 404
			exit 0
		fi
		[[ -f ${f} ]] || exit 22
		cp "${f}" "${dest}"
	EOF
	chmod +x "${bin}/curl"
	export PATH="${bin}:${PATH}"
}

# _ns_put URL BODY -- serve BODY at URL.
_ns_put() {
	local f="${JB_NS_FX}/${1#https://}"
	mkdir -p "${f%/*}"
	printf '%s\n' "${2}" >"${f}"
}

@test 'just-makeit:NAME resolves through the namespace aliases.toml' {
	_ns_stub
	local base=https://just-buildit.github.io/just-makeit
	_ns_put "${base}/aliases.toml" \
		"[aliases]
install-deps = \"${base}/installer.sh\""
	_ns_put "${base}/installer.sh" 'echo "ran the aliased installer"'
	run just-runit run -n just-makeit:install-deps
	assert_success
	assert_output 'ran the aliased installer'
	run grep -c "^${base}/aliases.toml\$" "${JB_NS_LOG}"
	assert_output 1
	run grep -c 'just-buildit.github.io/aliases.toml' "${JB_NS_LOG}"
	assert_output 0
}

@test 'just-makeit:NAME absent from aliases.toml falls to the direct probe' {
	_ns_stub
	local base=https://just-buildit.github.io/just-makeit
	_ns_put "${base}/aliases.toml" '[aliases]
other = "https://just-buildit.github.io/just-makeit/other.sh"'
	_ns_put "${base}/probed.sh" 'echo "ran the probed script"'
	run just-runit run -n just-makeit:probed
	assert_success
	assert_output 'ran the probed script'
	run grep -c "^${base}/probed.sh\$" "${JB_NS_LOG}"
	assert_output --regexp '^[1-9]'
}

@test 'an unknown namespace is refused, naming all three built-ins' {
	_ns_stub
	run just-runit run -n nope:thing
	assert_failure
	assert_output --partial "unknown namespace 'nope'"
	assert_output --partial 'known: just-buildit, just-bashit, just-makeit'
}

@test '-h lists every built-in namespace with its base' {
	run just-runit run -h
	assert_success
	assert_output --partial 'just-buildit          https://just-buildit.github.io/   (default)'
	assert_output --partial 'just-bashit           https://just-buildit.github.io/jbs/'
	assert_output --partial 'just-makeit           https://just-buildit.github.io/just-makeit/'
}
