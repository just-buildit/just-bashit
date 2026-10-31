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

# ---------------------------------------------------------------------------
# The jb-sshd-wsl rule and the task that keeps it current (#80). These
# functions change the machine only through cmdlets, so each cmdlet is
# replaced by a stub that records what it was asked to do; a PowerShell
# function shadows a cmdlet of the same name. The adapters are this box's
# real set as Get-NetAdapter -IncludeHidden reported it, trimmed.
# ---------------------------------------------------------------------------
_wsl_stubs() {
	local tmp="${BATS_TEST_TMPDIR}"
	if command -v cygpath >/dev/null 2>&1; then tmp="$(cygpath -w "${tmp}")"; fi
	cat <<-EOF
		\$InformationPreference = 'SilentlyContinue'
		\$env:ProgramData = '${tmp}'
		\$env:SystemRoot = '${tmp}'
		\$global:calls = [System.Collections.Generic.List[string]]::new()
		\$global:rules = @{}
		\$global:tasks = @{}
		\$global:adapters = @(
		    [pscustomobject]@{ Name = 'Wi-Fi'; InterfaceGuid = '{49CABE1F-3F4D-470F-A3BA-55AA87376ACD}' },
		    [pscustomobject]@{ Name = 'vSwitch (WSL (Hyper-V firewall))'; InterfaceGuid = '{368779DA-900F-40BC-88B3-EF8E22D08485}' },
		    [pscustomobject]@{ Name = 'vEthernet (WSL (Hyper-V firewall))'; InterfaceGuid = '{8B2E6D87-C178-428B-985E-0F573BE2496E}' },
		    [pscustomobject]@{ Name = 'vEthernet (Default Switch)'; InterfaceGuid = '{11111111-2222-3333-4444-555555555555}' },
		    [pscustomobject]@{ Name = 'Tailscale'; InterfaceGuid = '{66666666-7777-8888-9999-000000000000}' })
		function Get-NetAdapter { param([switch]\$IncludeHidden) \$global:adapters }
		function Get-NetFirewallRule { param(\$Name) if (\$global:rules.ContainsKey(\$Name)) { [pscustomobject]@{ Name = \$Name } } }
		function Set-NetFirewallRule { param(\$Name, \$Enabled, \$Profile, \$InterfaceAlias, \$RemoteAddress)
		    \$global:calls.Add("set \$Name if=\$(\$InterfaceAlias -join ';') ra=\$(\$RemoteAddress -join ';')") }
		function New-NetFirewallRule { param(\$Name, \$DisplayName, \$Direction, \$Protocol, \$LocalPort, \$Action, \$Profile, \$InterfaceAlias)
		    \$global:rules[\$Name] = \$true; \$global:calls.Add("new \$Name if=\$(\$InterfaceAlias -join ';') port=\$LocalPort") }
		function icacls.exe { \$global:LASTEXITCODE = 0 }
		function New-ScheduledTaskAction { param(\$Execute, \$Argument) [pscustomobject]@{ Execute = \$Execute; Argument = \$Argument } }
		function New-ScheduledTaskTrigger { param([switch]\$AtStartup) [pscustomobject]@{ Kind = 'startup' } }
		function Get-CimClass { param(\$ClassName, \$Namespace) \$ClassName }
		function New-CimInstance { param([switch]\$ClientOnly, \$CimClass) [pscustomobject]@{ Kind = \$CimClass; Subscription = \$null; Enabled = \$false } }
		function New-ScheduledTaskPrincipal { param(\$UserId, \$LogonType, \$RunLevel) [pscustomobject]@{ UserId = \$UserId; RunLevel = \$RunLevel } }
		function New-ScheduledTaskSettingsSet { [pscustomobject]@{} }
		function New-TimeSpan { param(\$Minutes) }
		# The real cmdlet refuses an existing name without -Force; so does this.
		function Register-ScheduledTask { param(\$TaskName, \$TaskPath, \$Action, \$Trigger, \$Principal, \$Settings, [switch]\$Force)
		    \$key = "\$TaskPath\$TaskName"
		    if (\$global:tasks.ContainsKey(\$key) -and -not \$Force) { throw "task \$key already exists" }
		    \$global:tasks[\$key] = [pscustomobject]@{ Action = \$Action; Trigger = \$Trigger; Principal = \$Principal } }
		Set-Content -LiteralPath (Join-Path \$env:ProgramData 'src.ps1') -Value '# the script'
	EOF
}

_psw() { _ps "$(_wsl_stubs); $1"; }

@test "windows-sshd: the WSL rule is scoped to WSL's vEthernet adapter and nothing else" {
	run _psw 'Sync-WslSshdRule | Out-Null; $global:calls -join "|"'
	assert_success
	assert_output "new jb-sshd-wsl if=vEthernet (WSL (Hyper-V firewall)) port=22"
}

@test 'windows-sshd: re-scoping rewrites jb-sshd-wsl, never the tailnet port-22 rule' {
	run _psw '$global:rules["jb-sshd-wsl"] = $true; $global:rules["OpenSSH-Server-In-TCP"] = $true
		Sync-WslSshdRule | Out-Null; $global:calls -join "|"'
	assert_success
	assert_output "set jb-sshd-wsl if=vEthernet (WSL (Hyper-V firewall)) ra="
}

@test 'windows-sshd: with no WSL adapter the rule is left alone' {
	run _psw '$global:adapters = @($global:adapters | ? Name -notlike "vEthernet (WSL*")
		"$(Sync-WslSshdRule) calls=$($global:calls.Count)"'
	assert_success
	assert_output "False calls=0"
}

@test 'windows-sshd: the re-scope task is registered once, and a re-run replaces it' {
	run _psw 'Register-WslRescopeTask -Source (Join-Path $env:ProgramData "src.ps1")
		Register-WslRescopeTask -Source (Join-Path $env:ProgramData "src.ps1")
		$t = $global:tasks["\just-bashit\jb-sshd-wsl-rescope"]
		"tasks=$($global:tasks.Count)"
		"user=$($t.Principal.UserId) level=$($t.Principal.RunLevel)"
		"args=$($t.Action.Argument)"
		"triggers=$(($t.Trigger | % { $_.Kind }) -join ",")"
		"event=$(@($t.Trigger)[1].Subscription)"
		"copied=$(Test-Path (Join-Path $env:ProgramData "just-bashit/windows-sshd.ps1"))"'
	assert_success
	assert_line "tasks=1"
	assert_line "user=S-1-5-18 level=Highest"
	assert_line --regexp '^args=.*-File ".*just-bashit.windows-sshd\.ps1" -RescopeWslRule$'
	assert_line "triggers=startup,MSFT_TaskEventTrigger"
	assert_line --partial "Provider[@Name='Microsoft-Windows-Hyper-V-VmSwitch'] and EventID=9"
	assert_line "copied=True"
}

@test 'windows-sshd: the scope check tells a current rule from a stale one' {
	run _psw '$a = $global:adapters
		"current=$((Test-WslRuleScope "v2.33|IF={8b2e6d87-c178-428b-985e-0f573be2496e}|Name=x|" $a).Current)"
		"stale=$((Test-WslRuleScope "v2.33|IF={82ff2c64-3728-4917-9137-caa0c2c7a04b}|" $a).Current)"
		"vswitch=$((Test-WslRuleScope "v2.33|IF={368779DA-900F-40BC-88B3-EF8E22D08485}|" $a).Current)"
		"noadapter=$((Test-WslRuleScope "v2.33|IF={8B2E6D87-C178-428B-985E-0F573BE2496E}|" @()).Current)"
		"norule=$((Test-WslRuleScope $null $a).Current)"'
	assert_success
	assert_output "current=True
stale=False
vswitch=False
noadapter=False
norule=False"
}

@test 'windows-sshd: the WSL rule is scoped in one place, which setup and the task both call' {
	# Every firewall cmdlet given -InterfaceAlias must sit inside
	# Sync-WslSshdRule; a second copy is the one that drifts.
	ast_q='$ast = [System.Management.Automation.Language.Parser]::ParseFile("'"${PS1_FILE}"'", [ref]$null, [ref]$null)
		$scoped = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and
		    $n.GetCommandName() -match "^(Set|New)-NetFirewallRule$" -and
		    @($n.CommandElements | ? { $_ -is [System.Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -eq "InterfaceAlias" }).Count }, $true))
		$outside = @($scoped | ? { $p = $_.Parent; while ($p -and -not ($p -is [System.Management.Automation.Language.FunctionDefinitionAst])) { $p = $p.Parent }; -not $p -or $p.Name -ne "Sync-WslSshdRule" })
		$callers = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq "Sync-WslSshdRule" }, $true)).Count
		"scoped=$($scoped.Count) outside=$($outside.Count) callers=$callers"'
	run pwsh -NoProfile -Command "${ast_q}"
	assert_success
	assert_output "scoped=2 outside=0 callers=2"
}
