# shellcheck disable=SC2154  # BATS_TEST_TMPDIR, PROJECT_ROOT set by bats/common-setup
# shellcheck disable=SC2016  # PowerShell code in single quotes: $ is for pwsh, not bash
load 'test_helper/common-setup'
_common_setup

# get-jb.ps1, the PowerShell front door (#172). Two halves:
#
#   - its pure parts (the bash search, the profile splice, the winget
#     flags), dot-sourced, on every runner with pwsh;
#   - the whole install end to end through `iex`, the way a user runs it,
#     with a stub get-jb.sh and bash itself standing in for Git Bash. Linux
#     and macOS only: there, a POSIX bash is a fair stand-in for Git
#     Bash's, and nothing touches a real profile. CI's windows job runs
#     the real thing from pwsh against Git for Windows.
setup() {
	command -v pwsh >/dev/null 2>&1 || skip "pwsh not installed (setup-system -s pwsh)"
	PS1_FILE="${PROJECT_ROOT}/src/just_bashit/get-jb.ps1"
	TMP="${BATS_TEST_TMPDIR}"
	if command -v cygpath >/dev/null 2>&1; then
		PS1_FILE="$(cygpath -w "${PS1_FILE}")"
		TMP="$(cygpath -w "${TMP}")"
	fi
}

_ps() {
	local out rc=0
	out="$(pwsh -NoProfile -Command ". '${PS1_FILE}'; $1" 2>&1)" || rc=$?
	printf '%s\n' "${out//$'\r'/}"
	return "${rc}"
}

_posix_only() {
	if command -v cygpath >/dev/null 2>&1; then
		skip "end to end runs from pwsh in CI's windows job, against Git Bash"
	fi
}

@test 'get-jb.ps1: dot-sourcing defines the functions and installs nothing' {
	run _ps 'Get-Command Find-GitBash, Merge-JbProfileBlock, Get-JbProfileBlock, Install-JustBashit | Measure-Object | % Count'
	assert_success
	assert_output "4"
}

# The flags are a peer of pkg.sh's: get-jb.ps1 is fetched alone and
# cannot source that file. One list, read from both, must agree.
@test 'get-jb.ps1: winget flags are pkg.sh _WINGET_INSTALL_FLAGS' {
	local bash_flags
	bash_flags="$(sed -n '/^_WINGET_INSTALL_FLAGS=(/,/^)/p' \
		"${PROJECT_ROOT}/src/just_bashit/pkg.sh" |
		sed '1d;$d' | tr -s ' \t\n' ' ' | sed 's/^ //;s/ $//')"
	[ -n "${bash_flags}" ]
	run _ps '(Get-JbWingetFlag) -join " "'
	assert_success
	assert_output "${bash_flags}"
}

@test 'get-jb.ps1: the WSL launcher is never taken for Git Bash' {
	# The launcher EXISTS here, and comes first: only the path refuses it.
	mkdir -p "${BATS_TEST_TMPDIR}/Git/bin" "${BATS_TEST_TMPDIR}/System32"
	: >"${BATS_TEST_TMPDIR}/Git/bin/bash.exe"
	: >"${BATS_TEST_TMPDIR}/System32/bash.exe"
	local git_bash="${TMP}/Git/bin/bash.exe"
	run _ps "Find-GitBash -Candidate '${TMP}/System32/bash.exe', '${TMP}/missing/bash.exe', '${git_bash}'"
	assert_success
	assert_output "${git_bash}"
}

@test 'get-jb.ps1: no candidate found is nothing, not an error' {
	run _ps "Find-GitBash -Candidate '${TMP}/missing/bash.exe' | Measure-Object | % Count"
	assert_success
	assert_output "0"
}

@test 'get-jb.ps1: the profile block keeps the user lines and replaces itself' {
	run _ps '$a = Merge-JbProfileBlock -Existing @("Set-Alias ll ls","") -Body @("v1"); (Merge-JbProfileBlock -Existing $a -Body @("v2")) -join "|"'
	assert_success
	assert_output "Set-Alias ll ls||# >>> just-bashit get-jb.ps1 >>>|v2|# <<< just-bashit get-jb.ps1 <<<"
}

@test 'get-jb.ps1: a profile with two blocks is refused, not guessed at' {
	run _ps '$a = Merge-JbProfileBlock -Existing @() -Body @("x"); Merge-JbProfileBlock -Existing ($a + $a) -Body @("y")'
	assert_failure
	assert_output --partial "Refusing to guess"
}

# A profile jb cannot read is never written (#202): a OneDrive online-only
# file whose provider is gone holds content that may live only in the cloud.
# No runner can make a real placeholder, so Read-JbProfile -- the one read --
# is replaced by one that fails the way the cloud read does: an IOException
# carrying ERROR_CLOUD_FILE_PROVIDER_NOT_RUNNING (0x8007016A).
_unreadable() {
	printf 'keep me\n' >"${BATS_TEST_TMPDIR}/a.ps1"
	run _ps "function Read-JbProfile { throw (New-Object IO.IOException('$1', $2)) }
		\$s = Write-JbProfileAll -Path '${TMP}/a.ps1', '${TMP}/b.ps1' -Body @('x')
		\"skipped=\$s\""
}

@test 'get-jb.ps1: an unreadable OneDrive profile is left alone, the other written' {
	_unreadable 'The cloud provider is not running.' -2147024534
	assert_success
	assert_output --partial "skipped ${TMP}/a.ps1 -- it is an online-only OneDrive file and OneDrive is not running or is uninstalled"
	assert_output --partial "recover it from onedrive.com"
	assert_line "skipped=${TMP}/a.ps1"
	run cat "${BATS_TEST_TMPDIR}/a.ps1"
	assert_output "keep me"
	run grep -c '^# >>> just-bashit get-jb.ps1 >>>' "${BATS_TEST_TMPDIR}/b.ps1"
	assert_output "1"
}

@test 'get-jb.ps1: any other read failure is named generically, file untouched' {
	_unreadable 'boom' -2147024864
	assert_success
	assert_output --partial "skipped ${TMP}/a.ps1 -- it could not be read (boom)"
	refute_output --partial "OneDrive"
	run cat "${BATS_TEST_TMPDIR}/a.ps1"
	assert_output "keep me"
	[ -s "${BATS_TEST_TMPDIR}/b.ps1" ]
}

@test 'get-jb.ps1: the generated block parses and defines jbx and just-runit' {
	run _ps '$b = Get-JbProfileBlock -Bash "C:\Program Files\Git\bin\bash.exe" -Driver "C:\it''s\jbx-ps.sh"; . ([scriptblock]::Create($b -join "`n")); (Get-Command jbx, just-runit | % CommandType) -join ","'
	assert_success
	assert_output "Function,Function"
}

# ---------------------------------------------------------------------------
# End to end. A fake HOME holds what get-jb.sh would install: the stub
# get-jb.sh writes jbx and just-runit stubs that print their arguments one
# per bracket and exit with JBX_RC. HOME is the test's, so the profile and
# driver land under BATS_TEST_TMPDIR and nothing real is touched.
# ---------------------------------------------------------------------------
_e2e_env() {
	E2E_HOME="${BATS_TEST_TMPDIR}/home"
	mkdir -p "${E2E_HOME}"
	WINGET_LOG="${BATS_TEST_TMPDIR}/winget.log"
	cat >"${BATS_TEST_TMPDIR}/winget" <<-EOF
		#!/usr/bin/env bash
		printf '%s\n' "\$*" >>"${WINGET_LOG}"
	EOF
	chmod +x "${BATS_TEST_TMPDIR}/winget"
	cat >"${BATS_TEST_TMPDIR}/get-jb.sh" <<-'EOF'
		mkdir -p "${HOME}/.local/bin"
		for n in jbx just-runit; do
			cat >"${HOME}/.local/bin/${n}" <<-'STUB'
				#!/usr/bin/env bash
				[ "$1" = --version ] && { echo "stub v0"; exit 0; }
				printf '[%s]' "$@"; printf ' n=%d\n' "$#"
				printf 'leaked=%s\n' "$(env | grep -c '^JB_PS_\(ARG\|NAME\)')"
				printf 'caller=%s\n' "${JB_CALLER:-unset}"
				[ "$1" = stdin ] && { IFS= read -r -t 5 l; printf 'stdin=%s\n' "$l"; }
				exit "${JBX_RC:-0}"
			STUB
			chmod +x "${HOME}/.local/bin/${n}"
		done
		echo "stub get-jb.sh ran (JB_REINSTALL=${JB_REINSTALL:-unset})"
	EOF
	PWSH="$(command -v pwsh)"
	BASH_BIN="$(command -v bash)"
}

# Run pwsh with the e2e environment and the PowerShell code $1.
_e2e() {
	local out rc=0
	out="$(env HOME="${E2E_HOME}" JB_PS_PROFILE="${E2E_HOME}/profile.ps1" \
		JB_WINGET="${BATS_TEST_TMPDIR}/winget" \
		JB_GET_JB_URL="file://${BATS_TEST_TMPDIR}/get-jb.sh" \
		"$@" "${PWSH}" -NoProfile -Command "$E2E_CODE" 2>&1)" || rc=$?
	printf '%s\n' "${out}"
	return "${rc}"
}

_iex() {
	printf 'Get-Content -Raw "%s" | Invoke-Expression; ' "${PS1_FILE}"
}

@test 'get-jb.ps1: irm | iex installs, and jbx forwards arguments byte for byte' {
	_posix_only
	_e2e_env
	# shellcheck disable=SC2089,SC2090  # the quotes are PowerShell's
	E2E_CODE="$(_iex)"$(
		cat <<-'EOF'
			jbx show 'a b' '*' 'it''s' '"q"' '' 'C:\x y'; exit $LASTEXITCODE
		EOF
	)
	run _e2e JB_BASH="${BASH_BIN}" JB_REINSTALL=1
	assert_success
	assert_output --partial "stub get-jb.sh ran (JB_REINSTALL=1)"
	assert_output --partial "stub v0"
	assert_output --partial '[show][a b][*][it'"'"'s]["q"][][C:\x y] n=7'
	# Only the forwarding functions are left in the caller's session.
	E2E_CODE="$(_iex)"'(Get-Command Install-JustBashit, Find-GitBash -ErrorAction SilentlyContinue | Measure-Object).Count'
	run _e2e JB_BASH="${BASH_BIN}"
	assert_success
	assert_line "0"
}

# PowerShell parses an unquoted a,b as an array, and [string] joins an array
# with a space: `jbx -r setup-system -s sshd,git` reached bash as
# 'sshd git' (#196). Every comma list jbx takes means a,b.
@test 'get-jb.ps1: jbx forwards an unquoted a,b as one argument a,b' {
	_posix_only
	_e2e_env
	E2E_CODE="$(_iex)"'jbx -s sshd,git -x a,b,c "q,r" one; exit $LASTEXITCODE'
	run _e2e JB_BASH="${BASH_BIN}"
	assert_success
	assert_output --partial '[-s][sshd,git][-x][a,b,c][q,r][one] n=6'
}

@test 'get-jb.ps1: jbx returns its exit code and passes stdin when piped' {
	_posix_only
	_e2e_env
	E2E_CODE="$(_iex)"'"piped" | jbx stdin; "rc=$LASTEXITCODE"; jbx x; exit $LASTEXITCODE'
	run _e2e JB_BASH="${BASH_BIN}" JBX_RC=7
	assert_failure 7
	assert_output --partial "stdin=piped"
	assert_output --partial "rc=7"
}

# Every variable the function sets is put back -- an absent one REMOVED.
# pwsh 7 on Windows keeps a variable "restored" to $null, empty, so the
# third argument of one call was still in the environment of the next.
@test 'get-jb.ps1: no JB_PS_ variable outlives its call' {
	_posix_only
	_e2e_env
	E2E_CODE="$(_iex)"'jbx a b c *> $null; jbx x; (Get-ChildItem Env:JB_PS_ARG*, Env:JB_PS_NAME -ErrorAction SilentlyContinue | Measure-Object).Count'
	run _e2e JB_BASH="${BASH_BIN}"
	assert_success
	assert_output --partial "[x] n=1"
	assert_line "leaked=0"
	assert_line "0"
	refute_line "leaked=2"
}

# The functions tell what they run that PowerShell called it, so
# setup-system's closing advice fits a PowerShell window (#179) -- and, like
# every other variable they set, JB_CALLER is gone once the call returns.
@test 'get-jb.ps1: jbx runs with JB_CALLER=pwsh, which does not outlive the call' {
	_posix_only
	_e2e_env
	E2E_CODE="$(_iex)"'jbx x; "after=$([bool](Test-Path Env:JB_CALLER))"'
	run _e2e JB_BASH="${BASH_BIN}"
	assert_success
	assert_line "caller=pwsh"
	assert_line "after=False"
}

@test 'get-jb.ps1: a re-run keeps one block, and a new session has jbx' {
	_posix_only
	_e2e_env
	printf 'Set-Alias ll Get-ChildItem\n' >"${E2E_HOME}/profile.ps1"
	E2E_CODE="$(_iex)$(_iex)"
	run _e2e JB_BASH="${BASH_BIN}"
	assert_success
	run grep -c '^# >>> just-bashit get-jb.ps1 >>>$' "${E2E_HOME}/profile.ps1"
	assert_output "1"
	run grep -c '^Set-Alias ll Get-ChildItem$' "${E2E_HOME}/profile.ps1"
	assert_output "1"
	E2E_CODE=". '${E2E_HOME}/profile.ps1'; just-runit --version; jbx new session"
	run _e2e
	assert_success
	assert_output --partial "stub v0"
	assert_output --partial "[new][session] n=2"
}

# The whole install with one profile locked against reading (FileShare.None,
# an IOException at the read, as the cloud read raises): the other profile
# and this session's jbx are still set up, and the run then fails naming the
# one it skipped (#202).
@test 'get-jb.ps1: an unreadable profile fails the run last, after the rest' {
	_posix_only
	_e2e_env
	printf 'keep me\n' >"${E2E_HOME}/locked.ps1"
	E2E_CODE='$f = [IO.File]::Open("'"${E2E_HOME}"'/locked.ps1", "Open", "ReadWrite", "None")
		try { '"$(_iex)"' } catch { "THREW: $_" } finally { $f.Dispose() }
		jbx after; "rc=$LASTEXITCODE"'
	run _e2e JB_BASH="${BASH_BIN}" JB_PS_PROFILE="${E2E_HOME}/locked.ps1:${E2E_HOME}/profile.ps1"
	assert_success
	assert_output --partial "skipped ${E2E_HOME}/locked.ps1 -- it could not be read"
	assert_output --partial "ok  jbx function in ${E2E_HOME}/profile.ps1"
	assert_output --partial "THREW: get-jb.ps1: jbx works in this session, but its function was NOT added to ${E2E_HOME}/locked.ps1"
	assert_output --partial "[after] n=1"
	assert_line "rc=0"
	run cat "${E2E_HOME}/locked.ps1"
	assert_output "keep me"
	run grep -c '^# >>> just-bashit get-jb.ps1 >>>$' "${E2E_HOME}/profile.ps1"
	assert_output "1"
}

@test 'get-jb.ps1: no uv means winget installs astral-sh.uv with the shared flags' {
	_posix_only
	_e2e_env
	[ ! -e /usr/bin/uv ] && [ ! -e /bin/uv ] || skip "a uv in /usr/bin cannot be hidden"
	E2E_CODE="$(_iex)"
	run _e2e JB_BASH="${BASH_BIN}" PATH="/usr/bin:/bin"
	assert_success
	run cat "${WINGET_LOG}"
	assert_output "install --id astral-sh.uv --exact --source winget --silent --accept-package-agreements --accept-source-agreements --disable-interactivity"
}

@test 'get-jb.ps1: no Git Bash means winget installs Git.Git, then a clear refusal' {
	_posix_only
	_e2e_env
	E2E_CODE="$(_iex)"
	run _e2e
	assert_failure
	assert_output --partial "winget ran, but Git for Windows bash.exe is still not found"
	run grep -c '^install --id Git.Git ' "${WINGET_LOG}"
	assert_output "1"
}

@test 'get-jb.ps1: a get-jb.sh that installs nothing is a failure, not a pass' {
	_posix_only
	_e2e_env
	: >"${BATS_TEST_TMPDIR}/get-jb.sh"
	E2E_CODE="$(_iex)"
	run _e2e JB_BASH="${BASH_BIN}"
	assert_failure
	assert_output --partial "get-jb.sh did not install ~/.local/bin/jbx"
}

# ---------------------------------------------------------------------------
# A PowerShell script jbx resolves runs in the calling session. Here
# get-jb.sh installs this checkout's REAL just-runit, as jbx and just-runit,
# and a curl stub beside it serves a namespace from fixtures: the driver puts
# ~/.local/bin first on PATH, so the runner finds that curl. Resolution is
# just-runit's (test/namespaces.bats); this is the function's half -- the
# hand-off read, the script run in the session with its arguments as typed,
# and the bash path kept for a name with no .ps1.
# ---------------------------------------------------------------------------
_e2e_real_env() {
	_e2e_env
	FX="${BATS_TEST_TMPDIR}/fx"
	BASE="${FX}/just-buildit.github.io/just-makeit"
	mkdir -p "${BASE}"
	printf '[aliases]\n' >"${BASE}/aliases.toml"
	cat >"${BATS_TEST_TMPDIR}/get-jb.sh" <<-EOF
		mkdir -p "\${HOME}/.local/bin"
		cp '${PROJECT_ROOT}/src/just_bashit/just-runit' "\${HOME}/.local/bin/just-runit"
		cp '${PROJECT_ROOT}/src/just_bashit/just-runit' "\${HOME}/.local/bin/jbx"
		cp '${BATS_TEST_TMPDIR}/curl' "\${HOME}/.local/bin/curl"
	EOF
	cat >"${BATS_TEST_TMPDIR}/curl" <<-EOF
		#!/usr/bin/env bash
		dest="" url="" head=0
		while [[ \$# -gt 0 ]]; do
			case "\${1}" in
			-o) dest="\${2}"; shift 2; continue ;;
			--head) head=1 ;;
			-V) echo "curl stub"; exit 0 ;;
			https://*) url="\${1}" ;;
			esac
			shift
		done
		[[ -n \${url} ]] || exit 0
		f='${FX}/'"\${url#https://}"
		if [[ \${head} -eq 1 ]]; then
			[[ -f \${f} ]] && printf 200 || printf 404
			exit 0
		fi
		[[ -f \${f} ]] || exit 22
		cp "\${f}" "\${dest}"
	EOF
	chmod +x "${BATS_TEST_TMPDIR}/curl"
}

@test 'get-jb.ps1: jbx runs a namespace .ps1 in the session, arguments as typed' {
	_posix_only
	_e2e_real_env
	cat >"${BASE}/tool.ps1" <<-'EOF'
		param([string]$Name, [switch]$Flag)
		$env:JB_T = "ran:${Name}:$Flag"
		$global:JbTArgs = @($args | ForEach-Object {
			if ($_ -is [array]) { '(' + ($_ -join ',') + ')' } else { "[$_]" } })
		$env:PATH = '/jb-t-bin' + [IO.Path]::PathSeparator + $env:PATH
	EOF
	printf 't() { echo "bash ran [$*] caller=${JB_CALLER-}"; }\n' >"${BASE}/shonly.sh"
	E2E_CODE="$(_iex)"$(
		cat <<-'EOF'
			jbx just-makeit:tool -Name 'a b' -Flag x,y '' '*'
			"rc=$LASTEXITCODE"
			"env=$env:JB_T"
			"global=$($global:JbTArgs -join '|')"
			"path=$(($env:PATH -split [IO.Path]::PathSeparator) -contains '/jb-t-bin')"
			"out=$([bool](Test-Path Env:JB_PS1_OUT))"
			jbx just-makeit:shonly t 'q r'
			"rc=$LASTEXITCODE"
		EOF
	)
	run _e2e JB_BASH="${BASH_BIN}"
	assert_success
	assert_line 'rc=0'
	assert_line 'env=ran:a b:True'
	assert_line 'global=(x,y)|[]|[*]'
	assert_line 'path=True'
	assert_line 'out=False'
	assert_line 'bash ran [q r] caller=pwsh'
}

@test 'get-jb.ps1: a .ps1 that throws is one error naming it; exit is refused' {
	_posix_only
	_e2e_real_env
	printf "throw 'boom'\n" >"${BASE}/boom.ps1"
	printf "\$global:JbRan = 1; exit 3\n" >"${BASE}/quits.ps1"
	E2E_CODE="$(_iex)"$(
		cat <<-'EOF'
			try { jbx just-makeit:boom } catch { "caught=$_" }
			"rc=$LASTEXITCODE"
			try { jbx just-makeit:quits } catch { "caught=$_" }
			"rc=$LASTEXITCODE ran=$([bool]$global:JbRan)"
			"alive"
		EOF
	)
	run _e2e JB_BASH="${BASH_BIN}"
	assert_success
	assert_line 'caught=jbx: https://just-buildit.github.io/just-makeit/boom.ps1 failed: boom'
	assert_line 'rc=1'
	assert_line --partial 'caught=jbx: https://just-buildit.github.io/just-makeit/quits.ps1 calls exit'
	assert_line 'rc=1 ran=False'
	assert_line 'alive'
}
