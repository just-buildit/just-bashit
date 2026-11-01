# shellcheck disable=SC2154  # BATS_TEST_TMPDIR, PROJECT_ROOT set by bats/common-setup
# shellcheck disable=SC2016  # PowerShell code in single quotes: $ is for pwsh, not bash
load 'test_helper/common-setup'
_common_setup

# windows-folders.ps1, the folders step's work (#204), through pwsh on every
# runner that has it. The registry and robocopy are each one function, so
# here both are shadowed: the registry by a hashtable, robocopy by a move of
# the files it would move. Everything else -- which folders count as
# OneDrive, what moves, what the key ends up holding, and the profile
# writes, which are get-jb.ps1's own -- runs for real against scratch
# folders. test/windows-folders.windows.ps1 is the other half: CI's windows
# job runs it with the real registry (a scratch HKCU key) and real robocopy,
# in both PowerShell editions.
setup() {
	command -v pwsh >/dev/null 2>&1 || skip "pwsh not installed (setup-system -s pwsh)"
	PS1_FILE="${PROJECT_ROOT}/src/just_bashit/windows-folders.ps1"
	TMP="${BATS_TEST_TMPDIR}"
	if command -v cygpath >/dev/null 2>&1; then
		PS1_FILE="$(cygpath -w "${PS1_FILE}")"
		TMP="$(cygpath -w "${TMP}")"
	fi
	HOME_DIR="${BATS_TEST_TMPDIR}/home"
	OD="${HOME_DIR}/OneDrive"
	mkdir -p "${OD}/Documents/sub" "${OD}/Pictures" "${BATS_TEST_TMPDIR}/lad/just-bashit"
	echo a >"${OD}/Documents/a.txt"
	echo b >"${OD}/Documents/sub/b.txt"
	echo p >"${OD}/Pictures/p.png"
	# get-jb.ps1 has installed jbx for PowerShell here: the driver exists.
	: >"${BATS_TEST_TMPDIR}/lad/just-bashit/jbx-ps.sh"
	# The stand-ins. Every flow test goes through them, so none can reach
	# the real registry, even on the Windows runner; the key named is a
	# scratch one besides, should a shadow ever stop shadowing.
	cat >"${BATS_TEST_TMPDIR}/prelude.ps1" <<-EOF
		\$InformationPreference = 'SilentlyContinue'
		\$env:USERPROFILE = '${TMP}/home'
		\$env:LOCALAPPDATA = '${TMP}/lad'
		\$env:JB_BASH = 'C:\\Program Files\\Git\\bin\\bash.exe'
		\$env:JB_KNOWN_FOLDERS_KEY = 'HKCU:\\Software\\just-bashit-test\\bats-absent'
		\$env:JB_ONEDRIVE_PROCESS = 'jb-no-such-process'
		\$env:JB_ONEDRIVE_POLICY_KEY = 'HKCU:\\Software\\just-bashit-test\\bats-absent-policy'
		foreach (\$v in 'JB_PS_PROFILE', 'OneDrive', 'OneDriveConsumer', 'OneDriveCommercial') {
		    Remove-Item -LiteralPath "Env:\$v" -ErrorAction SilentlyContinue
		}
		\$global:reg = @{}
		\$global:writes = New-Object System.Collections.Generic.List[string]
		\$global:robo = 0
		function Get-JbShellFolder { param(\$Key) \$h = @{}; foreach (\$k in \$global:reg.Keys) { \$h[\$k] = \$global:reg[\$k] }; \$h }
		function Write-JbShellFolder { param(\$Key, \$Name, \$Data) \$global:reg[\$Name] = \$Data; \$global:writes.Add("\$Name=\$Data") }
		function Move-JbFolderContent { param(\$Source, \$Destination, \$Exclude)
		    if (\$global:robo -ge 8) { return \$global:robo }
		    foreach (\$f in @(Get-ChildItem -LiteralPath \$Source -Recurse -File -Force)) {
		        \$to = Join-Path \$Destination \$f.FullName.Substring(\$Source.Length).TrimStart('\\', '/')
		        New-Item -ItemType Directory -Force -Path (Split-Path -Parent \$to) | Out-Null
		        Move-Item -LiteralPath \$f.FullName -Destination \$to
		    }
		    \$global:robo }
	EOF
	PRELUDE="${TMP}/prelude.ps1"
}

# Windows' pwsh ends lines CRLF; dropped so expected output compares the
# same on every runner. The exit status is pwsh's.
_ps() {
	local out rc=0
	out="$(pwsh -NoProfile -Command ". '${PS1_FILE}'; . '${PRELUDE}'; $1" 2>&1)" || rc=$?
	printf '%s\n' "${out//$'\r'/}"
	return "${rc}"
}

# The redirect KFM leaves: Documents (with the second value Windows keeps
# for it) and Pictures on OneDrive, Desktop already local.
_kfm='$global:reg["Personal"] = "%USERPROFILE%/OneDrive/Documents"
	$global:reg["{F42EE2D3-909F-4907-8871-4C22FC0BF756}"] = "%USERPROFILE%/OneDrive/Documents"
	$global:reg["My Pictures"] = "%USERPROFILE%/OneDrive/Pictures"
	$global:reg["Desktop"] = "%USERPROFILE%\Desktop"'

@test 'windows-folders: dot-sourcing defines the functions and changes nothing' {
	run _ps 'Get-Command Invoke-JbKnownFolderRestore, Test-JbOneDrivePath, Write-JbProfile | Measure-Object | % Count; $global:writes.Count'
	assert_success
	assert_output "3
0"
}

@test 'windows-folders: a OneDrive folder is recognised by name and by its root' {
	run _ps '$env:OneDriveCommercial = "D:\Cloud"
		@("C:\Users\me\OneDrive\Documents", "C:\Users\me\OneDrive - Contoso Ltd\Pictures",
		  "D:\Cloud\Desktop", "C:\Users\me\Documents", "C:\Users\me\OneDriveBackup\Music",
		  "D:\CloudNine\Videos") | % { Test-JbOneDrivePath $_ }'
	assert_success
	assert_output "True
True
True
False
False
False"
}

# Get-JbProfilePath grew -Documents for this step; JB_PS_PROFILE still
# decides without it, and does not with it.
@test 'windows-folders: -Documents names both editions there, whatever JB_PS_PROFILE says' {
	run _ps '$env:JB_PS_PROFILE = "/x/p.ps1"; (Get-JbProfilePath) -join "|"; (Get-JbProfilePath -Documents "/d" | % { $_ -replace "\\", "/" }) -join "|"'
	assert_success
	assert_output "/x/p.ps1
/d/WindowsPowerShell/profile.ps1|/d/PowerShell/profile.ps1"
}

@test 'windows-folders: nothing on OneDrive is ok (local) and writes nothing' {
	run _ps '$global:reg["Personal"] = "%USERPROFILE%\Documents"; Invoke-JbKnownFolderRestore; "writes=$($global:writes.Count)"'
	assert_success
	assert_line "Documents: ok (local)"
	assert_line "Desktop: ok (not redirected)"
	assert_line "result: ok (local)"
	assert_line "writes=0"
}

@test 'windows-folders: the folders move home, every value naming them follows, and jbx lands in the new profile' {
	mkdir -p "${HOME_DIR}/Documents/WindowsPowerShell"
	echo 'Set-Alias ll Get-ChildItem' >"${HOME_DIR}/Documents/WindowsPowerShell/profile.ps1"
	run _ps "${_kfm}"'
		Invoke-JbKnownFolderRestore
		$global:writes -join "|"'
	assert_success
	assert_line --regexp "^Documents: moved 2 files to .*home.Documents$"
	assert_line --regexp "^Pictures: moved 1 files to .*home.Pictures$"
	assert_line "Desktop: ok (local)"
	assert_line --partial "sign out and back in"
	assert_line "result: ok (restored Documents, Pictures; sign out to finish)"
	assert_line 'Personal=%USERPROFILE%\Documents|{F42EE2D3-909F-4907-8871-4C22FC0BF756}=%USERPROFILE%\Documents|My Pictures=%USERPROFILE%\Pictures'
	assert [ -f "${HOME_DIR}/Documents/a.txt" ]
	assert [ -f "${HOME_DIR}/Documents/sub/b.txt" ]
	assert [ -f "${HOME_DIR}/Pictures/p.png" ]
	assert [ ! -e "${OD}/Documents/a.txt" ]
	# The user's own line is kept; the block is get-jb.ps1's, in both editions.
	run cat "${HOME_DIR}/Documents/WindowsPowerShell/profile.ps1"
	assert_line 'Set-Alias ll Get-ChildItem'
	assert_line '# >>> just-bashit get-jb.ps1 >>>'
	assert_line --partial "function global:jbx {"
	run grep -c 'function global:jbx {' "${HOME_DIR}/Documents/PowerShell/profile.ps1"
	assert_output "1"
}

@test 'windows-folders: a second run finds every folder local and changes nothing' {
	run _ps "${_kfm}"'
		Invoke-JbKnownFolderRestore | Out-Null
		$global:writes.Clear()
		Invoke-JbKnownFolderRestore
		"writes=$($global:writes.Count)"'
	assert_success
	assert_line "Documents: ok (local)"
	assert_line "Pictures: ok (local)"
	assert_line "result: ok (local)"
	assert_line "writes=0"
}

@test 'windows-folders: a dry run moves nothing and writes nothing' {
	run _ps "${_kfm}"'
		Invoke-JbKnownFolderRestore -DryRun
		"writes=$($global:writes.Count)"'
	assert_success
	assert_line --partial "Documents: would move 2 files from"
	assert_line "result: ok (would restore Documents, Pictures) (dry run)"
	assert_line "writes=0"
	assert [ -f "${OD}/Documents/a.txt" ]
	assert [ ! -e "${HOME_DIR}/Documents" ]
}

@test 'windows-folders: a robocopy failure leaves that folder pointing at OneDrive' {
	run _ps "${_kfm}"'
		$global:robo = 16
		Invoke-JbKnownFolderRestore
		"writes=$($global:writes.Count)"'
	assert_success
	assert_line --partial "Documents: failed (robocopy exit 16)"
	assert_line --partial "result: failed (Documents, Pictures still on OneDrive"
	assert_line "writes=0"
}

# The fallback (the owner's, on the issue): OneDrive would redirect them
# again, so nothing moves and nothing is uninstalled; PowerShell is fixed by
# a stub in each redirected profile that loads the local one.
@test 'windows-folders: with OneDrive running nothing moves, and each redirected profile loads its local twin' {
	mkdir -p "${OD}/Documents/WindowsPowerShell"
	printf '%s\n' 'Set-Alias ll Get-ChildItem' >"${OD}/Documents/WindowsPowerShell/profile.ps1"
	run _ps "${_kfm}"'
		$env:JB_ONEDRIVE_PROCESS = (Get-Process -Id $PID).ProcessName
		Invoke-JbKnownFolderRestore
		"writes=$($global:writes.Count)"'
	assert_success
	assert_line --partial "Documents: left on OneDrive"
	assert_line --partial "not moved: OneDrive is running"
	assert_line "result: skipped (Documents, Pictures on OneDrive: OneDrive is running; profile stub written)"
	assert_line "writes=0"
	assert [ -f "${OD}/Documents/a.txt" ]
	run cat "${HOME_DIR}/Documents/WindowsPowerShell/profile.ps1"
	assert_line --partial "function global:jbx {"
	run cat "${OD}/Documents/WindowsPowerShell/profile.ps1"
	assert_line 'Set-Alias ll Get-ChildItem'
	assert_line --regexp "\. '.*home.Documents.WindowsPowerShell.profile\.ps1'"
	refute_line --partial "function global:jbx {"
	run cat "${OD}/Documents/PowerShell/profile.ps1"
	assert_line --regexp "home.Documents.PowerShell.profile"
}

@test 'windows-folders: a Known Folder Move policy blocks the move; a zero KFMBlockOptOut does not' {
	run _ps "${_kfm}"'
		function Get-ItemProperty { [pscustomobject]@{ KFMSilentOptIn = "1111-tenant"; KFMBlockOptOut = 0 } }
		Invoke-JbKnownFolderRestore'
	assert_success
	assert_line --partial "result: skipped (Documents, Pictures on OneDrive: the KFMSilentOptIn policy is set;"
	refute_output --partial "KFMBlockOptOut"
}

@test 'windows-folders: a redirected profile it cannot read is never written' {
	mkdir -p "${OD}/Documents/WindowsPowerShell"
	echo 'keep me' >"${OD}/Documents/WindowsPowerShell/profile.ps1"
	run _ps "${_kfm}"'
		$env:JB_ONEDRIVE_PROCESS = (Get-Process -Id $PID).ProcessName
		function Read-JbProfile { param($Path) throw (New-Object IO.IOException("cloud", -2147024534)) }
		Invoke-JbKnownFolderRestore'
	assert_success
	assert_line --partial "result: skipped (Documents, Pictures on OneDrive: OneDrive is running; profile stub written; skipped"
	run cat "${OD}/Documents/WindowsPowerShell/profile.ps1"
	assert_output "keep me"
}

@test 'windows-folders: without jbx installed for PowerShell no profile is touched' {
	rm "${BATS_TEST_TMPDIR}/lad/just-bashit/jbx-ps.sh"
	run _ps "${_kfm}"'
		$env:JB_ONEDRIVE_PROCESS = (Get-Process -Id $PID).ProcessName
		Invoke-JbKnownFolderRestore'
	assert_success
	assert_line --partial "no jbx profile block to keep)"
	assert [ ! -e "${HOME_DIR}/Documents" ]
	assert [ ! -e "${OD}/Documents/PowerShell" ]
}
