# shellcheck disable=SC2154  # BATS_TEST_TMPDIR, PROJECT_ROOT set by bats/common-setup
# shellcheck disable=SC2016  # shell text in single quotes, expanded where it runs
load 'test_helper/common-setup'
_common_setup
bats_require_minimum_version 1.5.0

# ---------------------------------------------------------------------------
# One TLS decision for every curl call just-bashit ships.
#
# Git for Windows' curl is built on Schannel, which refuses the connection
# when the CA's revocation endpoints cannot be reached (a VPN, a proxy, a
# firewall: "curl: (35) schannel: ... CRYPT_E_NO_REVOCATION_CHECK"), where
# PowerShell's irm soft-fails. So `irm get-jb.ps1 | iex` fetched the script
# and died at its first curl. pkg.sh's _curl_tls_init is the decision:
# --ssl-revoke-best-effort on a Schannel curl, in the _CURL_TLS array, and
# nothing anywhere else. Every call expands that array; every file that runs
# before pkg.sh can be sourced carries a byte-identical copy of the function
# (get-jb.ps1, a one-line equivalent).
#
# These tests hold that without a list of call sites: test_helper/
# curl-calls.awk tokenises every shipped bash file and reports each place
# curl is RUN -- curl, or a path ending in /curl, as a command name: at a
# command's start, in a one-line function body, after VAR=value words, after
# a wrapper and its options (env, sudo, nice, timeout, stdbuf, xargs,
# coproc, _run, exec, command...), inside $(...)/<(...) anywhere including an
# unquoted heredoc body, and as the head of an argv array (`A=(curl -x)`).
# What it cannot resolve fails closed, as a DYNAMIC finding: a command named
# by an expansion that mentions curl (`$CURL`, "${CURL:-curl}",
# "$(command -v curl)"), a variable assigned curl's name or path, and eval
# text naming curl. NOT seen: a command word that is an expansion NOT
# naming curl ("${cmd[@]}" of an array built elsewhere), curl reached
# through a function or alias of another name, a quoted heredoc body (it
# runs nothing), and anything not written in a shipped bash file;
# get-jb.ps1 is read by its own test below.
# ---------------------------------------------------------------------------

SRC="${PROJECT_ROOT}/src/just_bashit"
CALLS_AWK="${PROJECT_ROOT}/test/test_helper/curl-calls.awk"
SCHANNEL='curl 8.21.0 (aarch64-w64-mingw32) libcurl/8.21.0 Schannel zlib/1.3.2 brotli/1.2.0 zstd/1.5.7 libidn2/2.3.8 libpsl/0.21.5 libssh2/1.11.1 WinLDAP'
OPENSSL='curl 8.5.0 (x86_64-pc-linux-gnu) libcurl/8.5.0 OpenSSL/3.0.13 zlib/1.3 brotli/1.1.0 zstd/1.5.5 libidn2/2.3.7 libpsl/0.21.2 (+libidn2/2.3.7) libssh/0.10.6/openssl/zlib nghttp2/1.59.0 librtmp/2.3 OpenLDAP/2.6.7'

# The flag the decision adds. The only spelling these tests accept.
FLAG='--ssl-revoke-best-effort'

# get-jb.ps1's one-line copy of the decision, as it must appear in the bash
# command it hands Git Bash.
PS1_CHECK='o=; read -r v < <(curl -V 2>/dev/null); [[ $v =~ Schannel ]] && o=--ssl-revoke-best-effort;'

# The bash files the package ships: *.sh, and anything with a sh shebang.
_shipped_bash() {
	local f first
	for f in "${SRC}"/*; do
		[[ -f ${f} ]] || continue
		if [[ ${f} == *.sh ]]; then
			printf '%s\n' "${f}"
			continue
		fi
		IFS= read -r first <"${f}" || true
		[[ ${first} =~ ^#!.*(ba)?sh ]] && printf '%s\n' "${f}"
	done
	return 0
}

# A probe asks curl about itself and fetches nothing: `curl -V`, and the
# `curl --retry-all-errors --help` feature probe.
_is_probe() {
	local args="${1#curl}"
	args="${args// 2>\/dev\/null/}"
	args="${args// >\/dev\/null/}"
	args="${args// 2>&1/}"
	[[ ${args} == ' -V' || ${args} == ' --version' || ${args} == *' --help'* ]]
}

# _calls FILE... -- every curl invocation, FILE:LINE:curl ARGS.
_calls() {
	awk -f "${CALLS_AWK}" "$@"
}

# _fn_body FILE -- FILE's `_curl_tls_init() {` ... `}` definition, verbatim.
_fn_body() {
	sed -n '/^_curl_tls_init() {$/,/^}$/p' "${1}"
}

# get-jb.ps1's bash command lines: the single-quoted argument of each
# `-c '...'` on a line that is not a comment, with '' unescaped.
_ps1_bash_commands() {
	local line cmd
	while IFS= read -r line; do
		[[ ${line} =~ ^[[:space:]]*# ]] && continue
		[[ ${line} =~ -c\ \'(([^\']|\'\')*)\' ]] || continue
		cmd="${BASH_REMATCH[1]}"
		printf '%s\n' "${cmd//\'\'/\'}"
	done <"${1}"
}

# A curl that answers -V with BANNER, logs every call's arguments to
# ${CURL_LOG} one call per line, and prints `echo FETCHED <args>` for any
# other call -- so text that sources a fetch runs a line showing its args.
_fake_curl() {
	local banner="${1}" bin="${BATS_TEST_TMPDIR}/fake-curl"
	mkdir -p "${bin}"
	CURL_LOG="${BATS_TEST_TMPDIR}/curl.log"
	: >"${CURL_LOG}"
	{
		echo '#!/usr/bin/env bash'
		printf 'banner=%q log=%q\n' "${banner}" "${CURL_LOG}"
		cat <<-'EOF'
			printf '%s\n' "$*" >>"${log}"
			if [[ ${1-} == -V ]]; then
				printf '%s\n' "${banner}"
				exit 0
			fi
			printf 'echo FETCHED %s\n' "$*"
		EOF
	} >"${bin}/curl"
	chmod +x "${bin}/curl"
	PATH="${bin}:${PATH}"
}

# ---- the scanner ----------------------------------------------------------

@test 'curl-calls.awk finds every call shape, and nothing that is not one' {
	cat >"${BATS_TEST_TMPDIR}/shapes.sh" <<-'SH'
		# curl -sSL https://commented.example
		if ! curl -sSL --fail -o "${d}" "${u}"; then :; fi
		code=$(curl -sSL "${X[@]+"${X[@]}"}" --max-time 5 \
			-o /dev/null --head "${url}" 2>/dev/null)
		echo "$(curl -fsSL "https://in.quotes")"
		env -u MSYS2_ARG_CONV_EXCL -u MSYS_NO_PATHCONV \
			curl -sSL "${a}"
		_run curl -sSL "${b}"
		x | curl -K - "${c}"
		ARGS+=(curl --max-time "${REM}")
		COMMANDS=(curl wget ping)
		command -v curl >/dev/null
		_have curl
		_info "would run: curl -fsSL ${u} | bash"
		printf 'curl -LsSf %s | sh\n' "${u}"
		packages = ["curl", "git"]
		read -r -d '' HELP <<-EOF || true
		  curl -sSL https://in.a.heredoc
		EOF
		case "${c}" in
		curl) : ;;
		esac
		s='multi line
		curl -sSL https://in.a.string'
		curl -V 2>/dev/null
		_bare_fetch() { curl -fsSL https://one.liner; }
		function kw_fn { curl -fsSL https://keyword.fn; }
		nice -n 5 curl -sS https://nice
		sudo -E curl -sS https://sudo
		stdbuf -oL curl -sS https://stdbuf
		xargs -I {} curl -sS {}
		coproc curl -sS https://coproc
		/usr/bin/curl -sS https://by.path
		"${dir}/curl" -sS https://by.var.path
		cat <<-EOF
		  $(curl -sS https://unquoted.heredoc)
		EOF
		cat <<-'EOF'
		  $(curl -sS https://quoted.heredoc.runs.nothing)
		EOF
		$CURL -sS https://dynamic
		"${CURL:-curl}" -sS https://dynamic.default
		eval "curl -sS https://eval"
		CURL=curl
		c="$(command -v curl)"
		"$(command -v curl)" -sS https://dynamic.path
		sudo apt-get install curl
		why="${why:-curl exit ${rc}}"
	SH
	run --separate-stderr _calls "${BATS_TEST_TMPDIR}/shapes.sh"
	assert_success
	local f="${BATS_TEST_TMPDIR}/shapes.sh"
	assert_output "${f}:2:curl -sSL --fail -o \${d} \${u}
${f}:3:curl -sSL \${X[@]+\${X[@]}} --max-time 5 -o /dev/null --head \${url} 2>/dev/null
${f}:5:curl -fsSL https://in.quotes
${f}:7:curl -sSL \${a}
${f}:8:curl -sSL \${b}
${f}:9:curl -K - \${c}
${f}:10:curl --max-time \${REM}
${f}:25:curl -V 2>/dev/null
${f}:26:curl -fsSL https://one.liner
${f}:27:curl -fsSL https://keyword.fn
${f}:28:curl -sS https://nice
${f}:29:curl -sS https://sudo
${f}:30:curl -sS https://stdbuf
${f}:31:curl -sS {}
${f}:32:curl -sS https://coproc
${f}:33:curl -sS https://by.path
${f}:34:curl -sS https://by.var.path
${f}:36:curl -sS https://unquoted.heredoc
${f}:41:DYNAMIC \$CURL
${f}:42:DYNAMIC \${CURL:-curl}
${f}:43:DYNAMIC eval curl -sS https://eval
${f}:44:DYNAMIC CURL=curl
${f}:45:DYNAMIC c=\$(?curl?)
${f}:46:DYNAMIC \$(?curl?)"
}

@test 'curl-calls.awk reports a file it lost its place in' {
	printf '%s\n' 'echo "never closed' 'curl -sSL https://x' >"${BATS_TEST_TMPDIR}/bad.sh"
	run _calls "${BATS_TEST_TMPDIR}/bad.sh"
	assert_output --partial ':EOF:UNBALANCED'
}

# ---- the gate -------------------------------------------------------------

@test 'every shipped curl call carries the shared TLS options' {
	local -a files
	mapfile -t files < <(_shipped_bash)
	[[ ${#files[@]} -gt 10 ]] || fail "found only ${#files[@]} shipped bash files"
	local calls bad="" n=0 c
	calls="$(_calls "${files[@]}")"
	while IFS= read -r c; do
		[[ -n ${c} ]] || continue
		[[ ${c} == *:EOF:UNBALANCED* ]] && bad+="${c}"$'\n' && continue
		# A call the scan cannot resolve is refused, not trusted.
		[[ ${c} == *:DYNAMIC\ * ]] && bad+="${c}"$'\n' && continue
		_is_probe "${c#*:*:}" && continue
		n=$((n + 1))
		[[ ${c} == *'${_CURL_TLS[@]'* ]] || bad+="${c}"$'\n'
	done <<<"${calls}"
	[[ -z ${bad} ]] || fail "curl calls without \"\${_CURL_TLS[@]+\"\${_CURL_TLS[@]}\"}\" (pkg.sh's _curl_tls_init says why):
${bad}"
	# Armed: the scan found the fetches it exists for.
	[[ ${n} -ge 8 ]] || fail "found only ${n} fetching curl calls:
${calls}"
}

@test 'every file with a curl call makes the one decision: pkg.sh, or an identical copy' {
	local canon f bad="" users
	local -a files
	mapfile -t files < <(_shipped_bash)
	canon="$(_fn_body "${SRC}/pkg.sh")"
	[[ ${canon} == *"${FLAG}"* && ${canon} == *Schannel* ]] ||
		fail "pkg.sh's _curl_tls_init lost the Schannel check: ${canon}"
	users="$(_calls "${files[@]}" | grep -F '${_CURL_TLS[@]' | cut -d: -f1 | sort -u)"
	[[ -n ${users} ]] || fail "no file uses _CURL_TLS"
	while IFS= read -r f; do
		# The decision, from pkg.sh, sourced, or from the file's own copy,
		# byte for byte.
		if [[ ${f} != */pkg.sh ]] &&
			! grep -qE '^source "\$\{[A-Z_]+\}/pkg\.sh"$' "${f}"; then
			[[ "$(_fn_body "${f}")" == "${canon}" ]] ||
				bad+="${f##*/}: _curl_tls_init differs from pkg.sh's"$'\n'
		fi
	done <<<"${users}"
	[[ -z ${bad} ]] || fail "${bad}"
}

# _init_before FILE LINE -- does the function holding LINE (or the top-level
# stretch, after the last function to close) call _curl_tls_init before it?
# Functions here open at column 0 (`name() {`) and close on a `}` there.
_init_before() {
	local l=$(($2 - 1)) text
	while ((l > 0)); do
		text="$(sed -n "${l}p" "${1}")"
		[[ ${text} =~ ^[[:space:]]+_curl_tls_init$ ]] && return 0
		[[ ${text} == '}' || ${text} =~ ^[A-Za-z_][A-Za-z0-9_-]*\(\)\ \{ ]] && return 1
		l=$((l - 1))
	done
	return 1
}

# Per call, not per file: a new function that expands _CURL_TLS without
# running the decision first would send nothing on Schannel, silently.
@test 'every curl call runs _curl_tls_init first, in its own function' {
	local -a files
	mapfile -t files < <(_shipped_bash)
	local c file line bad="" n=0
	while IFS= read -r c; do
		[[ ${c} == *'${_CURL_TLS[@]'* ]] || continue
		file="${c%%:*}" line="${c#*:}" line="${line%%:*}"
		n=$((n + 1))
		_init_before "${file}" "${line}" ||
			bad+="${file##*/}:${line}: no _curl_tls_init before it in its function"$'\n'
	done < <(_calls "${files[@]}")
	[[ ${n} -ge 8 ]] || fail "found only ${n} calls using _CURL_TLS"
	[[ -z ${bad} ]] || fail "${bad}"
}

@test 'get-jb.ps1: every curl runs in bash behind the one-line Schannel check' {
	local ps1="${SRC}/get-jb.ps1" line cmds c bad="" n=0
	# A curl named anywhere but inside a `bash -c '...'` would be a call this
	# test cannot read: refused.
	while IFS= read -r line; do
		[[ ${line} =~ ^[[:space:]]*# ]] && continue
		[[ ${line} =~ (^|[^A-Za-z0-9_-])curl([^A-Za-z0-9_-]|$) ]] || continue
		[[ ${line} =~ -c\ \' ]] || bad+="not in a bash -c '...': ${line}"$'\n'
	done <"${ps1}"
	cmds="$(_ps1_bash_commands "${ps1}")"
	while IFS= read -r line; do
		[[ ${line} == *curl* ]] || continue
		[[ ${line} == "${PS1_CHECK}"* ]] ||
			bad+="does not start with the Schannel check: ${line}"$'\n'
		while IFS= read -r c; do
			[[ -n ${c} ]] || continue
			_is_probe "${c#*:*:}" && continue
			n=$((n + 1))
			[[ ${c} == *' $o '* ]] || bad+="a fetch without \$o: ${c}"$'\n'
		done < <(printf '%s\n' "${line}" | awk -v name=get-jb.ps1 -f "${CALLS_AWK}")
	done <<<"${cmds}"
	[[ ${n} -ge 1 ]] || bad+="no curl fetch found in get-jb.ps1"$'\n'
	[[ -z ${bad} ]] || fail "${bad}"
}

# ---- what the decision does -----------------------------------------------

# _decide FILE BANNER -- run FILE's _curl_tls_init twice against a curl whose
# `-V` prints BANNER; print the array, and how many times curl was asked.
_decide() {
	local body
	body="$(_fn_body "${1}")"
	[[ -n ${body} ]] || fail "no _curl_tls_init in ${1}"
	_fake_curl "${2}"
	# Without BASH_ENV: kcov's names BASH_SOURCE in a PS4 that `set -u`
	# then expands at this child's top level (test/runit-list.bats says more).
	env -u BASH_ENV bash -c 'set -euo pipefail; IFS=$'"'"'\n\t'"'"'
		eval "$1"
		_curl_tls_init
		_curl_tls_init
		printf "[%s]" "${_CURL_TLS[@]+"${_CURL_TLS[@]}"}"
		printf " asked=%s\n" "$(wc -l <"$2" | tr -d " ")"' _ "${body}" "${CURL_LOG}"
}

@test '_curl_tls_init: a Schannel curl gets --ssl-revoke-best-effort, once, in every copy' {
	local f
	for f in pkg.sh just-runit setup-system.sh get-jb.sh; do
		run _decide "${SRC}/${f}" "${SCHANNEL}"
		assert_success
		assert_output "[${FLAG}] asked=1"
	done
}

@test '_curl_tls_init: an OpenSSL curl, or none, gets nothing' {
	local f
	for f in pkg.sh just-runit setup-system.sh get-jb.sh; do
		run _decide "${SRC}/${f}" "${OPENSSL}"
		assert_success
		assert_output "[] asked=1"
	done
	# No curl at all: nothing, and no failure under set -e.
	run env -u BASH_ENV PATH="$(_bin_without curl)" bash -c 'set -euo pipefail
		eval "$1"; _curl_tls_init; printf "[%s]\n" "${_CURL_TLS[@]+"${_CURL_TLS[@]}"}"' \
		_ "$(_fn_body "${SRC}/pkg.sh")"
	assert_success
	assert_output "[]"
}

@test '_curl_tls_init appends: the --insecure of --no-verify survives it' {
	_fake_curl "${SCHANNEL}"
	run bash -c 'eval "$1"; _CURL_TLS=(--insecure); _curl_tls_init
		printf "[%s]" "${_CURL_TLS[@]}"' _ "$(_fn_body "${SRC}/pkg.sh")"
	assert_success
	assert_output "[--insecure][${FLAG}]"
}

@test 'get-jb.ps1: its bash command passes the flag to a Schannel curl only' {
	local cmd
	cmd="$(_ps1_bash_commands "${SRC}/get-jb.ps1" | grep -F 'JB_GET_JB_URL')"
	[[ -n ${cmd} ]] || fail "no bash command fetching JB_GET_JB_URL in get-jb.ps1"
	_fake_curl "${SCHANNEL}"
	JB_GET_JB_URL=https://example.test/get-jb.sh run bash -c "${cmd}"
	assert_success
	assert_output "FETCHED -fsSL ${FLAG} https://example.test/get-jb.sh"
	_fake_curl "${OPENSSL}"
	JB_GET_JB_URL=https://example.test/get-jb.sh run bash -c "${cmd}"
	assert_success
	assert_output "FETCHED -fsSL https://example.test/get-jb.sh"
}

# ---- end to end -------------------------------------------------------------

# Every logged call but the probes.
_fetches() {
	grep -v -e '--help' -e '^-V$' "${CURL_LOG}"
}

_logging_fixture_curl() {
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
	echo 'echo "args:$*"' >"${fx}/tool.sh"
}

@test 'jbx on a Schannel curl: every fetch is best-effort on revocation' {
	_logging_fixture_curl
	JB_CURL_BANNER="${SCHANNEL}" run --separate-stderr just-runit https://example.test/tool.sh
	assert_success
	assert_output 'args:'
	run _fetches
	assert_output --partial "${FLAG}"
	while IFS= read -r call; do
		[[ ${call} == *"${FLAG}"* ]] || fail "a fetch without ${FLAG}: ${call}"
	done < <(_fetches)
}

@test 'jbx on an OpenSSL curl: no fetch is given the flag' {
	_logging_fixture_curl
	JB_CURL_BANNER="${OPENSSL}" run --separate-stderr just-runit https://example.test/tool.sh
	assert_success
	assert_output 'args:'
	run grep -c -- "${FLAG}" "${CURL_LOG}"
	assert_output 0
}

@test 'get-jb.sh on a Schannel curl: both fetches carry the flag, and nothing leaks' {
	local home="${BATS_TEST_TMPDIR}/home" stub="${BATS_TEST_TMPDIR}/stub"
	mkdir -p "${home}" "${stub}"
	# uv is already there, so get-jb.sh runs no jbx after installing it.
	printf '#!/usr/bin/env bash\necho "uv 0.0.0"\n' >"${stub}/uv"
	chmod +x "${stub}/uv"
	_logging_fixture_curl
	printf '#!/usr/bin/env bash\n_VERSION="9.9.9"\n' >"${BATS_TEST_TMPDIR}/fixtures/just-runit"
	PATH="${stub}:${PATH}" HOME="${home}" JB_CURL_BANNER="${SCHANNEL}" \
		run bash -c '. "$1"
		declare -F _curl_tls_init && echo LEAKED-FN
		[[ -n ${_CURL_TLS+x}${_CURL_TLS_SET+x} ]] && echo LEAKED-VAR
		true' _ "${SRC}/get-jb.sh"
	assert_success
	refute_output --partial LEAKED
	run _fetches
	assert_line --partial 'jbs/just-runit'
	assert_line --partial 'jbs/jbx-shell.sh'
	while IFS= read -r call; do
		[[ ${call} == *"${FLAG}"* ]] || fail "a fetch without ${FLAG}: ${call}"
	done < <(_fetches)
}
