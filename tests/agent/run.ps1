# Tests for agent/xrrfix_agent.ps1, agent/setup_agent.ps1, agent/uninstall_agent.ps1 (Windows PowerShell 5.1).
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\agent\run.ps1 [-Filter 'AGT-03*'] [-KeepTemp] [-ShowOutput]
# Test names start with the requirement IDs from specs/system/agent.md (see COVERAGE.md).
# Isolation: everything lives in a fresh temp root (RUNNER_TEMP or %TEMP%). Every child gets LOCALAPPDATA=<root>\localappdata,
# XRRFIX_HOME=<sandbox>\xrrfix (never <LOCALAPPDATA>\xrrfix for setup/uninstall -> no scheduled task is touched),
# XRRFIX_API=http://127.0.0.1:<port>/latest.json (fixtures\fake_github.py), XRRFIX_BLOCK_PROCS=<fake process>, XRRFIX_NO_NOTIFY=1.
# Requires: git, python (stdlib only) on PATH.
param(
    [string]$Filter = '*',
    [switch]$KeepTemp,
    [switch]$ShowOutput
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $script:RepoRoot 'tests\lib\assert.ps1')
. (Join-Path $PSScriptRoot 'fixtures.ps1')
$script:Verbose = [bool]$ShowOutput

$oldOutEnc = $null
try { $oldOutEnc = [Console]::OutputEncoding; [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false) } catch { }

# ---- expected failures: spec [auto] requirement that the code does not meet (counted separately, does not fail the run)
$script:XF = @{ Fail = 0; Pass = 0; Names = @() }
function Test-CaseXF([string]$Name, [string]$Why, [scriptblock]$Body) {
    if ($Name -notlike $script:XT.Filter) { $script:XT.Skip++; return }
    $script:CurBody = $Body
    try {
        Reset-Www
        & $script:CurBody
        $script:XF.Pass++
        Write-Host ("XPASS {0}  (expected to fail: {1}) - remove the EXPECTED-FAIL mark" -f $Name, $Why) -ForegroundColor Yellow
    } catch {
        $script:XF.Fail++
        $script:XF.Names += "$Name ($Why)"
        Write-Host ("XFAIL {0}: {1}" -f $Name, ($_.Exception.Message -split "`n")[0]) -ForegroundColor DarkYellow
    }
}
# Test-Case wrapper: resets the fake GitHub server state before each case.
function TC([string]$Name, [scriptblock]$Body) {
    $script:CurBody = $Body
    Test-Case $Name { Reset-Www; & $script:CurBody }
}

# ---- snapshot of the real state that must stay untouched
$script:RealLad = $env:LOCALAPPDATA
$script:RealXrr = Join-Path $script:RealLad 'xrrfix'
function Get-RealSnapshot {
    $s = 'absent'
    if (Test-Path -LiteralPath $script:RealXrr) {
        $s = (@(Get-ChildItem -LiteralPath $script:RealXrr -Recurse -Force | ForEach-Object { '{0}|{1}|{2}' -f $_.FullName, $_.Length, $_.LastWriteTimeUtc.Ticks }) -join "`n")
    }
    return $s + "`nTASK:" + (Get-TaskSnapshot)
}
$realBefore = Get-RealSnapshot

Initialize-Tests -Filter $Filter
$script:Root = New-TestRoot 'xrrfix_agent'
$script:Root = (Get-Item -LiteralPath $script:Root).FullName.TrimEnd('\')
$script:Lad = Join-Path $script:Root 'localappdata'
$script:Www = Join-Path $script:Root 'www'
New-Item -ItemType Directory -Path $script:Lad, $script:Www -Force | Out-Null
Write-Host "Temp root: $script:Root"

$savedEnv = @{}
foreach ($k in @('LOCALAPPDATA', 'XRRFIX_HOME', 'XRRFIX_API', 'XRRFIX_REPO', 'XRRFIX_BLOCK_PROCS', 'XRRFIX_NO_NOTIFY')) { $savedEnv[$k] = [Environment]::GetEnvironmentVariable($k) }
$env:LOCALAPPDATA = $script:Lad
foreach ($k in @('XRRFIX_HOME', 'XRRFIX_API', 'XRRFIX_REPO')) { [Environment]::SetEnvironmentVariable($k, $null) }
$env:XRRFIX_BLOCK_PROCS = $script:FAKE_PROC
$env:XRRFIX_NO_NOTIFY = '1'

$t0 = Get-Date
try {
    if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) { throw 'git.exe not found in PATH' }
    Start-FakeGitHub
    Write-Host "Fake GitHub: $script:BaseUrl"

    . (Join-Path $PSScriptRoot 'cases_setup.ps1')
    . (Join-Path $PSScriptRoot 'cases_common.ps1')
    . (Join-Path $PSScriptRoot 'cases_peer.ps1')
    . (Join-Path $PSScriptRoot 'cases_host.ps1')
    . (Join-Path $PSScriptRoot 'cases_selfupdate.ps1')
    . (Join-Path $PSScriptRoot 'cases_e2e.ps1')
} catch {
    $script:XT.Fail++
    $script:XT.Failed += "suite setup: $($_.Exception.Message)"
    Write-Host "FAIL  suite: $($_.Exception.Message)" -ForegroundColor Red
} finally {
    Stop-AllChildren
    foreach ($k in $savedEnv.Keys) { [Environment]::SetEnvironmentVariable($k, $savedEnv[$k]) }
    if ($oldOutEnc) { try { [Console]::OutputEncoding = $oldOutEnc } catch { } }
    if ($KeepTemp) { Write-Host "Temp kept: $script:Root" }
    else {
        Get-ChildItem -LiteralPath $script:Root -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { -not $_.PSIsContainer -and $_.IsReadOnly } | ForEach-Object { try { $_.IsReadOnly = $false } catch { } }
        for ($i = 0; $i -lt 5 -and (Test-Path -LiteralPath $script:Root); $i++) {
            try { Remove-Item -LiteralPath $script:Root -Recurse -Force -ErrorAction Stop } catch { Start-Sleep -Milliseconds 500 }
        }
    }
}

$realAfter = Get-RealSnapshot
if ($realAfter -cne $realBefore) {
    $script:XT.Fail++
    $script:XT.Failed += 'SAFETY: real %LOCALAPPDATA%\xrrfix or the scheduled task changed during the run'
    Write-Host 'FAIL  SAFETY: real %LOCALAPPDATA%\xrrfix or the scheduled task changed during the run' -ForegroundColor Red
}
Write-Host ''
Write-Host ("EXPECTED-FAIL: {0} (XPASS: {1})" -f $script:XF.Fail, $script:XF.Pass) -ForegroundColor DarkYellow
$script:XF.Names | ForEach-Object { Write-Host "  ~ $_" -ForegroundColor DarkYellow }
Complete-Tests
