<#
.SYNOPSIS
    windows-folders.ps1 against the real registry and real robocopy, in
    whichever PowerShell runs this.

.DESCRIPTION
    CI's windows job runs this twice, with pwsh 7 and with Windows
    PowerShell 5.1 -- setup-system runs the script in 5.1. The bats suite
    (test/windows-folders.bats) shadows the registry and robocopy; this is
    the half only Windows can answer: a REG_EXPAND_SZ written and read back,
    robocopy's /MOVE and its exclusions, and an Offline file left alone.

    Nothing real is touched. The key is a scratch one under
    HKCU:\Software\just-bashit-test (JB_KNOWN_FOLDERS_KEY), the profile a
    temp directory (USERPROFILE, in this process only), OneDrive's policy
    key a scratch one too; all of it is deleted at the end, pass or fail.

    Proven:
      - a OneDrive Documents moves home: local files moved, an Offline
        (online-only) file left where it is and counted, a file whose name
        the local Documents already has left on both sides, the value and
        its {F42EE2D3-...} twin set to %USERPROFILE%\Documents as
        REG_EXPAND_SZ, and the jbx block written into the new profile;
      - a second run reports every folder ok (local);
      - with OneDrive "running" (this process's own name) nothing moves, the
        local profile gets jbx and the redirected one a stub loading it;
      - a KFMSilentOptIn policy blocks the move just the same.

    Every failure throws, so the step fails naming the check.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

$root = Split-Path -Parent $PSScriptRoot
$script = Join-Path $root 'src\just_bashit\windows-folders.ps1'
$id = [guid]::NewGuid().ToString('N')
$work = Join-Path ([IO.Path]::GetTempPath()) "jb-folders-$id"
$testKey = "HKCU:\Software\just-bashit-test\$id"
$key = "$testKey\User Shell Folders"
$policy = "$testKey\Policy"
Write-Information "=== $($PSVersionTable.PSEdition) $($PSVersionTable.PSVersion)"

function Assert-That {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAILED: $Message" }
    Write-Information "ok  $Message"
}

function Initialize-Scratch {
    # A OneDrive Documents (with a profile, a subfolder, an online-only file
    # and a name the local Documents already has) and a local Desktop.
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
    if (Test-Path -LiteralPath $testKey) { Remove-Item -LiteralPath $testKey -Recurse -Force }
    $od = Join-Path $work 'home\OneDrive\Documents'
    New-Item -ItemType Directory -Force -Path (Join-Path $od 'sub'), (Join-Path $od 'WindowsPowerShell'),
    (Join-Path $work 'home\Documents'), (Join-Path $work 'lad\just-bashit') | Out-Null
    Set-Content -LiteralPath (Join-Path $od 'a.txt') -Value 'a'
    Set-Content -LiteralPath (Join-Path $od 'sub\b.txt') -Value 'b'
    Set-Content -LiteralPath (Join-Path $od 'WindowsPowerShell\profile.ps1') -Value 'Set-Alias ll Get-ChildItem'
    Set-Content -LiteralPath (Join-Path $od 'taken.txt') -Value 'onedrive copy'
    Set-Content -LiteralPath (Join-Path $work 'home\Documents\taken.txt') -Value 'local copy'
    $cloud = Join-Path $od 'cloud.txt'
    Set-Content -LiteralPath $cloud -Value 'only in the cloud'
    [IO.File]::SetAttributes($cloud, [IO.File]::GetAttributes($cloud) -bor [IO.FileAttributes]::Offline)
    Set-Content -LiteralPath (Join-Path $work 'lad\just-bashit\jbx-ps.sh') -Value '# driver'
    New-Item -Path $key -Force | Out-Null
    $redirect = '%USERPROFILE%\OneDrive\Documents'
    New-ItemProperty -Path $key -Name 'Personal' -Value $redirect -PropertyType ExpandString | Out-Null
    New-ItemProperty -Path $key -Name '{F42EE2D3-909F-4907-8871-4C22FC0BF756}' -Value $redirect -PropertyType ExpandString | Out-Null
    New-ItemProperty -Path $key -Name 'Desktop' -Value '%USERPROFILE%\Desktop' -PropertyType ExpandString | Out-Null
}

function Invoke-FolderScript {
    # The script as setup-system runs it, as a child process, so its output
    # is exactly what the step relays.
    $exe = (Get-Process -Id $PID).Path
    $out = & $exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script 2>&1
    @($out | ForEach-Object { "$_" })
}

$saved = @{}
foreach ($v in 'USERPROFILE', 'LOCALAPPDATA', 'JB_BASH', 'JB_PS_PROFILE', 'JB_KNOWN_FOLDERS_KEY',
    'JB_ONEDRIVE_PROCESS', 'JB_ONEDRIVE_POLICY_KEY', 'OneDrive', 'OneDriveConsumer', 'OneDriveCommercial') {
    $saved[$v] = [Environment]::GetEnvironmentVariable($v)
}
try {
    $env:USERPROFILE = Join-Path $work 'home'
    $env:LOCALAPPDATA = Join-Path $work 'lad'
    $env:JB_BASH = 'C:\Program Files\Git\bin\bash.exe'
    $env:JB_KNOWN_FOLDERS_KEY = $key
    $env:JB_ONEDRIVE_PROCESS = 'jb-no-such-process'
    $env:JB_ONEDRIVE_POLICY_KEY = $policy
    foreach ($v in 'JB_PS_PROFILE', 'OneDrive', 'OneDriveConsumer', 'OneDriveCommercial') {
        Remove-Item -LiteralPath "Env:$v" -ErrorAction SilentlyContinue
    }
    $od = Join-Path $work 'home\OneDrive\Documents'
    $docs = Join-Path $work 'home\Documents'

    # -- the move ------------------------------------------------------------
    Initialize-Scratch
    $out = Invoke-FolderScript
    $out | ForEach-Object { Write-Information "    | $_" }
    Assert-That ($out -contains 'result: ok (restored Documents; sign out to finish)') 'the run reports Documents restored'
    Assert-That (@($out | Where-Object { $_ -like 'Documents: moved 3 files to *; 1 online-only stayed in*onedrive.com*; 1 not moved*' }).Count -eq 1) 'it counts the moved, the online-only and the name already taken'
    $item = Get-Item -LiteralPath $key
    Assert-That ($item.GetValue('Personal', $null, 'DoNotExpandEnvironmentNames') -eq '%USERPROFILE%\Documents') 'Personal is %USERPROFILE%\Documents'
    Assert-That ("$($item.GetValueKind('Personal'))" -eq 'ExpandString') 'Personal is REG_EXPAND_SZ'
    Assert-That ($item.GetValue('{F42EE2D3-909F-4907-8871-4C22FC0BF756}', $null, 'DoNotExpandEnvironmentNames') -eq '%USERPROFILE%\Documents') 'the second Documents value follows'
    Assert-That (Test-Path -LiteralPath (Join-Path $docs 'sub\b.txt')) 'a subfolder moved'
    Assert-That (-not (Test-Path -LiteralPath (Join-Path $od 'a.txt'))) 'a moved file is gone from OneDrive'
    Assert-That (Test-Path -LiteralPath (Join-Path $od 'cloud.txt')) 'the online-only file stayed on OneDrive'
    Assert-That (-not (Test-Path -LiteralPath (Join-Path $docs 'cloud.txt'))) 'the online-only file was not copied'
    Assert-That ((Get-Content -Raw -LiteralPath (Join-Path $docs 'taken.txt')).Trim() -eq 'local copy') 'the local file of a taken name is untouched'
    Assert-That ((Get-Content -Raw -LiteralPath (Join-Path $od 'taken.txt')).Trim() -eq 'onedrive copy') 'the OneDrive file of a taken name is kept'
    $prof = Get-Content -Raw -LiteralPath (Join-Path $docs 'WindowsPowerShell\profile.ps1')
    Assert-That ($prof -match 'Set-Alias ll Get-ChildItem' -and $prof -match 'function global:jbx') 'the moved profile keeps its line and has jbx'
    Assert-That ((Get-Content -Raw -LiteralPath (Join-Path $docs 'PowerShell\profile.ps1')) -match 'function global:jbx') 'pwsh 7''s profile has jbx'

    # -- idempotent -----------------------------------------------------------
    $out = Invoke-FolderScript
    Assert-That ($out -contains 'Documents: ok (local)' -and $out -contains 'result: ok (local)') 'a second run finds Documents local'

    # -- OneDrive running: the stub -------------------------------------------
    Initialize-Scratch
    $env:JB_ONEDRIVE_PROCESS = (Get-Process -Id $PID).ProcessName
    $out = Invoke-FolderScript
    $out | ForEach-Object { Write-Information "    | $_" }
    Assert-That (@($out | Where-Object { $_ -like 'result: skipped (Documents on OneDrive: OneDrive is running; profile stub written)' }).Count -eq 1) 'with OneDrive running it reports the stub'
    Assert-That ((Get-Item -LiteralPath $key).GetValue('Personal', $null, 'DoNotExpandEnvironmentNames') -eq '%USERPROFILE%\OneDrive\Documents') 'Personal is left on OneDrive'
    Assert-That (Test-Path -LiteralPath (Join-Path $od 'a.txt')) 'nothing moved'
    $stub = Get-Content -Raw -LiteralPath (Join-Path $od 'WindowsPowerShell\profile.ps1')
    Assert-That ($stub -match 'Set-Alias ll Get-ChildItem' -and $stub -match [regex]::Escape(". '$docs\WindowsPowerShell\profile.ps1'")) 'the redirected profile keeps its line and loads the local one'
    Assert-That ((Get-Content -Raw -LiteralPath (Join-Path $docs 'WindowsPowerShell\profile.ps1')) -match 'function global:jbx') 'the local profile has jbx'
    $env:JB_ONEDRIVE_PROCESS = 'jb-no-such-process'

    # -- a KFM policy ---------------------------------------------------------
    Initialize-Scratch
    New-Item -Path $policy -Force | Out-Null
    New-ItemProperty -Path $policy -Name 'KFMSilentOptIn' -Value '00000000-0000-0000-0000-000000000000' -PropertyType String | Out-Null
    $out = Invoke-FolderScript
    Assert-That (@($out | Where-Object { $_ -like 'result: skipped (*the KFMSilentOptIn policy is set*' }).Count -eq 1) 'a KFMSilentOptIn policy blocks the move'
    Assert-That (Test-Path -LiteralPath (Join-Path $od 'a.txt')) 'nothing moved under the policy'
} finally {
    foreach ($v in $saved.Keys) { [Environment]::SetEnvironmentVariable($v, $saved[$v]) }
    if (Test-Path -LiteralPath $testKey) { Remove-Item -LiteralPath $testKey -Recurse -Force }
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
    $parent = 'HKCU:\Software\just-bashit-test'
    if ((Test-Path -LiteralPath $parent) -and -not (Get-ChildItem -LiteralPath $parent)) {
        Remove-Item -LiteralPath $parent -Force
    }
}
