<#
.SYNOPSIS
    get-jb.ps1 end to end on real Windows, in whichever PowerShell runs this.

.DESCRIPTION
    CI's windows job runs this twice, with pwsh 7 and with Windows
    PowerShell 5.1 (#172). test/get-jb-ps1.bats covers the same ground on
    Linux with bash standing in for Git Bash; this is the half only Windows
    can answer -- Git for Windows' bash.exe found for real, the MSYS
    runtime between PowerShell and bash, and each edition's own native
    argument passing and environment handling.

    It installs through `iex`, the way a user does, with get-jb.sh taken
    from this checkout (JB_GET_JB_URL) and the profile written to a temp
    file (JB_PS_PROFILE), then proves:

      - jbx runs a library function, and its exit status reaches
        $LASTEXITCODE, zero and non-zero;
      - a new session that loads the profile has jbx;
      - with HOME pointed at a stub jbx, every argument arrives as typed
        (spaces, `*`, quotes, empty) and no JB_PS_ variable outlives a call.

    Every failure throws, so the step fails naming the check.
#>
# `irm | iex` is the install this test exists to prove, so the analyzer's
# advice against Invoke-Expression is declined here, by name, for this file.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingInvokeExpression', '',
    Justification = 'iex is the user-facing install path under test')]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

$root = Split-Path -Parent $PSScriptRoot
$script = Join-Path $root 'src\just_bashit\get-jb.ps1'
$work = Join-Path ([IO.Path]::GetTempPath()) ("jb-getjb-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
$env:JB_PS_PROFILE = Join-Path $work 'profile.ps1'
$env:JB_GET_JB_URL = 'file:///' + ((Join-Path $root 'src\just_bashit\get-jb.sh') -replace '\\', '/')
Write-Information "=== $($PSVersionTable.PSEdition) $($PSVersionTable.PSVersion)"

function Assert-That {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAILED: $Message" }
    Write-Information "ok  $Message"
}

Get-Content -Raw -LiteralPath $script | Invoke-Expression
Assert-That ([bool](Get-Command jbx -CommandType Function -ErrorAction SilentlyContinue)) 'iex defined the jbx function'
Assert-That (-not (Get-Command Install-JustBashit -ErrorAction SilentlyContinue)) 'iex left no helper behind'

$out = jbx just-bashit:datetime iso-8601-basic
Assert-That ($LASTEXITCODE -eq 0) "jbx just-bashit:datetime exits 0 (got $LASTEXITCODE)"
Assert-That ("$out" -match '^\d{8}T\d{6}Z$') "jbx just-bashit:datetime prints a timestamp (got '$out')"

# 5.1 turns a redirected native stderr line into an error record, which
# 'Stop' makes terminating; the exit code is the thing under test here.
$ErrorActionPreference = 'Continue'
jbx no-such-command-get-jb-ps1 2>&1 | Out-Null
$ErrorActionPreference = 'Stop'
Assert-That ($LASTEXITCODE -ne 0) "an unresolvable jbx call exits non-zero (got $LASTEXITCODE)"

$exe = (Get-Process -Id $PID).Path
$fresh = & $exe -NoProfile -ExecutionPolicy Bypass -Command ". '$env:JB_PS_PROFILE'; jbx just-bashit:datetime iso-8601-basic; exit `$LASTEXITCODE"
Assert-That ($LASTEXITCODE -eq 0 -and "$fresh" -match '^\d{8}T\d{6}Z$') "a new session that loads the profile runs jbx (got '$fresh')"

# A stub jbx in a fake HOME: the driver puts ~/.local/bin first on PATH, and
# Git Bash takes HOME from the environment.
$bin = Join-Path $work 'home\.local\bin'
New-Item -ItemType Directory -Path $bin | Out-Null
$stub = "#!/usr/bin/env bash`nprintf '[%s]' `"`$@`"; printf ' n=%d\n' `"`$#`"`n" +
    "printf 'leaked=%s\n' `"`$(env | grep -c '^JB_PS_\(ARG\|NAME\)')`"`nexit 5`n"
[IO.File]::WriteAllText((Join-Path $bin 'jbx'), $stub, (New-Object System.Text.UTF8Encoding($false)))
$savedHome = $env:HOME
$env:HOME = Join-Path $work 'home'
try {
    $first = jbx show 'a b' '*' "it's" '"q"' '' 'C:\x y'
    $rc = $LASTEXITCODE
    $second = jbx x
} finally {
    if ($null -eq $savedHome) { Remove-Item Env:HOME } else { $env:HOME = $savedHome }
}
Assert-That ($rc -eq 5) "the stub's exit status reaches `$LASTEXITCODE (got $rc)"
Assert-That ($first[0] -eq '[show][a b][*][it''s]["q"][][C:\x y] n=7') "every argument arrives as typed (got $($first[0]))"
Assert-That ($second[1] -eq 'leaked=0') "no JB_PS_ variable outlives its call (got $($second[1]))"

Remove-Item -Recurse -Force -LiteralPath $work
Write-Information "=== get-jb.ps1 passed on $($PSVersionTable.PSEdition)"
exit 0
