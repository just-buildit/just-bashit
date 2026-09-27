# shellcheck disable=SC2154  # BATS_TEST_TMPDIR, PROJECT_ROOT set by bats/common-setup
# shellcheck disable=SC2016  # PowerShell code in single quotes: $ is for pwsh, not bash
load 'test_helper/common-setup'
_common_setup

# windows-sshd.ps1's text transforms, exercised through Linux pwsh. The rest
# of the script changes a Windows machine and needs one, elevated; these are
# the parts that decide WHAT it writes, and they are pure. Dot-sourcing
# stops at the script's own guard, before anything touches the system.
setup() {
	command -v pwsh >/dev/null 2>&1 || skip "pwsh not installed (setup-system -s pwsh)"
	PS1_FILE="${PROJECT_ROOT}/src/just_bashit/windows-sshd.ps1"
	# Under MSYS (the windows runner) pwsh is a Windows program and cannot
	# open /d/a/... paths; hand it the Windows spelling.
	if command -v cygpath >/dev/null 2>&1; then
		PS1_FILE="$(cygpath -w "${PS1_FILE}")"
	fi
}

_ps() { pwsh -NoProfile -Command ". '${PS1_FILE}'; $1"; }

@test 'windows-sshd: dot-sourcing defines the functions and changes nothing' {
	run _ps "Get-Command Get-KeyLine, Merge-ManagedBlock, Edit-SshdOption | Measure-Object | % Count"
	assert_success
	assert_output "3"
}

@test 'windows-sshd: only key lines survive, an HTML error page does not' {
	run _ps '(Get-KeyLine "ssh-ed25519 AAAA a`r`n<html>404</html>`n# c`nssh-ed25519 AAAA a`necdsa-sha2-nistp256 BBBB`nsk-ssh-ed25519@openssh.com CCCC") -join "|"'
	assert_success
	assert_output "ssh-ed25519 AAAA a|ecdsa-sha2-nistp256 BBBB|sk-ssh-ed25519@openssh.com CCCC"
}

@test 'windows-sshd: the managed block replaces itself and keeps hand-added keys' {
	run _ps '$a = Merge-ManagedBlock -Existing @("ssh-rsa MINE","") -Body @("k1"); (Merge-ManagedBlock -Existing $a -Body @("k2")) -join "|"'
	assert_success
	assert_output "ssh-rsa MINE||# >>> managed by just-bashit windows-sshd.ps1 >>>|k2|# <<< just-bashit <<<"
}

@test 'windows-sshd: refreshing the block is idempotent' {
	run _ps '$a = Merge-ManagedBlock -Existing @() -Body @("k"); $b = Merge-ManagedBlock -Existing $a -Body @("k"); ($a -join "|") -eq ($b -join "|")'
	assert_success
	assert_output "True"
}

@test 'windows-sshd: the stock commented default is rewritten in place' {
	run _ps '(Edit-SshdOption @("#PasswordAuthentication yes","Subsystem sftp x","Match Group administrators") PasswordAuthentication no) -join "|"'
	assert_success
	assert_output "PasswordAuthentication no|Subsystem sftp x|Match Group administrators"
}

@test 'windows-sshd: a live setting wins over a commented one' {
	run _ps '(Edit-SshdOption @("#PasswordAuthentication yes","PasswordAuthentication yes") PasswordAuthentication no) -join "|"'
	assert_success
	assert_output "#PasswordAuthentication yes|PasswordAuthentication no"
}

@test 'windows-sshd: a missing setting goes ABOVE the first Match, not into it' {
	run _ps '(Edit-SshdOption @("Port 22","Match all","PasswordAuthentication yes") PasswordAuthentication no) -join "|"'
	assert_success
	assert_output "Port 22|PasswordAuthentication no|Match all|PasswordAuthentication yes"
}

@test 'windows-sshd: two live settings are refused, not guessed between' {
	run _ps 'Edit-SshdOption @("PasswordAuthentication yes","PasswordAuthentication no") PasswordAuthentication no'
	assert_failure
	assert_output --partial "refusing to guess"
}
