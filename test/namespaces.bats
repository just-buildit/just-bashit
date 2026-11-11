# shellcheck disable=SC2154  # bats/common-setup export the harness vars
# shellcheck disable=SC2016  # fixture scripts in single quotes: $ is theirs
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

# ---------------------------------------------------------------------------
# The PowerShell hand-off. get-jb.ps1's jbx function sets JB_PS1_OUT; a run
# that resolves to a PowerShell script writes the argument count, the URL and
# the script there and runs nothing, so the function can run it in the
# session. Resolution stays here, in bash: these are its tests. The function
# side is test/get-jb-ps1.bats and test/get-jb-ps1.windows.ps1.
# ---------------------------------------------------------------------------

@test 'from PowerShell, NS:NAME.ps1 is handed back, not run, with the argument count' {
	_ns_stub
	local base=https://just-buildit.github.io/just-makeit out="${BATS_TEST_TMPDIR}/handoff"
	_ns_put "${base}/aliases.toml" '[aliases]'
	_ns_put "${base}/tool.ps1" '$env:JB_T = "ran"'
	_ns_put "${base}/tool.sh" 'echo "ran the bash twin"'
	: >"${out}"
	JB_PS1_OUT="${out}" run just-runit run -n just-makeit:tool -Name 'a b' ''
	assert_success
	assert_output ''
	run cat "${out}"
	assert_output "3
${base}/tool.ps1
\$env:JB_T = \"ran\""
}

@test 'from PowerShell, [aliases.ps1] comes before the NAME.ps1 probe' {
	_ns_stub
	local base=https://just-buildit.github.io/just-makeit out="${BATS_TEST_TMPDIR}/handoff"
	_ns_put "${base}/aliases.toml" "[aliases]
install = \"${base}/sh/install.sh\"

[aliases.ps1]
install = \"${base}/ps/install.ps1\""
	_ns_put "${base}/ps/install.ps1" 'Write-Output aliased'
	_ns_put "${base}/install.ps1" 'Write-Output probed'
	: >"${out}"
	JB_PS1_OUT="${out}" run just-runit run -n just-makeit:install
	assert_success
	run sed -n 2p "${out}"
	assert_output "${base}/ps/install.ps1"
	run grep -c "^${base}/install.ps1\$" "${JB_NS_LOG}"
	assert_output 0
}

@test 'from PowerShell, a namespace with no .ps1 runs the bash script as today' {
	_ns_stub
	local base=https://just-buildit.github.io/just-makeit out="${BATS_TEST_TMPDIR}/handoff"
	_ns_put "${base}/aliases.toml" '[aliases]'
	_ns_put "${base}/tool.sh" 't() { echo "bash ran [$*] out=${JB_PS1_OUT-unset}"; }'
	: >"${out}"
	JB_PS1_OUT="${out}" run just-runit run -n just-makeit:tool t 'a b'
	assert_success
	assert_output 'bash ran [a b] out=unset'
	[ ! -s "${out}" ]
	run grep -c "^${base}/tool.ps1\$" "${JB_NS_LOG}"
	assert_output 1
}

@test 'from bash, a NAME.ps1 is never probed and [aliases.ps1] never read' {
	_ns_stub
	local base=https://just-buildit.github.io/just-makeit
	_ns_put "${base}/aliases.toml" "[aliases]

[aliases.ps1]
tool = \"${base}/tool.ps1\""
	_ns_put "${base}/tool.ps1" 'Write-Output ps'
	_ns_put "${base}/tool.sh" 'echo "bash ran"'
	run just-runit run -n just-makeit:tool
	assert_success
	assert_output 'bash ran'
	run grep -c '\.ps1$' "${JB_NS_LOG}"
	assert_output 0
}

@test 'from PowerShell, -f keeps the bash resolution' {
	_ns_stub
	local base=https://just-buildit.github.io/just-makeit out="${BATS_TEST_TMPDIR}/handoff"
	_ns_put "${base}/aliases.toml" '[aliases]'
	_ns_put "${base}/tool.ps1" 'Write-Output ps'
	_ns_put "${base}/tool.sh" 'echo "bash ran"'
	: >"${out}"
	JB_PS1_OUT="${out}" run just-runit run -n -f just-makeit:tool
	assert_success
	assert_output --regexp '\.sh$'
	[ ! -s "${out}" ]
}

@test 'from PowerShell, a .ps1 URL is handed back, and -k still checks it' {
	_ns_stub
	local url=https://example.com/t/setup.ps1 out="${BATS_TEST_TMPDIR}/handoff"
	_ns_put "${url}" 'Write-Output hi'
	: >"${out}"
	JB_PS1_OUT="${out}" run just-runit run -n -k sha256:0000 "${url}" x
	assert_failure
	assert_output --partial 'checksum mismatch'
	[ ! -s "${out}" ]
	JB_PS1_OUT="${out}" run just-runit run -n "${url}" x
	assert_success
	run head -2 "${out}"
	assert_output "1
${url}"
}
