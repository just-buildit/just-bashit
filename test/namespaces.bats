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
	# The user's namespaces file lives under XDG_CONFIG_HOME: one per test,
	# so a developer's own `just-runit ns add` never reaches the suite.
	export XDG_CONFIG_HOME="${BATS_TEST_TMPDIR}/config"
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

# ---------------------------------------------------------------------------
# The user's own namespaces: `just-runit ns add NAME BASE`, then NAME:SCRIPT
# resolves exactly as a built-in does -- BASE/aliases.toml, then the probe.
# ---------------------------------------------------------------------------

@test 'ns add, then NAME:SCRIPT runs through a relative alias at the pinned ref' {
	_ns_stub
	local base=https://raw.githubusercontent.com/hunterdsp/examples/abc123/scripts
	run just-runit ns add examples gh:hunterdsp/examples/scripts@abc123
	assert_success
	assert_output "examples -> ${base}/"
	_ns_put "${base}/aliases.toml" '[aliases]
hello = "hello-world.sh"'
	_ns_put "${base}/hello-world.sh" 'echo "Hello World!"'
	run just-runit run -n examples:hello
	assert_success
	assert_output 'Hello World!'
	# The relative value stayed at the pinned ref: main was never asked for.
	run grep -c '/main/' "${JB_NS_LOG}"
	assert_output 0
}

@test 'a user namespace takes an absolute alias as written, and probes the rest' {
	_ns_stub
	just-runit ns add tools https://example.com/tools/
	_ns_put https://example.com/tools/aliases.toml '[aliases]
far = "https://cdn.example.org/far.sh"'
	_ns_put https://cdn.example.org/far.sh 'echo far'
	_ns_put https://example.com/tools/near.sh 'echo near'
	run just-runit run -n tools:far
	assert_success
	assert_output far
	run just-runit run -n tools:near
	assert_success
	assert_output near
}

@test 'a user namespace must serve aliases.toml, as a built-in must' {
	_ns_stub
	just-runit ns add tools https://example.com/tools
	_ns_put https://example.com/tools/near.sh 'echo near'
	run just-runit run -n tools:near
	assert_failure
	assert_output --partial 'could not fetch https://example.com/tools/aliases.toml'
}

@test '-k checks a script from a user namespace' {
	_ns_stub
	just-runit ns add tools https://example.com/tools
	_ns_put https://example.com/tools/aliases.toml '[aliases]'
	_ns_put https://example.com/tools/t.sh 'echo ran'
	run just-runit run -n -k sha256:0000 tools:t
	assert_failure
	assert_output --partial 'checksum mismatch'
	refute_output --partial ran
}

@test 'from PowerShell, a relative [aliases.ps1] value resolves against the base' {
	_ns_stub
	local base=https://example.com/tools out="${BATS_TEST_TMPDIR}/handoff"
	just-runit ns add tools "${base}"
	_ns_put "${base}/aliases.toml" '[aliases]

[aliases.ps1]
setup = "ps/setup.ps1"'
	_ns_put "${base}/ps/setup.ps1" 'Write-Output hi'
	: >"${out}"
	JB_PS1_OUT="${out}" run just-runit run -n tools:setup
	assert_success
	run sed -n 2p "${out}"
	assert_output "${base}/ps/setup.ps1"
}

@test 'ns add resolves every base form to the URL it stores' {
	_ns_stub
	run just-runit ns add root gh:o/r
	assert_output 'root -> https://raw.githubusercontent.com/o/r/main/'
	run just-runit ns add gl https://gitlab.com/acme/tools//ci@v2
	assert_output 'gl -> https://gitlab.com/acme/tools/-/raw/v2/ci/'
	run just-runit ns add cb https://codeberg.org/o/r//lib
	assert_output 'cb -> https://codeberg.org/o/r/raw/HEAD/lib/'
	run cat "${XDG_CONFIG_HOME}/jb/namespaces"
	assert_line 'root https://raw.githubusercontent.com/o/r/main'
	assert_line 'gl https://gitlab.com/acme/tools/-/raw/v2/ci'
}

@test 'ns add refuses a built-in, gh, a bad name, a taken name and a bad base' {
	_ns_stub
	run just-runit ns add just-makeit https://example.com
	assert_failure
	assert_output --partial "'just-makeit' is a built-in namespace"
	run just-runit ns add gh https://example.com
	assert_failure
	assert_output --partial 'GitHub shorthand'
	run just-runit ns add Tools https://example.com
	assert_failure
	assert_output --partial "bad namespace name 'Tools'"
	just-runit ns add tools https://example.com
	run just-runit ns add tools https://example.org
	assert_failure
	assert_output --partial "'tools' is already yours (https://example.com)"
	for base in http://example.com gh:onlyuser ftp://x https://github.com/o/r// tools; do
		run just-runit ns add other "${base}"
		assert_failure
	done
	run grep -c other "${XDG_CONFIG_HOME}/jb/namespaces"
	assert_output 0
}

@test 'a hand-written row cannot redirect a built-in namespace' {
	_ns_stub
	mkdir -p "${XDG_CONFIG_HOME}/jb"
	echo 'just-makeit https://evil.example.com' >"${XDG_CONFIG_HOME}/jb/namespaces"
	local base=https://just-buildit.github.io/just-makeit
	_ns_put "${base}/aliases.toml" '[aliases]'
	_ns_put "${base}/t.sh" 'echo real'
	_ns_put https://evil.example.com/aliases.toml '[aliases]'
	_ns_put https://evil.example.com/t.sh 'echo evil'
	run just-runit run -n just-makeit:t
	assert_output real
	run grep -c evil "${JB_NS_LOG}"
	assert_output 0
}

@test 'ns list, -h and the unknown-namespace error all show the user namespaces' {
	_ns_stub
	just-runit ns add tools https://example.com/tools
	run just-runit ns list
	assert_success
	assert_line --index 0 --partial 'just-buildit'
	assert_line 'tools                 https://example.com/tools/'
	run just-runit run -h
	assert_output --partial 'tools                 https://example.com/tools/   (yours)'
	run just-runit run -n nope:thing
	assert_failure
	assert_output --partial 'known: just-buildit, just-bashit, just-makeit, tools'
}

@test 'ns rm removes one of yours, and only one of yours' {
	_ns_stub
	just-runit ns add tools https://example.com/tools
	just-runit ns add tools2 https://example.com/tools2
	run just-runit ns rm tools
	assert_success
	run just-runit ns list
	refute_line --partial 'example.com/tools/'
	assert_line --partial 'example.com/tools2/'
	run just-runit ns rm tools
	assert_failure
	assert_output --partial "'tools' is not one of your namespaces"
	run just-runit ns rm just-bashit
	assert_failure
	assert_output --partial 'cannot be removed'
}

@test 'jbx takes no subcommand: jbx ns is a SPEC, never the ns command' {
	_ns_stub
	ln -s "$(command -v just-runit)" "${BATS_TEST_TMPDIR}/jbx"
	_ns_put https://just-buildit.github.io/aliases.toml '[aliases]'
	# No -n: an option before `ns` would hide it from the dispatcher, and the
	# test would pass even with a jbx that took subcommands.
	XDG_CACHE_HOME="${BATS_TEST_TMPDIR}/cache" run "${BATS_TEST_TMPDIR}/jbx" ns list
	assert_failure
	assert_output --partial "cannot resolve 'ns'"
	[ ! -e "${XDG_CONFIG_HOME}/jb/namespaces" ]
}
