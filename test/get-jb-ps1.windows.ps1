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
      - a profile it cannot read (held open with FileShare.None) is left
        as it was, the other is written, jbx still loads, and the run
        fails naming the skipped one (#202);
      - a new session that loads the profile has jbx;
      - with HOME pointed at a stub jbx, every argument arrives as typed
        (spaces, `*`, quotes, empty) and no JB_PS_ variable outlives a call;
      - with HOME pointed at this checkout's just-runit and a curl stub
        serving a namespace, `jbx NS:NAME` runs NAME.ps1 in this session
        (what it sets persists, its arguments arrive as typed), a NAME with
        only NAME.sh still runs in bash, and a .ps1 that throws or calls
        exit is one error naming it.

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

# The Schannel check get-jb.ps1 runs before its curl, taken from its own
# line, against Git for Windows' real curl: it must name Schannel there, so
# the check must choose --ssl-revoke-best-effort, and that curl must accept
# the flag on a real https fetch. The bats suite drives the same line with a
# fake curl; only here is the curl real.
$gitBash = if ($env:JB_BASH) { $env:JB_BASH } else { Join-Path $env:ProgramFiles 'Git\bin\bash.exe' }
$fetchLine = (Select-String -LiteralPath $script -SimpleMatch 'o=--ssl-revoke-best-effort' |
        Select-Object -First 1).Line
Assert-That ($fetchLine -match "-c '(.*?)\. <\(curl") "get-jb.ps1 runs a Schannel check before its curl (got '$fetchLine')"
$check = $Matches[1]
$probe = & $gitBash -l -c ($check + 'echo $o; read -r v < <(curl -V); echo $v; ' +
    'curl -fsS $o -o /dev/null https://just-buildit.github.io/get-jb.sh && echo FETCHED')
Write-Information "    Git for Windows curl: $($probe[1])"
Assert-That ($probe[1] -match 'Schannel') "Git for Windows' curl is Schannel (got '$($probe[1])')"
Assert-That ($probe[0] -eq '--ssl-revoke-best-effort') "the check chooses --ssl-revoke-best-effort on it (got '$($probe[0])')"
Assert-That ($probe[2] -eq 'FETCHED') "that curl fetches over https with the flag (got '$($probe -join ' | ')')"

$out = jbx just-bashit:datetime iso-8601-basic
Assert-That ($LASTEXITCODE -eq 0) "jbx just-bashit:datetime exits 0 (got $LASTEXITCODE)"
Assert-That ("$out" -match '^\d{8}T\d{6}Z$') "jbx just-bashit:datetime prints a timestamp (got '$out')"

# 5.1 turns a redirected native stderr line into an error record, which
# 'Stop' makes terminating; the exit code is the thing under test here.
$ErrorActionPreference = 'Continue'
jbx no-such-command-get-jb-ps1 2>&1 | Out-Null
$ErrorActionPreference = 'Stop'
Assert-That ($LASTEXITCODE -ne 0) "an unresolvable jbx call exits non-zero (got $LASTEXITCODE)"

# A profile that cannot be read is never written, and does not stop the
# rest (#202). A real OneDrive placeholder cannot be made here; a file held
# open with FileShare.None fails the same read with an IOException.
$locked = Join-Path $work 'locked.ps1'
$other = Join-Path $work 'other.ps1'
Set-Content -LiteralPath $locked -Value 'keep me'
$savedProfile = $env:JB_PS_PROFILE
$env:JB_PS_PROFILE = $locked + [IO.Path]::PathSeparator + $other
Remove-Item Function:\jbx
$threw = ''
$hold = [IO.File]::Open($locked, 'Open', 'ReadWrite', 'None')
try {
    # Not redirected: 5.1 makes a redirected native stderr line an error.
    try { Get-Content -Raw -LiteralPath $script | Invoke-Expression } catch { $threw = "$_" }
} finally {
    $hold.Dispose()
    $env:JB_PS_PROFILE = $savedProfile
}
Assert-That ($threw -like "*NOT added to $locked*") "an unreadable profile fails the run, naming it (got '$threw')"
Assert-That ((Get-Content -Raw -LiteralPath $locked).Trim() -eq 'keep me') 'the unreadable profile is left exactly as it was'
Assert-That ((Get-Content -Raw -LiteralPath $other) -match '# >>> just-bashit get-jb.ps1 >>>') 'the other profile is still written'
Assert-That ([bool](Get-Command jbx -CommandType Function -ErrorAction SilentlyContinue)) 'jbx is still defined in this session'

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
    # An unquoted a,b is a PowerShell array: it must reach bash as a,b (#196).
    $third = jbx -s sshd,git -x a,b,c
} finally {
    if ($null -eq $savedHome) { Remove-Item Env:HOME } else { $env:HOME = $savedHome }
}
Assert-That ($rc -eq 5) "the stub's exit status reaches `$LASTEXITCODE (got $rc)"
Assert-That ($first[0] -eq '[show][a b][*][it''s]["q"][][C:\x y] n=7') "every argument arrives as typed (got $($first[0]))"
Assert-That ($second[1] -eq 'leaked=0') "no JB_PS_ variable outlives its call (got $($second[1]))"
Assert-That ($third[0] -eq '[-s][sshd,git][-x][a,b,c] n=4') "an unquoted a,b arrives as one argument a,b (got $($third[0]))"

# A PowerShell script jbx resolves runs in THIS session: an installer that
# puts a tool on PATH must change the caller, which bash cannot. The jbx
# installed above is the published one, so a second fake HOME holds this
# checkout's just-runit as jbx and just-runit, beside a curl stub that serves
# a namespace from fixtures: jbx fetches over https only, from fixed
# namespace bases, so a stub is how a local site is served.
$home2 = Join-Path $work 'home2'
$bin2 = Join-Path $home2 '.local\bin'
$fx = Join-Path $work 'fx'
$base = Join-Path $fx 'just-buildit.github.io\just-makeit'
New-Item -ItemType Directory -Path $bin2, $base | Out-Null
$lf = New-Object System.Text.UTF8Encoding($false)
function Write-Lf {
    param([string]$Path, [string]$Text)
    [IO.File]::WriteAllText($Path, ($Text -replace "`r`n", "`n"), $lf)
}
$runit = [IO.File]::ReadAllText((Join-Path $root 'src\just_bashit\just-runit'))
foreach ($n in 'jbx', 'just-runit') { Write-Lf (Join-Path $bin2 $n) $runit }
Write-Lf (Join-Path $bin2 'curl') @'
#!/usr/bin/env bash
dest="" url="" head=0
while [[ $# -gt 0 ]]; do
	case "${1}" in
	-o) dest="${2}"; shift 2; continue ;;
	--head) head=1 ;;
	-V) echo "curl stub"; exit 0 ;;
	https://*) url="${1}" ;;
	esac
	shift
done
[[ -n ${url} ]] || exit 0
f="${JB_T_FX}/${url#https://}"
if [[ ${head} -eq 1 ]]; then
	[[ -f ${f} ]] && printf 200 || printf 404
	exit 0
fi
[[ -f ${f} ]] || exit 22
cp "${f}" "${dest}"
'@
Write-Lf (Join-Path $base 'aliases.toml') "[aliases]`n"
Write-Lf (Join-Path $base 'tool.ps1') @'
param([string]$Name, [switch]$Flag)
$env:JB_T = "ran:${Name}:$Flag"
$global:JbTArgs = @($args | ForEach-Object {
        if ($_ -is [array]) { '(' + ($_ -join ',') + ')' } else { "[$_]" } })
$env:PATH = 'C:\jb-t-bin' + [IO.Path]::PathSeparator + $env:PATH
'@
Write-Lf (Join-Path $base 'shonly.sh') 't() { echo "bash ran [$*] caller=${JB_CALLER-}"; }'
Write-Lf (Join-Path $base 'boom.ps1') "throw 'boom'"
Write-Lf (Join-Path $base 'quits.ps1') '$global:JbRan = 1; exit 3'
$savedHome = $env:HOME
$env:HOME = $home2
$env:JB_T_FX = $fx -replace '\\', '/'
$boom = ''
$quits = ''
try {
    jbx just-makeit:tool -Name 'a b' -Flag x,y '' '*'
    $rcTool = $LASTEXITCODE
    $sh = jbx just-makeit:shonly t 'q r'
    $rcSh = $LASTEXITCODE
    try { jbx just-makeit:boom } catch { $boom = "$_" }
    $rcBoom = $LASTEXITCODE
    try { jbx just-makeit:quits } catch { $quits = "$_" }
} finally {
    if ($null -eq $savedHome) { Remove-Item Env:HOME } else { $env:HOME = $savedHome }
    Remove-Item Env:JB_T_FX
}
$ns = 'https://just-buildit.github.io/just-makeit'
Assert-That ($rcTool -eq 0) "a namespace .ps1 run by jbx leaves `$LASTEXITCODE 0 (got $rcTool)"
Assert-That ($env:JB_T -eq 'ran:a b:True') "the .ps1 ran in this session, -Name and -Flag bound (got '$env:JB_T')"
$tArgs = (Get-Variable -Scope Global -Name JbTArgs -ValueOnly) -join '|'
Assert-That ($tArgs -eq '(x,y)|[]|[*]') "the rest arrive as typed, an array an array (got '$tArgs')"
Assert-That (@($env:PATH -split ';') -contains 'C:\jb-t-bin') 'the PATH entry the .ps1 added is on this session''s PATH'
Assert-That (-not (Test-Path Env:JB_PS1_OUT)) 'JB_PS1_OUT does not outlive the call'
Assert-That ($rcSh -eq 0 -and "$sh" -eq 'bash ran [q r] caller=pwsh') "a name with only NAME.sh still runs in bash (got '$sh', rc $rcSh)"
Assert-That ($boom -eq "jbx: $ns/boom.ps1 failed: boom" -and $rcBoom -eq 1) "a .ps1 that throws is one error naming it, rc 1 (got '$boom', rc $rcBoom)"
Assert-That ($quits -like "jbx: $ns/quits.ps1 calls exit*") "a .ps1 that calls exit is refused before it runs (got '$quits')"
Assert-That (-not (Test-Path Variable:global:JbRan)) 'the refused .ps1 did not run'
$env:PATH = (@($env:PATH -split ';') | Where-Object { $_ -ne 'C:\jb-t-bin' }) -join ';'
Remove-Item Env:JB_T

Remove-Item -Recurse -Force -LiteralPath $work
Write-Information "=== get-jb.ps1 passed on $($PSVersionTable.PSEdition)"
exit 0
